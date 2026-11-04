-- PartyGatherRadar - UI/MinimapButton.lua
-- Bouton autour de la minicarte : clic pour ouvrir la fenêtre de réglages, glisser pour le déplacer sur le bord.
-- Textures standard du client, celles des boutons de minicarte des addons Forever installés.
-- Cadre nommé (PartyGatherRadarMinimapButton) : les addons qui regroupent les boutons de minicarte le retrouvent.

local addonName, ns = ...

local MinimapButton = ns.NewModule("MinimapButton")
ns.MinimapButton = MinimapButton

local cos, sin, rad, deg, atan2 = math.cos, math.sin, math.rad, math.deg, math.atan2
local abs, max = math.abs, math.max

local BUTTON_NAME = "PartyGatherRadarMinimapButton"
local ICON = "Interface\\Icons\\INV_Misc_Flower_02" -- même icône que le TOC
local EDGE_GAP = 5         -- écart entre le bord de la minicarte et le centre du bouton
local CLICK_AFTER_DRAG = 0.2 -- secondes pendant lesquelles un clic qui termine un déplacement est ignoré

local button
local dragAngle
local lastDragStop = -CLICK_AFTER_DRAG

--- Décalage du bouton depuis le centre de la minicarte pour un angle en degrés (0 = est, sens trigonométrique).
--- Minicarte non ronde (GetMinimapShape fourni par un addon de minicarte) : le bouton suit le bord du carré.
function MinimapButton.OffsetForAngle(angle, width, shape)
	local radius = width / 2 + EDGE_GAP
	local x, y = cos(rad(angle)), sin(rad(angle))
	if shape and shape ~= "ROUND" then
		local scale = 1 / max(abs(x), abs(y))
		x, y = x * scale, y * scale
	end
	return x * radius, y * radius
end

local function MinimapShape()
	return GetMinimapShape and GetMinimapShape() or "ROUND"
end

local function PlaceAt(angle)
	local x, y = MinimapButton.OffsetForAngle(angle, Minimap:GetWidth(), MinimapShape())
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

--- Angle (degrés, 0 à 360) du curseur autour du centre de la minicarte.
local function CursorAngle()
	local centerX, centerY = Minimap:GetCenter()
	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	return deg(atan2(cursorY / scale - centerY, cursorX / scale - centerX)) % 360
end

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("PartyGatherRadar " .. ns.VERSION)
	if ns.GroupSync.IsInGroup() then
		GameTooltip:AddLine(ns.T("BUTTON_TIP_GROUP", ns.GroupSync.GetRosterSize(), #ns.GroupSync.GetPeers()), 1, 1, 1)
	else
		GameTooltip:AddLine(ns.T("BUTTON_TIP_NO_GROUP"), 1, 1, 1)
	end
	if not ns.Config.Get("enabled") then
		GameTooltip:AddLine(ns.T("BUTTON_TIP_DISABLED"), 1, 0.4, 0.4)
	end
	GameTooltip:AddLine(ns.T("BUTTON_TIP_CLICK"), 0.6, 0.6, 0.6)
	GameTooltip:AddLine(ns.T("BUTTON_TIP_DRAG"), 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

--- Script de cadre protégé : une erreur désactive ce module seul (voir ns.SafeCall).
local function Protected(fn)
	return function(...)
		ns.SafeCall("MinimapButton", fn, ...)
	end
end

local function Create()
	button = CreateFrame("Button", BUTTON_NAME, Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(24, 24)
	background:SetPoint("CENTER", button, "CENTER", 0, 0)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER", button, "CENTER", 0, 0)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnClick", Protected(function()
		-- le relâchement qui termine un déplacement ne doit pas ouvrir la fenêtre
		if ns.Now() - lastDragStop >= CLICK_AFTER_DRAG then
			ns.SettingsPanel.Toggle()
		end
	end))
	button:SetScript("OnEnter", Protected(ShowTooltip))
	button:SetScript("OnLeave", Protected(function() GameTooltip:Hide() end))
	button:SetScript("OnDragStart", Protected(function(self)
		self:LockHighlight()
		GameTooltip:Hide()
		self:SetScript("OnUpdate", Protected(function()
			dragAngle = CursorAngle()
			PlaceAt(dragAngle)
		end))
	end))
	button:SetScript("OnDragStop", Protected(function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
		lastDragStop = ns.Now()
		if dragAngle then
			ns.Config.Set("minimapButtonAngle", dragAngle)
			dragAngle = nil
		end
	end))
end

--- Applique les réglages : visibilité et position.
function MinimapButton.Refresh()
	if not button then
		return
	end
	if ns.Config.Get("showMinimapButton") then
		button:Show()
	else
		button:Hide()
	end
	PlaceAt(ns.Config.Get("minimapButtonAngle"))
end

function MinimapButton.GetFrame()
	return button
end

ns.On("PGR_CONFIG_LOADED", "MinimapButton", function()
	if not button then
		Create()
	end
	MinimapButton.Refresh()
end)

ns.On("PGR_SETTING_CHANGED", "MinimapButton", function(_, key)
	if key == "showMinimapButton" or key == "minimapButtonAngle" then
		MinimapButton.Refresh()
	end
end)

-- taille et forme de la minicarte connues après le chargement des addons de minicarte
ns.RegisterEvent("PLAYER_ENTERING_WORLD", "MinimapButton", function()
	MinimapButton.Refresh()
end)
