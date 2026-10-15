-- PartyGatherRadar - Map/MinimapOverlay.lua
-- Couche d'icônes personnalisées posée sur la minicarte, indépendante du pistage natif.
--
-- Placement : position du joueur (C_Map) + position du marqueur convertie dans la carte courante,
-- décalage en mètres, mis à l'échelle par le rayon de vue (C_Minimap.GetViewRadius), rotation de
-- la minicarte prise en compte seulement si l'orientation du joueur est accessible.
-- Si une donnée manque (instance, valeur secrète…), les icônes sont masquées : rien n'est deviné.
-- Les cadres sont réutilisés (réserve) et la mise à jour ne tourne que s'il existe des marqueurs.

local addonName, ns = ...

local Overlay = ns.NewModule("MinimapOverlay")
ns.MinimapOverlay = Overlay

local pairs, next, sqrt, format, floor = pairs, next, math.sqrt, string.format, math.floor

local UPDATE_INTERVAL = 0.1  -- 10 rafraîchissements par seconde au plus
local FULL_REFRESH_INTERVAL = 1
local EXPIRE_INTERVAL = 1
local MASK_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local ICONS = {
	HERB = "Interface\\Icons\\INV_Misc_Flower_02",
	ORE = "Interface\\Icons\\INV_Ore_Copper_01",
	TEST = "Interface\\Icons\\INV_Misc_QuestionMark",
	OTHER = "Interface\\Icons\\INV_Misc_QuestionMark",
}

local STATUS_COLOR_KEY = {
	ACTIVE = "live", UNCERTAIN = "uncertain", HISTORY = "history", MANUAL = "history", TEST = "test",
}

local pool = {}         -- cadres libres
local activePins = {}   -- [clé du marqueur] = cadre
local usedThisPass = {} -- [clé] = true, réutilisée à chaque passage
local updateFrame = CreateFrame("Frame")
local sinceUpdate, sinceExpire, lastFullAt = 0, 0, -1
local dirty = true
local last = {}         -- dernier état de projection, pour éviter les recalculs inutiles

-- contexte du passage courant (évite de créer une fermeture à chaque rafraîchissement)
local ctx = {}

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

local function ShowTooltip(pin)
	local marker, status = pin.marker, pin.status
	if not marker then
		return
	end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:AddLine(status == "TEST" and ns.T("TOOLTIP_TITLE_TEST") or ns.T("TOOLTIP_TITLE"), 0.2, 1, 0.6)
	if ns.Config.Get("showTooltipName") then
		TooltipLine("TT_NAME", (marker.name and marker.name ~= "") and marker.name or ns.T("UNKNOWN"))
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
	pin.marker, pin.status, pin.distance, pin.styleKey = nil, nil, nil, nil
	pool[pin] = true
end

local function HideAll()
	for key in pairs(activePins) do
		ReleasePin(key)
	end
end

local function ApplyStyle(pin, marker, status)
	local size = ns.Config.Get("iconSize")
	local alpha = ns.Config.Get("iconAlpha")
	local styleKey = format("%s|%s|%d|%.2f", marker.kind, status, size, alpha)
	if pin.styleKey == styleKey then
		return
	end
	pin.styleKey = styleKey
	if status == "HISTORY" or status == "MANUAL" then
		size = floor(size * 0.75 + 0.5) -- marqueur discret
		alpha = alpha * 0.7
	end
	pin:SetSize(size, size)
	pin:SetAlpha(alpha)
	local color = ns.Config.Get("colors")[STATUS_COLOR_KEY[status]]
	pin.ring:SetVertexColor(color.r, color.g, color.b, 1)
	pin.icon:SetTexture(ICONS[marker.kind] or ICONS.OTHER)
	pin.icon:SetDesaturated(status == "UNCERTAIN" or status == "HISTORY")
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

local function PlaceMarker(marker, status)
	if not PassesFilters(marker, status) then
		return
	end
	local vx, vy = ViewCoords(marker, ctx.mapID)
	if not vx then
		return -- autre continent ou conversion impossible : jamais affiché sur une mauvaise carte
	end
	local east, north = ns.Coordinates.OffsetYards(ctx.width, ctx.height, ctx.px, ctx.py, vx, vy)
	local distance = sqrt(east * east + north * north)
	if distance > ctx.radius * 1.5 then
		return
	end
	local ox, oy = ns.Coordinates.ProjectToMinimap(east, north, ctx.radius, ctx.halfWidth, ctx.halfHeight,
		ctx.facing)
	if not ns.Coordinates.IsInsideMinimap(ox, oy, ctx.halfWidth, ctx.halfHeight, ctx.round, ctx.margin) then
		return
	end
	local pin = AcquirePin(marker.key)
	pin.marker, pin.status, pin.distance = marker, status, distance
	ApplyStyle(pin, marker, status)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
	pin:Show()
	usedThisPass[marker.key] = true
end

local function Refresh(now)
	if not (ns.Config.Get("enabled") and ns.Config.Get("showMinimap")) or not Minimap:IsVisible() then
		HideAll()
		return
	end
	local mapID, px, py = ns.Coordinates.GetPlayerMapPosition()
	if not mapID then
		HideAll()
		return
	end
	local width, height = ns.Coordinates.GetMapSizeYards(mapID)
	local radius = ns.Coordinates.GetMinimapRadiusYards()
	if not width or not radius then
		HideAll()
		return
	end
	local facing
	if ns.GetCVar("rotateMinimap") == "1" then
		facing = GetPlayerFacing and GetPlayerFacing()
		if ns.IsSecret(facing) or facing == nil then
			HideAll() -- rotation active mais orientation inaccessible : placement impossible
			return
		end
	end
	local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	local version = ns.MarkerManager.version

	if not dirty and now - lastFullAt < FULL_REFRESH_INTERVAL and last.mapID == mapID and last.px == px
		and last.py == py and last.radius == radius and last.facing == facing and last.halfWidth == halfWidth
		and last.version == version then
		return
	end
	dirty = false
	lastFullAt = now
	last.mapID, last.px, last.py, last.radius, last.facing = mapID, px, py, radius, facing
	last.halfWidth, last.version = halfWidth, version

	ctx.mapID, ctx.px, ctx.py, ctx.width, ctx.height = mapID, px, py, width, height
	ctx.radius, ctx.facing, ctx.halfWidth, ctx.halfHeight = radius, facing, halfWidth, halfHeight
	ctx.round = (GetMinimapShape and GetMinimapShape() or "ROUND") == "ROUND"
	ctx.margin = ns.Config.Get("iconSize") / 2

	ns.Wipe(usedThisPass)
	ns.MarkerManager.ForEach(PlaceMarker, now)
	for key in pairs(activePins) do
		if not usedThisPass[key] then
			ReleasePin(key)
		end
	end
end

---------------------------------------------------------------------------
-- Boucle de mise à jour (active seulement s'il existe des marqueurs)
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
	if real + test == 0 then
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
ns.On("PGR_SETTING_CHANGED", "MinimapOverlay", OnChange)
ns.On("PGR_CONFIG_LOADED", "MinimapOverlay", OnChange)
ns.RegisterEvent("MINIMAP_UPDATE_ZOOM", "MinimapOverlay", OnChange)
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", "MinimapOverlay", OnChange)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", "MinimapOverlay", OnChange)
ns.RegisterEvent("CVAR_UPDATE", "MinimapOverlay", OnChange)
