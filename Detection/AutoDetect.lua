-- PartyGatherRadar - Detection/AutoDetect.lua
-- Détection automatique des herbes et minerais affichés sur la minicarte, et partage au groupe.
--
-- Principe (API officielle propre à Forever, vérifiée en jeu le 2026-10-15) : toutes les 2 secondes, si le
-- pistage des herbes ou des minerais est actif, la minicarte est sondée point par point
-- (Minimap:SetUsingSoftCursor + Minimap:UpdateMouseoverAtPoint + C_TooltipInfo.GetMinimapMouseover), par lots
-- de 40 points par image. Chaque lot convertit ses points avec la position du joueur du moment : le balayage
-- reste juste pendant un déplacement. Seuls les noms reconnus comme herbe ou minerai sont gardés
-- (Detection/ResourceNames.lua).
--
-- Suivi : une ressource revue au même endroit garde son identifiant et sa position s'affine (moyenne). Elle
-- est envoyée au groupe à sa découverte, puis rafraîchie toutes les 25 s tant qu'elle reste visible. Absente
-- de 2 balayages alors qu'elle devrait être visible (pistage actif, bien à l'intérieur du rayon de la
-- minicarte) : elle est considérée récoltée ou disparue, retirée et signalée au groupe (REMOVE).
--
-- Jamais pendant un combat, jamais quand la souris survole la minicarte (infobulle native du joueur), jamais
-- sans pistage actif : aucun pistage n'est activé par l'addon.

local addonName, ns = ...

local AutoDetect = ns.NewModule("AutoDetect")
ns.AutoDetect = AutoDetect

local pairs, ipairs, type, tostring, pcall = pairs, ipairs, type, tostring, pcall
local sqrt, floor, max, min = math.sqrt, math.floor, math.max, math.min
local format = string.format

AutoDetect.PASS_INTERVAL = 2       -- secondes entre deux balayages
AutoDetect.GRID_SPACING = 10       -- unités du cadre Minimap (≈ 33 m au zoom minimal)
AutoDetect.POINTS_PER_FRAME = 40
AutoDetect.LINK_UNITS = 15         -- points d'un même nom voisins sur la grille (10 ; diagonale 14,1) : reliés
AutoDetect.CLUSTER_UNITS = 15      -- rayon de rapprochement avec une ressource suivie, en unités du cadre
AutoDetect.MATCH_MIN_YARDS = 25    -- rapprochement minimal avec une ressource déjà suivie
AutoDetect.MAX_WEIGHT = 20         -- poids maximal de l'historique dans la moyenne des positions
AutoDetect.RESEND_INTERVAL = 25    -- secondes : garde les marqueurs des autres « récents » (liveTTL 60 s)
AutoDetect.RESEND_MOVE_YARDS = 8   -- position affinée de plus de 8 m : renvoyée tout de suite
AutoDetect.MISS_LIMIT = 2          -- balayages consécutifs sans la ressource avant de la déclarer disparue
AutoDetect.INSIDE_FACTOR = 0.75    -- part du rayon de la minicarte où une absence est fiable
AutoDetect.MAX_NODES = 150         -- même borne que MarkerManager.MAX_REAL_PER_SENDER
AutoDetect.UNKNOWN_LOG_LIMIT = 30  -- noms inconnus journalisés (une fois chacun)

-- Sorts de récolte : le nom ciblé est une ressource (apprentissage des noms)
local GATHER_SPELLS = {
	[2366] = "HERB", [2368] = "HERB", [3570] = "HERB", [11993] = "HERB",
	[2575] = "ORE", [2576] = "ORE", [3564] = "ORE", [10248] = "ORE",
}
local HERB_GATHERING_SPELL, MINING_SPELL = 2366, 2575

local frame
local pass                 -- balayage en cours
local nodes = {}           -- [id] = ressource suivie
local nodeCount = 0
local nextId = 0
local sessionTag
local forceResend = false
local unknownNames = {}
local unknownCount = 0

AutoDetect.stats = { passes = 0, aborted = 0, lastAbort = nil, found = 0, gone = 0 }

---------------------------------------------------------------------------
-- Conditions
---------------------------------------------------------------------------

