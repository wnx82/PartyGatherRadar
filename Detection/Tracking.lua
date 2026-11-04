-- PartyGatherRadar - Detection/Tracking.lua
-- État du pistage natif (Découverte d'herbes / de gisements) et SONDES de détection (phase 0).
--
-- Constat de faisabilité : aucune API ne liste les points de pistage dessinés sur la minicarte.
-- Le client Forever 1.60.1 expose en revanche trois fonctions officielles (expérimentales) :
--   Minimap:SetUsingSoftCursor(bool)            -- curseur logiciel de la minicarte
--   Minimap:UpdateMouseoverAtPoint(x, y)        -- survol simulé d'un point, en pixels écran
--   C_TooltipInfo.GetMinimapMouseover()         -- noms des points situés sous ce survol
-- Les sondes ci-dessous les utilisent uniquement à la demande (/pgr probe ...), hors combat,
-- jamais pendant que le vrai curseur survole la minicarte. Elles n'activent aucun pistage et
-- ne déplacent pas le personnage. Le module de détection continue est prévu en phase 2.

local addonName, ns = ...

local Tracking = ns.NewModule("Tracking")
ns.Tracking = Tracking

local type, pairs, ipairs, tostring, pcall = type, pairs, ipairs, tostring, pcall
local sqrt, floor, cos, sin = math.sqrt, math.floor, math.cos, math.sin
local format = string.format

local FIND_HERBS_SPELL = 2383
local FIND_MINERALS_SPELL = 2580

local SCAN_SPACING = 10        -- espacement de la grille, en unités du cadre Minimap
local SCAN_POINTS_PER_FRAME = 40
local SCAN_CLUSTER_RADIUS = 15 -- deux points touchés à moins de 15 unités appartiennent au même repère
local SCAN_MAX_MOVE_YARDS = 2  -- au-delà, le joueur a bougé pendant le balayage : résultats faux
local SCAN_MAX_TURN = 0.05     -- radians, minicarte tournante
local SCAN_MAX_WAIT = 3        -- secondes d'attente maximale si la souris survole la minicarte
local PASSIVE_INTERVAL = 0.2

---------------------------------------------------------------------------
-- Pistage natif
---------------------------------------------------------------------------

local function SpellName(spellID)
	if C_Spell and C_Spell.GetSpellName then
		local name = C_Spell.GetSpellName(spellID)
		if type(name) == "string" and not ns.IsSecret(name) then
			return name
		end
	end
	return nil
end

local function ReadTrackingInfo(index)
	local a, b, c, d, e, f = C_Minimap.GetTrackingInfo(index)
	if type(a) == "table" then
		return a
	end
	-- ancien format à valeurs multiples
	return { name = a, texture = b, active = c, type = d, subType = e, spellID = f }
end

--- État du pistage : { available, reason, count, herbs = {name, active}|nil, ores = {name, active}|nil }.
function Tracking.GetTrackingState()
	if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then
		return { available = false, reason = "api" }
	end
	local count = C_Minimap.GetNumTrackingTypes()
	if type(count) ~= "number" or ns.IsSecret(count) then
		return { available = false, reason = "secret" }
	end
	local herbName, oreName = SpellName(FIND_HERBS_SPELL), SpellName(FIND_MINERALS_SPELL)
	local state = { available = true, count = count }
	for i = 1, count do
		local ok, info = pcall(ReadTrackingInfo, i)
		if ok and not ns.IsSecret(info) and type(info) == "table"
			and not ns.AnySecret(info.name, info.active, info.spellID) then
			local isHerb = info.spellID == FIND_HERBS_SPELL or (herbName ~= nil and info.name == herbName)
			local isOre = info.spellID == FIND_MINERALS_SPELL or (oreName ~= nil and info.name == oreName)
			if isHerb then
				state.herbs = { name = info.name, active = info.active and true or false }
			elseif isOre then
				state.ores = { name = info.name, active = info.active and true or false }
			end
		end
	end
	return state
end

---------------------------------------------------------------------------
-- Lecture de l'infobulle de minicarte
---------------------------------------------------------------------------

--- Retire les codes de couleur, textures et atlas d'une ligne d'infobulle.
function Tracking.StripCodes(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
	text = text:gsub("|cn[^:]*:", "")
	text = text:gsub("|r", "")
	text = text:gsub("|T.-|t", "")
	text = text:gsub("|A.-|a", "")
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Noms présents dans l'infobulle de minicarte courante (table, éventuellement vide) ou nil, raison.
function Tracking.ReadMinimapMouseover()
	if not (C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover) then
		return nil, "api"
	end
	local data = C_TooltipInfo.GetMinimapMouseover()
	-- valeurs secrètes testées avant toute comparaison
	if ns.IsSecret(data) then
		return nil, "secret"
	end
	if data == nil then
		return {}
	end
	if type(data) ~= "table" or ns.IsSecret(data.lines) then
		return nil, "secret"
	end
	local names = {}
	for _, line in ipairs(data.lines or {}) do
		if ns.IsSecret(line) or ns.IsSecret(line.leftText) then
			return nil, "secret"
		end
		local text = line.leftText
		if text ~= nil then
			for part in tostring(text):gmatch("[^\n]+") do
				local name = Tracking.StripCodes(part)
				if name ~= "" then
					names[#names + 1] = name
				end
			end
		end
	end
	return names
end

local function ProbeApisAvailable()
	return Minimap ~= nil and Minimap.UpdateMouseoverAtPoint ~= nil and Minimap.SetUsingSoftCursor ~= nil
		and C_TooltipInfo ~= nil and C_TooltipInfo.GetMinimapMouseover ~= nil
end

--- Liste des fonctions de sondage de minicarte présentes dans le client (pour les diagnostics).
function Tracking.FindBlipApis()
	local found = {}
	if Minimap and Minimap.UpdateMouseoverAtPoint then
		found[#found + 1] = "Minimap:UpdateMouseoverAtPoint"
	end
	if Minimap and Minimap.SetUsingSoftCursor then
		found[#found + 1] = "Minimap:SetUsingSoftCursor"
	end
	if C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover then
		found[#found + 1] = "C_TooltipInfo.GetMinimapMouseover"
	end
	return found
end

---------------------------------------------------------------------------
-- Conversion d'un point de la minicarte en position de carte
---------------------------------------------------------------------------

--- Convertit un décalage (unités du cadre Minimap, relatif au centre) en position de carte.
--- Renvoie mapID, x, y, mètresParUnité — ou nil, raison.
function Tracking.MinimapOffsetToMap(dx, dy, context)
	local yardsPerUnitX = context.radius / context.halfWidth
	local yardsPerUnitY = context.radius / context.halfHeight
	local px, py = dx * yardsPerUnitX, dy * yardsPerUnitY
	local east, north = px, py
	if context.facing then
		-- inverse de la rotation appliquée par Coordinates.ProjectToMinimap
		local c, s = cos(context.facing), sin(context.facing)
		east = px * c - py * s
		north = px * s + py * c
	end
	local x, y = ns.Coordinates.ApplyOffset(context.mapWidth, context.mapHeight, context.playerX, context.playerY,
		east, north)
	return context.mapID, x, y, (yardsPerUnitX + yardsPerUnitY) / 2
end

--- Contexte de projection courant (position du joueur, rayon, rotation) ou nil, raison.
function Tracking.GetProjectionContext()
	local mapID, playerX, playerY = ns.Coordinates.GetPlayerMapPosition()
	if not mapID then
		return nil, playerX
	end
	local width, height = ns.Coordinates.GetMapSizeYards(mapID)
	if not width then
		return nil, "mapsize"
	end
	local radius, source = ns.Coordinates.GetMinimapRadiusYards()
	if not radius then
		return nil, source
	end
	local facing
	if ns.GetCVar("rotateMinimap") == "1" then
		facing = GetPlayerFacing and GetPlayerFacing()
		if ns.IsSecret(facing) or facing == nil then
			return nil, "facing"
		end
	end
	return {
		mapID = mapID, playerX = playerX, playerY = playerY, mapWidth = width, mapHeight = height,
		radius = radius, facing = facing, halfWidth = Minimap:GetWidth() / 2, halfHeight = Minimap:GetHeight() / 2,
	}
end

---------------------------------------------------------------------------
-- Sonde passive : lecture de l'infobulle quand le joueur survole lui-même la minicarte
---------------------------------------------------------------------------

local passiveFrame
local passiveElapsed, passiveLastText = 0, nil

local function PassiveUpdate(_, elapsed)
	passiveElapsed = passiveElapsed + elapsed
	if passiveElapsed < PASSIVE_INTERVAL then
		return
	end
	passiveElapsed = 0
	if not (Minimap and Minimap:IsVisible() and Minimap:IsMouseOver()) then
		passiveLastText = nil
		return
	end
	local names, reason = Tracking.ReadMinimapMouseover()
	if not names then
		ns.Diagnostics.Log("SONDE", "infobulle de minicarte illisible : %s", tostring(reason))
		return
	end
	local text = table.concat(names, " / ")
	if text == "" or text == passiveLastText then
		return
	end
	passiveLastText = text
	ns.Diagnostics.SetFlag("minimapTooltipSeen", text)

	-- position estimée sous le curseur
	local context = Tracking.GetProjectionContext()
	if context and GetCursorPosition then
		local cursorX, cursorY = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		local centerX, centerY = Minimap:GetCenter()
		local dx, dy = cursorX / scale - centerX, cursorY / scale - centerY
		local mapID, x, y, yardsPerUnit = Tracking.MinimapOffsetToMap(dx, dy, context)
		ns.Print(ns.T("PROBE_PASSIVE_HIT", text, mapID, x * 100, y * 100, SCAN_CLUSTER_RADIUS * yardsPerUnit))
	else
		ns.Print(ns.T("PROBE_PASSIVE_HIT_NOPOS", text))
	end
end

function Tracking.TogglePassiveProbe()
	if not passiveFrame then
		passiveFrame = CreateFrame("Frame")
	end
	if passiveFrame:GetScript("OnUpdate") then
		passiveFrame:SetScript("OnUpdate", nil)
		ns.UnregisterEvent("UNIT_SPELLCAST_SENT", "Tracking")
		ns.Print(ns.T("PROBE_PASSIVE_OFF"))
		return false
	end
	passiveElapsed, passiveLastText = 0, nil
	ns.RegisterEvent("UNIT_SPELLCAST_SENT", "Tracking", Tracking.LogSpellcastSent)
	passiveFrame:SetScript("OnUpdate", function(...)
		ns.SafeCall("Tracking", PassiveUpdate, ...)
	end)
	ns.Print(ns.T("PROBE_PASSIVE_ON"))
	return true
end

---------------------------------------------------------------------------
-- Sonde active : balayage unique de la minicarte par le curseur logiciel (expérimental)
---------------------------------------------------------------------------

local scanFrame
local scan -- état du balayage en cours

--- Grille de points (unités du cadre Minimap, relatives au centre) couvrant le disque de la minicarte.
local function BuildGrid(halfWidth, halfHeight, spacing)
	spacing = spacing or SCAN_SPACING
	local points = {}
	local radius = math.min(halfWidth, halfHeight) - 4
	local steps = floor(radius / spacing)
	for i = -steps, steps do
		for j = -steps, steps do
			local dx, dy = i * spacing, j * spacing
			if dx * dx + dy * dy <= radius * radius then
				points[#points + 1] = { dx, dy }
			end
		end
	end
	return points
end

local function ProbePoint(dx, dy, scale, centerX, centerY)
	Minimap:UpdateMouseoverAtPoint((centerX + dx) * scale, (centerY + dy) * scale)
	return Tracking.ReadMinimapMouseover()
end

-- partagés avec la détection automatique (Detection/AutoDetect.lua)
Tracking.ProbeApisAvailable = ProbeApisAvailable
Tracking.BuildGrid = BuildGrid
Tracking.ProbePoint = ProbePoint

--- Vrai pendant un balayage manuel (/pgr probe scan).
function Tracking.IsScanRunning()
	return scan ~= nil
end

--- Regroupe les points touchés par nom ; renvoie une liste { name, dx, dy, hits, spread }.
function Tracking.ClusterHits(hits)
	local clusters = {}
	for _, hit in ipairs(hits) do
		local target
		for _, cluster in ipairs(clusters) do
			if cluster.name == hit.name then
				local cx, cy = cluster.sumX / cluster.hits, cluster.sumY / cluster.hits
				if sqrt((hit.dx - cx) ^ 2 + (hit.dy - cy) ^ 2) <= SCAN_CLUSTER_RADIUS then
					target = cluster
					break
				end
			end
		end
		if not target then
			target = { name = hit.name, sumX = 0, sumY = 0, hits = 0, points = {} }
			clusters[#clusters + 1] = target
		end
		target.sumX = target.sumX + hit.dx
		target.sumY = target.sumY + hit.dy
		target.hits = target.hits + 1
		target.points[#target.points + 1] = hit
	end
	for _, cluster in ipairs(clusters) do
		cluster.dx, cluster.dy = cluster.sumX / cluster.hits, cluster.sumY / cluster.hits
		local spread = 0
		for _, p in ipairs(cluster.points) do
			local d = sqrt((p.dx - cluster.dx) ^ 2 + (p.dy - cluster.dy) ^ 2)
			if d > spread then
				spread = d
			end
		end
		cluster.spread = spread
		cluster.points = nil
	end
	return clusters
end

local function FinishScan(aborted)
	scanFrame:SetScript("OnUpdate", nil)
	local current = scan
	scan = nil
	if aborted then
		ns.Print(ns.T("PROBE_SCAN_ABORTED", aborted))
		ns.Diagnostics.Log("SONDE", "balayage interrompu : %s", aborted)
		return
	end
	local clusters = Tracking.ClusterHits(current.hits)
	ns.Diagnostics.SetFlag("minimapScanResult", format("%d point(s), %d repère(s)", #current.points, #clusters))
	ns.Print(ns.T("PROBE_SCAN_DONE", #current.points, #clusters, (ns.Now() - current.startedAt) * 1000))
	-- journal : une ligne par herbe ou minerai, un seul résumé pour le reste (zones de quête, joueurs...),
	-- sinon un balayage remplit le journal sauvegardé (300 lignes)
	local others, otherOrder = {}, {}
	for _, cluster in ipairs(clusters) do
		if not ns.ResourceNames.Classify(cluster.name) then
			if not others[cluster.name] then
				otherOrder[#otherOrder + 1] = cluster.name
			end
			others[cluster.name] = (others[cluster.name] or 0) + 1
		end
	end
	local summary = {}
	for _, name in ipairs(otherOrder) do
		summary[#summary + 1] = format("%s x%d", name, others[name])
	end
	ns.Diagnostics.Log("SONDE", "balayage : %d point(s), %d repère(s) ; hors ressources : %s", #current.points,
		#clusters, #summary > 0 and ns.Utf8Truncate(table.concat(summary, ", "), 400) or "aucun")
	local scanTag = floor(current.startedAt)
	local placed = 0
	for index, cluster in ipairs(clusters) do
		local mapID, x, y, yardsPerUnit = Tracking.MinimapOffsetToMap(cluster.dx, cluster.dy, current.context)
		local accuracy = (cluster.spread + SCAN_SPACING) * yardsPerUnit
		ns.Print(ns.T("PROBE_SCAN_HIT", cluster.name, x * 100, y * 100, accuracy, cluster.hits))
		if not others[cluster.name] then
			ns.Diagnostics.Log("SONDE", "repère '%s' carte %d (%.2f, %.2f) ±%.0f m, %d touche(s)", cluster.name, mapID,
				x * 100, y * 100, accuracy, cluster.hits)
		end
		ns.Diagnostics.SetFlag("minimapTooltipSeen", cluster.name)
		-- marqueur local de calibration : source TEST, jamais partagé. Superposé au point natif,
		-- il valide visuellement la chaîne minicarte -> carte -> minicarte.
		if ns.MarkerManager then
			local marker = ns.MarkerManager.Upsert({
				sender = ns.GetPlayerFullName() or "?", id = format("s%d_%d", scanTag, index),
				source = "TEST", kind = "TEST", state = "DETECTED", uiMapID = mapID, x = x, y = y,
				name = ns.T("PROBE_MARKER_NAME", cluster.name), accuracy = accuracy, isLocal = true,
			})
			if marker then
				placed = placed + 1
			end
		end
	end
	-- un repère au bord de la carte (coordonnées hors 0..1) est refusé : seul le nombre réel est annoncé
	ns.Print(ns.T("PROBE_SCAN_MARKERS", placed, #clusters))
	ns.Fire("PGR_MARKERS_CHANGED")
end

--- Raison d'abandon si le joueur a bougé, tourné ou changé de zoom depuis le début du balayage.
local function ContextChanged(start)
	local now, reason = Tracking.GetProjectionContext()
	if not now then
		return ns.T("PROBE_REASON_POSITION", tostring(reason))
	end
	if now.mapID ~= start.mapID or now.radius ~= start.radius or now.halfWidth ~= start.halfWidth then
		return ns.T("PROBE_REASON_MOVED")
	end
	local east, north = ns.Coordinates.OffsetYards(start.mapWidth, start.mapHeight, start.playerX, start.playerY,
		now.playerX, now.playerY)
	if east * east + north * north > SCAN_MAX_MOVE_YARDS * SCAN_MAX_MOVE_YARDS then
		return ns.T("PROBE_REASON_MOVED")
	end
	if (start.facing or now.facing) and math.abs((now.facing or 0) - (start.facing or 0)) > SCAN_MAX_TURN then
		return ns.T("PROBE_REASON_MOVED")
	end
	return nil
end

local function ScanStep()
	if InCombatLockdown and InCombatLockdown() then
		return FinishScan(ns.T("PROBE_REASON_COMBAT"))
	end
	if not Minimap:IsVisible() then
		return FinishScan(ns.T("PROBE_REASON_HIDDEN"))
	end
	if Minimap:IsMouseOver() then
		-- le joueur survole la minicarte : on attend qu'il la quitte, mais pas indéfiniment
		scan.waitingSince = scan.waitingSince or ns.Now()
		if ns.Now() - scan.waitingSince > SCAN_MAX_WAIT then
			return FinishScan(ns.T("PROBE_REASON_MOUSE"))
		end
		return
	end
	scan.waitingSince = nil
	local changed = ContextChanged(scan.context)
	if changed then
		return FinishScan(changed)
	end
	local scale = Minimap:GetEffectiveScale()
	local centerX = Minimap:GetLeft() + Minimap:GetWidth() / 2
	local centerY = Minimap:GetBottom() + Minimap:GetHeight() / 2
	local points = scan.points
	local last = math.min(scan.index + SCAN_POINTS_PER_FRAME - 1, #points)
	local ok, err = pcall(Minimap.SetUsingSoftCursor, Minimap, true)
	if not ok then
		return FinishScan(tostring(err))
	end
	for i = scan.index, last do
		local point = points[i]
		local probeOk, names, reason = pcall(ProbePoint, point[1], point[2], scale, centerX, centerY)
		if not probeOk then
			pcall(Minimap.SetUsingSoftCursor, Minimap, false)
			return FinishScan(tostring(names))
		end
		if not names then
			pcall(Minimap.SetUsingSoftCursor, Minimap, false)
			return FinishScan(tostring(reason))
		end
		for _, name in ipairs(names) do
			scan.hits[#scan.hits + 1] = { name = name, dx = point[1], dy = point[2] }
		end
	end
	pcall(Minimap.SetUsingSoftCursor, Minimap, false)
	scan.index = last + 1
	if scan.index > #points then
		FinishScan()
	end
end

--- Lance un balayage unique. Renvoie false et une raison si impossible.
function Tracking.StartScanProbe()
	if scan then
		return false, ns.T("PROBE_REASON_RUNNING")
	end
	if not ProbeApisAvailable() then
		return false, ns.T("PROBE_REASON_API")
	end
	-- le balayage manuel prend la main sur la détection automatique (même curseur logiciel)
	if ns.AutoDetect then
		ns.AutoDetect.Abort("probe")
	end
	if InCombatLockdown and InCombatLockdown() then
		return false, ns.T("PROBE_REASON_COMBAT")
	end
	if not Minimap:IsVisible() then
		return false, ns.T("PROBE_REASON_HIDDEN")
	end
	local context, reason = Tracking.GetProjectionContext()
	if not context then
		return false, ns.T("PROBE_REASON_POSITION", tostring(reason))
	end
	scan = {
		context = context,
		points = BuildGrid(context.halfWidth, context.halfHeight),
		index = 1,
		hits = {},
		startedAt = ns.Now(),
	}
	if not scanFrame then
		scanFrame = CreateFrame("Frame")
	end
	scanFrame:SetScript("OnUpdate", function()
		local ok, err = pcall(ScanStep)
		if not ok then
			pcall(Minimap.SetUsingSoftCursor, Minimap, false)
			ns.OnModuleError("Tracking", err)
			if scan then
				FinishScan(tostring(err))
			end
		end
	end)
	ns.Print(ns.T("PROBE_SCAN_START", #scan.points))
	return true
end

--- Journalise les commandes de récolte (cible du sort) pour étudier la détection par récolte (phase 2).
function Tracking.LogSpellcastSent(_, unit, target, castGUID, spellID)
	if ns.AnySecret(unit, target, spellID) then
		ns.Diagnostics.Log("SONDE", "UNIT_SPELLCAST_SENT : valeur secrète")
		return
	end
	if unit ~= "player" then
		return
	end
	ns.Diagnostics.Log("SONDE", "UNIT_SPELLCAST_SENT sort %s cible '%s'", tostring(spellID), tostring(target))
end
