-- PartyGatherRadar - Map/MinimapOverlay.lua
-- Couche d'icônes personnalisées posée sur la minicarte, indépendante du pistage natif.
--
-- Placement : position du joueur (C_Map) + position du marqueur convertie dans la carte courante,
-- décalage en mètres, mis à l'échelle par le rayon de vue (C_Minimap.GetViewRadius), rotation de
-- la minicarte prise en compte seulement si l'orientation du joueur est accessible.
-- Si une donnée manque (instance, valeur secrète…), les icônes sont masquées : rien n'est deviné.
-- Les cadres sont réutilisés (réserve) et la mise à jour ne tourne que s'il existe des marqueurs ou des
-- emplacements connus.
--
-- Emplacements connus (Map/KnownSpots.lua) : marqueurs discrets de la carte courante (style « position
-- historique »), sauf près d'une détection du même type (moins de 20 m), pour un type que ce personnage piste
-- (ses points natifs suffisent, et l'icône gênerait leur survol) et, réception désactivée, pour les
-- emplacements seulement reçus du groupe.
--
-- Points d'apparition (Map/SpawnPoints.lua, données de QuestieDB) : marqueurs plus discrets encore, pour les mêmes
-- types que les emplacements connus, sauf près d'une détection ou d'un emplacement connu du même type (moins de
-- 20 m, emplacement tout juste récolté compris : la ressource vient de disparaître).

local addonName, ns = ...

local Overlay = ns.NewModule("MinimapOverlay")
ns.MinimapOverlay = Overlay

local pairs, next, sqrt, format, floor = pairs, next, math.sqrt, string.format, math.floor

local UPDATE_INTERVAL = 0.1  -- 10 rafraîchissements par seconde au plus
local FULL_REFRESH_INTERVAL = 1
local EXPIRE_INTERVAL = 1
local SPOT_HIDE_NEAR_LIVE_YARDS = 20 -- emplacement connu masqué près d'une détection du même type
local SPAWN_HIDE_NEAR_SPOT_YARDS = 20 -- point d'apparition masqué près d'un emplacement connu du même type
local MASK_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local ICONS = {
	HERB = "Interface\\Icons\\INV_Misc_Flower_02",
	ORE = "Interface\\Icons\\INV_Ore_Copper_01",
	TEST = "Interface\\Icons\\INV_Misc_QuestionMark",
	OTHER = "Interface\\Icons\\INV_Misc_QuestionMark",
}

local STATUS_COLOR_KEY = {
	ACTIVE = "live", UNCERTAIN = "uncertain", HISTORY = "history", MANUAL = "history", TEST = "test",
	SPAWN = "history",
}

local pool = {}         -- cadres libres
local activePins = {}   -- [clé du marqueur] = cadre
local usedThisPass = {} -- [clé] = true, réutilisée à chaque passage
local updateFrame = CreateFrame("Frame")
local sinceUpdate, sinceExpire, lastFullAt = 0, 0, -1
local dirty = true
local last = {}         -- dernier état de projection, pour éviter les recalculs inutiles

-- contexte du passage courant (évite de créer une fermeture à chaque rafraîchissement)
local ctx = { spotKinds = {}, spawnKinds = {} }
-- détections du passage courant, en mètres du joueur : { kind, east, north } (masquent les emplacements connus et
-- les points d'apparition)
local liveNear = {}
local liveCount = 0
-- emplacements connus voisins du passage courant, même forme (masquent les points d'apparition)
local spotsNear = {}
local spotsNearCount = 0

---------------------------------------------------------------------------
-- Infobulle
---------------------------------------------------------------------------

local function FormatAge(seconds)
	seconds = floor(seconds + 0.5)
	if seconds < 60 then
		return ns.T("AGE_SECONDS", seconds)
	end
	return ns.T("AGE_MINUTES", floor(seconds / 60), seconds % 60)
end

--- Âge d'un emplacement connu : secondes et minutes, puis heures, puis jours.
local function FormatLongAge(seconds)
	seconds = seconds > 0 and floor(seconds) or 0
	if seconds < 3600 then
		return FormatAge(seconds)
	elseif seconds < 86400 then
		return ns.T("AGE_HOURS", floor(seconds / 3600), floor(seconds % 3600 / 60))
	end
	return ns.T("AGE_DAYS", floor(seconds / 86400))
end

local function ReporterNames(marker)
	local names = {}
	for reporter in pairs(marker.reporters) do
		names[#names + 1] = ns.ShortName(reporter)
	end
	table.sort(names)
	return table.concat(names, ", ")
end

local function TooltipLine(label, value, r, g, b)
	GameTooltip:AddLine(ns.T("TOOLTIP_LINE", ns.T(label), value), r or 1, g or 1, b or 1)
end

local function ShowSpotTooltip(pin)
	local spot = pin.spot
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	if ns.Config.Get("showTooltipName") and spot.n then
		local color = ns.Config.Get("colors").history
		GameTooltip:AddLine(spot.n, color.r, color.g, color.b)
	else
		GameTooltip:AddLine(ns.T("TOOLTIP_TITLE"), 0.2, 1, 0.6)
	end
	TooltipLine("TT_KIND", ns.T("KIND_" .. spot.k))
	TooltipLine("TT_STATE", ns.T("STATUS_KNOWN_SPOT"))
	if ns.Config.Get("showTooltipAge") then
		TooltipLine("TT_LAST_SEEN", FormatLongAge(ns.Epoch() - spot.t))
	end
	TooltipLine("TT_SEEN_COUNT", ns.T("SEEN_TIMES_FMT", spot.c))
	TooltipLine("TT_ACCURACY", ns.T("ACCURACY_FMT", floor(spot.a + 0.5)))
	if pin.distance then
		TooltipLine("TT_DISTANCE", ns.T("DISTANCE_FMT", floor(pin.distance + 0.5)))
	end
	GameTooltip:AddLine(ns.T("TT_KNOWN_SPOT_WARNING"), 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

local function ShowSpawnTooltip(pin)
	local point = pin.spawn
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	local name = ns.Config.Get("showTooltipName") and ns.SpawnPoints.GetName(point)
	if name then
		local color = ns.Config.Get("colors").history
		GameTooltip:AddLine(name, color.r, color.g, color.b)
	else
		GameTooltip:AddLine(ns.T("TOOLTIP_TITLE"), 0.2, 1, 0.6)
	end
	TooltipLine("TT_KIND", ns.T("KIND_" .. point.k))
	TooltipLine("TT_STATE", ns.T("STATUS_SPAWN"))
	if pin.distance then
		TooltipLine("TT_DISTANCE", ns.T("DISTANCE_FMT", floor(pin.distance + 0.5)))
	end
	GameTooltip:AddLine(ns.T("TT_SPAWN_WARNING"), 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

local function ShowTooltip(pin)
	if pin.spot then
		return ShowSpotTooltip(pin)
	end
	if pin.spawn then
		return ShowSpawnTooltip(pin)
	end
	local marker, status = pin.marker, pin.status
	if not marker then
		return
	end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	-- titre : le nom de la ressource (« Pacifique »), dans la couleur de son statut ; nom absent ou masqué
	-- par le réglage showTooltipName : titre de l'addon et ligne « Nom » comme avant
	local hasName = type(marker.name) == "string" and marker.name ~= ""
	if ns.Config.Get("showTooltipName") and hasName then
		local color = ns.Config.Get("colors")[STATUS_COLOR_KEY[status]]
		GameTooltip:AddLine(marker.name, color.r, color.g, color.b)
	else
		GameTooltip:AddLine(status == "TEST" and ns.T("TOOLTIP_TITLE_TEST") or ns.T("TOOLTIP_TITLE"), 0.2, 1, 0.6)
		if ns.Config.Get("showTooltipName") then
			TooltipLine("TT_NAME", ns.T("UNKNOWN"))
		end
	end
	TooltipLine("TT_KIND", ns.T("KIND_" .. marker.kind))
	if ns.Config.Get("showTooltipReporter") then
		TooltipLine("TT_REPORTER", ReporterNames(marker))
	end
	TooltipLine("TT_STATE", ns.T("STATUS_" .. status))
	if ns.Config.Get("showTooltipAge") then
		TooltipLine("TT_LAST_SEEN", FormatAge(ns.Now() - marker.lastSeen))
	end
	if marker.accuracy and marker.accuracy > 0 then
		TooltipLine("TT_ACCURACY", ns.T("ACCURACY_FMT", floor(marker.accuracy + 0.5)))
	end
	if pin.distance then
		-- distance calculée par les conversions officielles carte/monde : affichée seulement dans ce cas
		TooltipLine("TT_DISTANCE", ns.T("DISTANCE_FMT", floor(pin.distance + 0.5)))
	end
	if status == "TEST" then
		GameTooltip:AddLine(ns.T("TT_TEST_WARNING"), 0.4, 0.7, 1, true)
	elseif status == "HISTORY" then
		GameTooltip:AddLine(ns.T("TT_HISTORY_WARNING"), 0.8, 0.8, 0.8, true)
	end
	GameTooltip:Show()
end

local function HideTooltip(pin)
	if GameTooltip:IsOwned(pin) then
		GameTooltip:Hide()
	end
end

---------------------------------------------------------------------------
-- Cadres
---------------------------------------------------------------------------

local function AddCircleMask(pin, texture)
	if not pin.CreateMaskTexture then
		return
	end
	local mask = pin:CreateMaskTexture()
	mask:SetTexture(MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
end

local function CreatePin()
	local pin = CreateFrame("Button", nil, Minimap)
	pin:SetFrameLevel(Minimap:GetFrameLevel() + 2)
	pin.ring = pin:CreateTexture(nil, "BACKGROUND")
	pin.ring:SetAllPoints()
	pin.ring:SetColorTexture(1, 1, 1, 1)
	AddCircleMask(pin, pin.ring)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetPoint("TOPLEFT", 2, -2)
	pin.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	AddCircleMask(pin, pin.icon)
	pin:SetScript("OnEnter", ShowTooltip)
	pin:SetScript("OnLeave", HideTooltip)
	return pin
end

local function AcquirePin(key)
	local pin = activePins[key]
	if pin then
		return pin
	end
	pin = next(pool)
	if pin then
		pool[pin] = nil
	else
		pin = CreatePin()
	end
	activePins[key] = pin
	return pin
end

local function ReleasePin(key)
	local pin = activePins[key]
	if not pin then
		return
	end
	activePins[key] = nil
	HideTooltip(pin)
	pin:Hide()
	pin:ClearAllPoints()
	pin.marker, pin.spot, pin.spawn, pin.status, pin.distance, pin.styleKey = nil, nil, nil, nil, nil, nil
	pool[pin] = true
end

local function HideAll()
	for key in pairs(activePins) do
		ReleasePin(key)
	end
end

local function ApplyStyle(pin, kind, status)
	local size = ns.Config.Get("iconSize")
	local alpha = ns.Config.Get("iconAlpha")
	local styleKey = format("%s|%s|%d|%.2f", kind, status, size, alpha)
	if pin.styleKey == styleKey then
		return
	end
	pin.styleKey = styleKey
	if status == "HISTORY" or status == "MANUAL" then
		size = floor(size * 0.75 + 0.5) -- marqueur discret
		alpha = alpha * 0.7
	elseif status == "SPAWN" then
		size = floor(size * 0.6 + 0.5) -- possible seulement : plus discret qu'un emplacement connu
		alpha = alpha * 0.5
	end
	pin:SetSize(size, size)
	pin:SetAlpha(alpha)
	local color = ns.Config.Get("colors")[STATUS_COLOR_KEY[status]]
	pin.ring:SetVertexColor(color.r, color.g, color.b, 1)
	pin.icon:SetTexture(ICONS[kind] or ICONS.OTHER)
	pin.icon:SetDesaturated(status == "UNCERTAIN" or status == "HISTORY" or status == "SPAWN")
end

---------------------------------------------------------------------------
-- Projection
---------------------------------------------------------------------------

local function PassesFilters(marker, status)
	-- réception désactivée : les marqueurs déjà reçus sont masqués aussi (seuls les locaux restent)
	if not marker.isLocal and not ns.Config.Get("receiveEnabled") then
		return false
	end
	-- nos propres détections recouvriraient les points natifs de notre minicarte : masquées par défaut
	if marker.isLocal and marker.source == "LIVE" and not ns.Config.Get("showOwnDetections") then
		return false
	end
	if marker.kind == "HERB" and not ns.Config.Get("showHerbs") then
		return false
	end
	if marker.kind == "ORE" and not ns.Config.Get("showOres") then
		return false
	end
	if (status == "ACTIVE" or status == "UNCERTAIN") and not ns.Config.Get("showLive") then
		return false
	end
	if status == "HISTORY" and not ns.Config.Get("showHistory") then
		return false
	end
	return true
end

--- Coordonnées du marqueur dans la carte courante (mises en cache par carte).
local function ViewCoords(marker, mapID)
	if marker.uiMapID == mapID then
		return marker.x, marker.y
	end
	if marker.viewMapID ~= mapID then
		local x, y = ns.Coordinates.TranslateToMap(marker.uiMapID, marker.x, marker.y, mapID)
		marker.viewMapID, marker.viewX, marker.viewY = mapID, x or false, y or false
	end
	if marker.viewX then
		return marker.viewX, marker.viewY
	end
	return nil
end

--- Affiche un cadre à (east, north) mètres du joueur s'il tombe dans la minicarte. Renvoie true si affiché.
local function ShowPinAt(key, east, north, distance, kind, status)
	local ox, oy = ns.Coordinates.ProjectToMinimap(east, north, ctx.radius, ctx.halfWidth, ctx.halfHeight,
		ctx.facing)
	if not ns.Coordinates.IsInsideMinimap(ox, oy, ctx.halfWidth, ctx.halfHeight, ctx.round, ctx.margin) then
		return nil
	end
	local pin = AcquirePin(key)
	pin.status, pin.distance = status, distance
	ApplyStyle(pin, kind, status)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
	pin:Show()
	usedThisPass[key] = true
	return pin
end

--- Détection du passage courant, affichée ou propre au joueur (il était sur place) : masque les emplacements
--- connus voisins du même type. Une détection reçue mais masquée par un réglage ne masque rien.
local function NoteLive(kind, east, north)
	liveCount = liveCount + 1
	local entry = liveNear[liveCount]
	if not entry then
		entry = {}
		liveNear[liveCount] = entry
	end
	entry.kind, entry.east, entry.north = kind, east, north
end

local function PlaceMarker(marker, status)
	local vx, vy = ViewCoords(marker, ctx.mapID)
	if not vx then
		return -- autre continent ou conversion impossible : jamais affiché sur une mauvaise carte
	end
	local east, north = ns.Coordinates.OffsetYards(ctx.width, ctx.height, ctx.px, ctx.py, vx, vy)
	local visible = PassesFilters(marker, status)
	if marker.source == "LIVE" and (visible or marker.isLocal) then
		NoteLive(marker.kind, east, north)
	end
	if not visible then
		return
	end
	local distance = sqrt(east * east + north * north)
	if distance > ctx.radius * 1.5 then
		return
	end
	local pin = ShowPinAt(marker.key, east, north, distance, marker.kind, status)
	if pin then
		pin.marker = marker
	end
end

local function IsNear(list, count, limitYards, kind, east, north)
	local limit = limitYards * limitYards
	for i = 1, count do
		local entry = list[i]
		local dx, dy = entry.east - east, entry.north - north
		if entry.kind == kind and dx * dx + dy * dy <= limit then
			return true
		end
	end
	return false
end

local function NearLive(kind, east, north)
	return IsNear(liveNear, liveCount, SPOT_HIDE_NEAR_LIVE_YARDS, kind, east, north)
end

--- Emplacement connu voisin du joueur : masque les points d'apparition proches du même type.
local function NoteSpot(kind, east, north)
	spotsNearCount = spotsNearCount + 1
	local entry = spotsNear[spotsNearCount]
	if not entry then
		entry = {}
		spotsNear[spotsNearCount] = entry
	end
	entry.kind, entry.east, entry.north = kind, east, north
end

--- Emplacement connu de la carte courante (la table de l'emplacement sert de clé de cadre). Pas affiché juste
--- après une récolte : la ressource vient de disparaître. Retenu aussi, affiché ou non (réglage, récolte), pour
--- masquer les points d'apparition voisins.
local function PlaceSpot(spot)
	local kind = spot.k
	local shown, masksSpawns = ctx.spotKinds[kind], ctx.spawnKinds[kind]
	if not (shown or masksSpawns) or (not spot.m and not ctx.receiveEnabled) then
		return
	end
	local east, north = ns.Coordinates.OffsetYards(ctx.width, ctx.height, ctx.px, ctx.py, spot.x, spot.y)
	local distance = sqrt(east * east + north * north)
	if masksSpawns and distance <= ctx.radius * 1.5 + SPAWN_HIDE_NEAR_SPOT_YARDS then
		NoteSpot(kind, east, north)
	end
	if not shown then
		return
	end
	ctx.spotsFollowed = true -- affichable ici : suivi pendant les déplacements, même hors de vue ou récolté
	if ns.KnownSpots.IsRecentlyGathered(spot, ctx.epoch) then
		return
	end
	if distance > ctx.radius * 1.5 or NearLive(kind, east, north) then
		return
	end
	local pin = ShowPinAt(spot, east, north, distance, kind, "HISTORY")
	if pin then
		pin.spot = spot
	end
end

--- Point d'apparition de la carte courante (sa clé numérique sert de clé de cadre).
local function PlaceSpawn(point)
	local kind = point.k
	if not ctx.spawnKinds[kind] then
		return
	end
	ctx.spotsFollowed = true
	local east, north = ns.Coordinates.OffsetYards(ctx.width, ctx.height, ctx.px, ctx.py, point.x, point.y)
	local distance = sqrt(east * east + north * north)
	if distance > ctx.radius * 1.5 or NearLive(kind, east, north)
		or IsNear(spotsNear, spotsNearCount, SPAWN_HIDE_NEAR_SPOT_YARDS, kind, east, north) then
		return
	end
	local pin = ShowPinAt(point.key, east, north, distance, kind, "SPAWN")
	if pin then
		pin.spawn = point
	end
end

local herbsTracked, oresTracked, trackingReadAt = false, false, nil

--- Types dont les emplacements connus et les points d'apparition s'affichent : filtre d'affichage, et pas de
--- pistage actif de ce type (pistage relu au plus une fois par seconde).
local function UpdateSpotKinds(now)
	local spotKinds, spawnKinds = ctx.spotKinds, ctx.spawnKinds
	spotKinds.HERB, spotKinds.ORE, spawnKinds.HERB, spawnKinds.ORE = false, false, false, false
	local wantSpots = ns.Config.Get("showHistory") and ns.KnownSpots.Count(ctx.mapID) > 0
	local wantSpawns = ns.Config.Get("showSpawns") and ns.SpawnPoints.IsAvailable()
	if not (wantSpots or wantSpawns) then
		return
	end
	if not trackingReadAt or now - trackingReadAt >= FULL_REFRESH_INTERVAL or now < trackingReadAt then
		trackingReadAt = now
		local tracking = ns.Tracking.GetTrackingState()
		herbsTracked = tracking.available and tracking.herbs ~= nil and tracking.herbs.active or false
		oresTracked = tracking.available and tracking.ores ~= nil and tracking.ores.active or false
	end
	local herbs = ns.Config.Get("showHerbs") and not herbsTracked
	local ores = ns.Config.Get("showOres") and not oresTracked
	if wantSpots then
		spotKinds.HERB, spotKinds.ORE = herbs, ores
	end
	if wantSpawns then
		spawnKinds.HERB, spawnKinds.ORE = herbs, ores
	end
end

--- Rien n'est affiché (minicarte masquée, position inconnue) : aucun emplacement connu ni point d'apparition à
--- suivre non plus. ctx.spotsFollowed : un emplacement connu ou un point d'apparition de la carte courante est
--- affichable (la boucle continue).
local function HideEverything()
	HideAll()
	ctx.spotsFollowed = false
end

local function Refresh(now)
	if not (ns.Config.Get("enabled") and ns.Config.Get("showMinimap")) or not Minimap:IsVisible() then
		HideEverything()
		return
	end
	local mapID, px, py = ns.Coordinates.GetPlayerMapPosition()
	if not mapID then
		HideEverything()
		return
	end
	local width, height = ns.Coordinates.GetMapSizeYards(mapID)
	local radius = ns.Coordinates.GetMinimapRadiusYards()
	if not width or not radius then
		HideEverything()
		return
	end
	local facing
	if ns.GetCVar("rotateMinimap") == "1" then
		facing = GetPlayerFacing and GetPlayerFacing()
		if ns.IsSecret(facing) or facing == nil then
			HideEverything() -- rotation active mais orientation inaccessible : placement impossible
			return
		end
	end
	local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	local version, spotsVersion = ns.MarkerManager.version, ns.KnownSpots.version
	local spawnsVersion = ns.SpawnPoints.version

	if not dirty and now - lastFullAt < FULL_REFRESH_INTERVAL and last.mapID == mapID and last.px == px
		and last.py == py and last.radius == radius and last.facing == facing and last.halfWidth == halfWidth
		and last.version == version and last.spotsVersion == spotsVersion and last.spawnsVersion == spawnsVersion then
		return
	end
	dirty = false
	lastFullAt = now
	last.mapID, last.px, last.py, last.radius, last.facing = mapID, px, py, radius, facing
	last.halfWidth, last.version, last.spotsVersion, last.spawnsVersion = halfWidth, version, spotsVersion,
		spawnsVersion

	ctx.mapID, ctx.px, ctx.py, ctx.width, ctx.height = mapID, px, py, width, height
	ctx.radius, ctx.facing, ctx.halfWidth, ctx.halfHeight = radius, facing, halfWidth, halfHeight
	ctx.round = (GetMinimapShape and GetMinimapShape() or "ROUND") == "ROUND"
	ctx.margin = ns.Config.Get("iconSize") / 2
	ctx.receiveEnabled = ns.Config.Get("receiveEnabled")
	ctx.epoch = ns.Epoch()

	ns.Wipe(usedThisPass)
	liveCount, spotsNearCount = 0, 0
	ns.MarkerManager.ForEach(PlaceMarker, now)
	UpdateSpotKinds(now)
	ctx.spotsFollowed = false
	local spawnsWanted = ctx.spawnKinds.HERB or ctx.spawnKinds.ORE
	if ctx.spotKinds.HERB or ctx.spotKinds.ORE or spawnsWanted then
		ns.KnownSpots.ForEachOnMap(mapID, PlaceSpot)
	end
	if spawnsWanted then
		-- carte pas encore lue : sa construction démarre, PGR_SPAWNS_CHANGED relance l'affichage à la fin
		ns.SpawnPoints.ForEachOnMap(mapID, PlaceSpawn)
	end
	for key in pairs(activePins) do
		if not usedThisPass[key] then
			ReleasePin(key)
		end
	end
end

---------------------------------------------------------------------------
-- Boucle de mise à jour (active seulement s'il existe des marqueurs, ou des emplacements connus affichables sur
-- la carte courante ; relancée par un changement de zone, de pistage ou de réglage)
---------------------------------------------------------------------------

local function OnUpdate(_, elapsed)
	sinceUpdate = sinceUpdate + elapsed
	sinceExpire = sinceExpire + elapsed
	if sinceUpdate < UPDATE_INTERVAL then
		return
	end
	sinceUpdate = 0
	local now = ns.Now()
	if sinceExpire >= EXPIRE_INTERVAL then
		sinceExpire = 0
		if ns.MarkerManager.Expire(now) > 0 then
			dirty = true
			ns.Fire("PGR_MARKERS_EXPIRED")
		end
	end
	Refresh(now)
	local real, test = ns.MarkerManager.Count()
	if real + test == 0 and not ctx.spotsFollowed then
		HideAll()
		updateFrame:SetScript("OnUpdate", nil)
	end
end

local function SafeOnUpdate(frame, elapsed)
	ns.SafeCall("MinimapOverlay", OnUpdate, frame, elapsed)
end

--- Demande un rafraîchissement complet et démarre la boucle si nécessaire.
function Overlay.Invalidate()
	dirty = true
	if not updateFrame:GetScript("OnUpdate") then
		sinceUpdate, sinceExpire = UPDATE_INTERVAL, 0
		updateFrame:SetScript("OnUpdate", SafeOnUpdate)
	end
end

--- Vrai si la boucle de mise à jour tourne.
function Overlay.IsUpdating()
	return updateFrame:GetScript("OnUpdate") ~= nil
end

function Overlay.GetVisibleCount()
	local count = 0
	for _ in pairs(activePins) do
		count = count + 1
	end
	return count
end

function Overlay.OnDisabled()
	updateFrame:SetScript("OnUpdate", nil)
	HideAll()
end

local function OnChange()
	Overlay.Invalidate()
end

ns.On("PGR_MARKERS_CHANGED", "MinimapOverlay", OnChange)
ns.On("PGR_SPOTS_CHANGED", "MinimapOverlay", OnChange)
ns.On("PGR_SPAWNS_CHANGED", "MinimapOverlay", OnChange)
ns.On("PGR_SETTING_CHANGED", "MinimapOverlay", OnChange)
ns.On("PGR_CONFIG_LOADED", "MinimapOverlay", OnChange)
ns.RegisterEvent("MINIMAP_UPDATE_ZOOM", "MinimapOverlay", OnChange)
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", "MinimapOverlay", OnChange)
-- sous-zones, villes et intérieurs : la carte du joueur peut changer, avec d'autres emplacements connus
ns.RegisterEvent("ZONE_CHANGED", "MinimapOverlay", OnChange)
ns.RegisterEvent("ZONE_CHANGED_INDOORS", "MinimapOverlay", OnChange)
-- pistage activé ou coupé : les emplacements connus de ce type sont masqués ou de nouveau affichables
ns.RegisterEvent("MINIMAP_UPDATE_TRACKING", "MinimapOverlay", function()
	trackingReadAt = nil
	Overlay.Invalidate()
end)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", "MinimapOverlay", OnChange)
ns.RegisterEvent("CVAR_UPDATE", "MinimapOverlay", OnChange)