--- Types de ressources dont le pistage est actif : { HERB = bool, ORE = bool } ou nil si aucun.
local function ActiveKinds()
	local state = ns.Tracking.GetTrackingState()
	if not state.available then
		return nil
	end
	local herbs = state.herbs ~= nil and state.herbs.active
	local ores = state.ores ~= nil and state.ores.active
	if not (herbs or ores) then
		return nil
	end
	return { HERB = herbs and true or false, ORE = ores and true or false }
end

--- Vrai si un balayage peut avoir lieu maintenant ; sinon false, raison.
function AutoDetect.CanScan()
	if not ns.Config.Get("enabled") or not ns.Config.Get("autoDetect") then
		return false, "disabled"
	end
	if not ns.Tracking.ProbeApisAvailable() then
		return false, "api"
	end
	if ns.Tracking.IsScanRunning() then
		return false, "probe"
	end
	if InCombatLockdown and InCombatLockdown() then
		return false, "combat"
	end
	if not Minimap:IsVisible() then
		return false, "hidden"
	end
	if Minimap:IsMouseOver() then
		return false, "mouse"
	end
	return true
end

---------------------------------------------------------------------------
-- Ressources suivies
---------------------------------------------------------------------------

local function NewId()
	nextId = nextId + 1
	return format("%s%x", sessionTag, nextId)
end

local function Yards(width, height, x1, y1, x2, y2)
	local dx, dy = (x2 - x1) * width, (y2 - y1) * height
	return sqrt(dx * dx + dy * dy)
end

local function RemoveNode(node)
	nodes[node.id] = nil
	nodeCount = nodeCount - 1
end

--- Regroupe les points touchés par nom, dans l'espace de la carte (mètres). Deux points du même nom sont
--- reliés s'ils sont voisins sur la grille (diagonale comprise) : une ressource touchée sur plusieurs points
--- donne un seul groupe, quelle que soit sa forme. Un regroupement autour d'un centre mobile découpait un
--- même point en plusieurs repères (constaté en jeu le 2026-10-15). Renvoie une liste de
--- { name, kind, x, y, hits, spread, yardsPerUnit }.
function AutoDetect.ClusterHits(hits, width, height)
	-- union-find sur les points
	local parent = {}
	local function Root(i)
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end
	for i = 1, #hits do
		parent[i] = i
	end
	for i = 1, #hits do
		local a = hits[i]
		local link = AutoDetect.LINK_UNITS * a.yardsPerUnit
		for j = i + 1, #hits do
			local b = hits[j]
			if a.name == b.name and Yards(width, height, a.x, a.y, b.x, b.y) <= link then
				local ra, rb = Root(i), Root(j)
				if ra ~= rb then
					parent[rb] = ra
				end
			end
		end
	end
	local byRoot, clusters = {}, {}
	for i, hit in ipairs(hits) do
		local root = Root(i)
		local cluster = byRoot[root]
		if not cluster then
			cluster = { name = hit.name, kind = hit.kind, sumX = 0, sumY = 0, hits = 0, points = {},
				yardsPerUnit = hit.yardsPerUnit }
			byRoot[root] = cluster
			clusters[#clusters + 1] = cluster
		end
		cluster.sumX = cluster.sumX + hit.x
		cluster.sumY = cluster.sumY + hit.y
		cluster.hits = cluster.hits + 1
		cluster.points[#cluster.points + 1] = hit
	end
	for _, cluster in ipairs(clusters) do
		cluster.x, cluster.y = cluster.sumX / cluster.hits, cluster.sumY / cluster.hits
		local spread = 0
		for _, point in ipairs(cluster.points) do
			spread = max(spread, Yards(width, height, cluster.x, cluster.y, point.x, point.y))
		end
		cluster.spread = spread
		cluster.points = nil
	end
	return clusters
end

local function FindNode(cluster, mapID, width, height)
	local limit = max(AutoDetect.MATCH_MIN_YARDS, AutoDetect.CLUSTER_UNITS * cluster.yardsPerUnit)
	local best, bestDistance
	for _, node in pairs(nodes) do
		if node.mapID == mapID and node.name == cluster.name then
			local distance = Yards(width, height, node.x, node.y, cluster.x, cluster.y)
			if distance <= limit and (not bestDistance or distance < bestDistance) then
				best, bestDistance = node, distance
			end
		end
	end
	return best
end

local function Accuracy(cluster)
	return cluster.spread + AutoDetect.GRID_SPACING * cluster.yardsPerUnit / 2
end

local function OldestNode()
	local oldest
	for _, node in pairs(nodes) do
		if not oldest or node.lastSeen < oldest.lastSeen then
			oldest = node
		end
	end
	return oldest
end

local function CreateNode(cluster, mapID, now)
	if nodeCount >= AutoDetect.MAX_NODES then
		local oldest = OldestNode()
		if oldest then
			RemoveNode(oldest)
		end
	end
	local node = {
		id = NewId(), name = cluster.name, kind = cluster.kind, mapID = mapID, x = cluster.x, y = cluster.y,
		weight = cluster.hits, accuracy = Accuracy(cluster), firstSeen = now, lastSeen = now, misses = 0,
	}
	nodes[node.id] = node
	nodeCount = nodeCount + 1
	AutoDetect.stats.found = AutoDetect.stats.found + 1
	ns.Diagnostics.Log("DETECT", "%s : %s, carte %d (%.2f, %.2f) ±%.0f m", node.kind == "HERB" and "herbe" or "minerai",
		node.name, mapID, node.x * 100, node.y * 100, node.accuracy)
	return node
end

local function UpdateNode(node, cluster, now)
	local weight = min(node.weight, AutoDetect.MAX_WEIGHT)
	local total = weight + cluster.hits
	node.x = (node.x * weight + cluster.x * cluster.hits) / total
	node.y = (node.y * weight + cluster.y * cluster.hits) / total
	node.weight = total
	node.accuracy = min(node.accuracy, Accuracy(cluster))
	node.lastSeen = now
	node.misses = 0
end

--- Marqueur local (jamais affiché sur sa propre minicarte, sauf réglage showOwnDetections) et envoi au groupe.
local function Publish(node, sender, now, width, height)
	ns.MarkerManager.Upsert({
		sender = sender, id = node.id, source = "LIVE", kind = node.kind,
		state = node.sentOnce and "UPDATED" or "DETECTED", uiMapID = node.mapID, x = node.x, y = node.y,
		accuracy = node.accuracy, name = node.name, isLocal = true,
	}, now)
	local due = not node.lastSent or forceResend or now - node.lastSent >= AutoDetect.RESEND_INTERVAL
		or Yards(width, height, node.sentX, node.sentY, node.x, node.y) >= AutoDetect.RESEND_MOVE_YARDS
	if not due then
		return
	end
	local ok = ns.Sender.SendNode({
		id = node.id, source = "LIVE", kind = node.kind, state = node.sentOnce and "UPDATED" or "DETECTED",
		uiMapID = node.mapID, x = node.x, y = node.y, accuracy = node.accuracy, age = 0, resourceID = 0,
		name = node.name,
	})
	if ok then
		node.lastSent, node.sentX, node.sentY, node.sentOnce = now, node.x, node.y, true
	end
end

local function Gone(node, sender)
	ns.MarkerManager.Remove(sender, node.id, false)
	if node.sentOnce then
		ns.Sender.SendRemove(node.id, "GATHERED")
	end
	RemoveNode(node)
	AutoDetect.stats.gone = AutoDetect.stats.gone + 1
	ns.Diagnostics.Log("DETECT", "disparu : %s, carte %d (%.2f, %.2f)", node.name, node.mapID, node.x * 100,
		node.y * 100)
end

--- Ressources absentes de ce balayage alors qu'elles auraient dû y figurer.
local function CheckMisses(current, context, matched, sender)
	local limit = context.radius * AutoDetect.INSIDE_FACTOR
	local missing = {}
	for id, node in pairs(nodes) do
		if not matched[id] and node.mapID == context.mapID and current.kinds[node.kind]
			and Yards(context.mapWidth, context.mapHeight, context.playerX, context.playerY, node.x, node.y) <= limit then
			node.misses = node.misses + 1
			if node.misses >= AutoDetect.MISS_LIMIT then
				missing[#missing + 1] = node
			end
		end
	end
	for _, node in ipairs(missing) do
		Gone(node, sender)
	end
	return #missing
end

--- Oublie les ressources dont le marqueur a expiré (plus revues depuis liveTTL + uncertainTTL).
local function PruneExpired(now)
	local limit = ns.Config.Get("liveTTL") + ns.Config.Get("uncertainTTL")
	local expired = {}
	for _, node in pairs(nodes) do
		if now - node.lastSeen > limit then
			expired[#expired + 1] = node
		end
	end
	for _, node in ipairs(expired) do
		RemoveNode(node)
	end
end

---------------------------------------------------------------------------
-- Balayage
---------------------------------------------------------------------------

local function NoteUnknown(name)
	if unknownNames[name] or unknownCount >= AutoDetect.UNKNOWN_LOG_LIMIT then
		return
	end
	unknownNames[name] = true
	unknownCount = unknownCount + 1
	ns.Diagnostics.Log("DETECT", "nom ignoré (ni herbe ni minerai connus) : %s", name)
end

local function StopFrame()
	if frame then
		frame:SetScript("OnUpdate", nil)
	end
end

--- Interrompt le balayage en cours (résultats partiels abandonnés).
function AutoDetect.Abort(reason)
	if not pass then
		return
	end
	pass = nil
	StopFrame()
	AutoDetect.stats.aborted = AutoDetect.stats.aborted + 1
	AutoDetect.stats.lastAbort = tostring(reason)
end

local function Finish()
	local current = pass
	pass = nil
	StopFrame()
	local now = ns.Now()
	local context = current.context
	local sender = ns.GetPlayerFullName()
	AutoDetect.stats.passes = AutoDetect.stats.passes + 1
	if not context or not sender then
		return
	end
	local width, height = context.mapWidth, context.mapHeight
	local matched = {}
	for _, cluster in ipairs(AutoDetect.ClusterHits(current.hits, width, height)) do
		local node = FindNode(cluster, context.mapID, width, height)
		if node then
			UpdateNode(node, cluster, now)
		else
			node = CreateNode(cluster, context.mapID, now)
		end
		matched[node.id] = true
		Publish(node, sender, now, width, height)
	end
	forceResend = false
	local gone = CheckMisses(current, context, matched, sender)
	PruneExpired(now)
	if next(matched) or gone > 0 then
		ns.Fire("PGR_MARKERS_CHANGED")
	end
end

local function Step()
	local ok, reason = AutoDetect.CanScan()
	if not ok then
		return AutoDetect.Abort(reason)
	end
	local context, why = ns.Tracking.GetProjectionContext()
	if not context then
		return AutoDetect.Abort(why)
	end
	if context.mapID ~= pass.mapID then
		return AutoDetect.Abort("map")
	end
	local scale = Minimap:GetEffectiveScale()
	local centerX = Minimap:GetLeft() + Minimap:GetWidth() / 2
	local centerY = Minimap:GetBottom() + Minimap:GetHeight() / 2
	local points = pass.points
	local last = min(pass.index + AutoDetect.POINTS_PER_FRAME - 1, #points)
	local cursorOk, cursorErr = pcall(Minimap.SetUsingSoftCursor, Minimap, true)
	if not cursorOk then
		return AutoDetect.Abort(cursorErr)
	end
	local failure
	for i = pass.index, last do
		local point = points[i]
		local probeOk, names, readError = pcall(ns.Tracking.ProbePoint, point[1], point[2], scale, centerX, centerY)
		if not probeOk then
			failure = names
			break
		end
		if not names then
			failure = readError
			break
		end
		for _, name in ipairs(names) do
			local kind = ns.ResourceNames.Classify(name)
			if kind then
				local _, x, y, yardsPerUnit = ns.Tracking.MinimapOffsetToMap(point[1], point[2], context)
				pass.hits[#pass.hits + 1] = { name = name, kind = kind, x = x, y = y, yardsPerUnit = yardsPerUnit }
			else
				NoteUnknown(name)
			end
		end
	end
	pcall(Minimap.SetUsingSoftCursor, Minimap, false)
	if failure then
		return AutoDetect.Abort(failure)
	end
	pass.index = last + 1
	pass.context = context -- position du joueur à la fin du balayage : sert aux absences
	if pass.index > #points then
		Finish()
	end
end

local function OnUpdate()
	local ok, err = pcall(Step)
	if not ok then
		pcall(Minimap.SetUsingSoftCursor, Minimap, false)
		AutoDetect.Abort(err)
		ns.OnModuleError("AutoDetect", err)
	end
end

--- Lance un balayage si les conditions sont réunies. Renvoie true s'il a démarré.
function AutoDetect.StartPass()
	if pass or not frame then
		return false
	end
	if not AutoDetect.CanScan() then
		return false
	end
	local kinds = ActiveKinds()
	if not kinds or not ns.GetPlayerFullName() then
		return false
	end
	local context = ns.Tracking.GetProjectionContext()
	if not context then
		return false
	end
	pass = {
		kinds = kinds, mapID = context.mapID, index = 1, hits = {},
		points = ns.Tracking.BuildGrid(context.halfWidth, context.halfHeight, AutoDetect.GRID_SPACING),
	}
	frame:SetScript("OnUpdate", OnUpdate)
	return true
end

---------------------------------------------------------------------------
-- Apprentissage des noms à la récolte
---------------------------------------------------------------------------

local function GatherKind(spellID)
	local kind = GATHER_SPELLS[spellID]
	if kind then
		return kind
	end
	-- autres rangs ou identifiants propres à Forever : comparaison avec le nom localisé du sort
	if C_Spell and C_Spell.GetSpellName then
		local name = C_Spell.GetSpellName(spellID)
		if type(name) == "string" and not ns.IsSecret(name) then
			if name == C_Spell.GetSpellName(HERB_GATHERING_SPELL) then
				return "HERB"
			elseif name == C_Spell.GetSpellName(MINING_SPELL) then
				return "ORE"
			end
		end
	end
	return nil
end

local function OnSpellcastSent(_, unit, target, _, spellID)
	if ns.AnySecret(unit, target, spellID) or unit ~= "player" or type(target) ~= "string" or target == "" then
		return
	end
	local kind = GatherKind(spellID)
	if kind and ns.ResourceNames.Learn(kind, target) then
		ns.Diagnostics.Log("DETECT", "nom appris à la récolte : %s (%s)", target, kind == "HERB" and "herbe" or "minerai")
	end
end

---------------------------------------------------------------------------
-- Diagnostics et accès
---------------------------------------------------------------------------

function AutoDetect.GetNodeCount()
	return nodeCount
end

function AutoDetect.IsRunning()
	return pass ~= nil
end

--- Résumé pour /pgr status et /pgr diag.
function AutoDetect.Describe()
	local stats = AutoDetect.stats
	return format("%d balayage(s), %d interrompu(s)%s, %d ressource(s) suivie(s), %d trouvée(s), %d disparue(s), "
		.. "%d nom(s) ignoré(s)", stats.passes, stats.aborted,
		stats.lastAbort and (" (dernier : " .. stats.lastAbort .. ")") or "", nodeCount, stats.found, stats.gone,
		unknownCount)
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

ns.On("PGR_CONFIG_LOADED", "AutoDetect", function()
	if frame then
		return
	end
	frame = CreateFrame("Frame")
	-- identifiants uniques d'une session à l'autre (un /reload ne réutilise pas ceux d'avant)
	sessionTag = format("%x", floor(ns.Now() * 10) % 65536)
	ns.NewTicker(AutoDetect.PASS_INTERVAL, "AutoDetect", AutoDetect.StartPass)
	ns.RegisterEvent("UNIT_SPELLCAST_SENT", "AutoDetect", OnSpellcastSent)
end)

ns.On("PGR_SETTING_CHANGED", "AutoDetect", function(_, key, value)
	if (key == "autoDetect" or key == "enabled") and not value then
		AutoDetect.Abort("disabled")
	end
end)

-- nouveau membre ou retour d'un membre : nos ressources visibles lui sont renvoyées au prochain balayage
ns.On("PGR_PEERS_CHANGED", "AutoDetect", function()
	forceResend = true
end)
