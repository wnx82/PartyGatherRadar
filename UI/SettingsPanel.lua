-- PartyGatherRadar - UI/SettingsPanel.lua
-- Fenêtre de réglages (bouton de minicarte ou /pgr) : version, membres du groupe qui utilisent l'addon,
-- réglages d'affichage et de partage. Créée au premier affichage seulement.
-- Cadre nommé (PartyGatherRadarSettingsFrame) pour que la touche Échap la ferme (UISpecialFrames).

local addonName, ns = ...

local SettingsPanel = ns.NewModule("SettingsPanel")
ns.SettingsPanel = SettingsPanel

local ipairs, format, max = ipairs, string.format, math.max

local FRAME_NAME = "PartyGatherRadarSettingsFrame"
local WIDTH = 420
local PADDING = 16
local LINE_HEIGHT = 16
local CHECK_HEIGHT = 26
local MAX_MEMBER_LINES = 5 -- un groupe : 4 autres membres ; en raid, « … et N autres »
local ROSTER_REFRESH_DELAY = 0.5 -- laisse GroupSync relire la composition avant l'affichage

local COLOR_OK = "ff40ff40"
local COLOR_BAD = "ffff4040"
local COLOR_WARN = "ffffd040"
local COLOR_MUTED = "ff9d9d9d"

local frame
local versionText
local summaryText
local memberLines = {}
local checkboxes = {}

local function Colored(color, text)
	return "|c" .. color .. text .. "|r"
end

--- Lignes de la liste des membres : { text } ; membres avec l'addon d'abord, puis les autres.
function SettingsPanel.BuildMemberLines()
	local lines = {}
	if not ns.GroupSync.IsInGroup() then
		lines[1] = Colored(COLOR_MUTED, ns.T("PANEL_NO_GROUP"))
		return lines, 0, 0
	end
	local known = {}
	local peers = ns.GroupSync.GetPeers()
	for _, entry in ipairs(peers) do
		local peer = entry.peer
		known[entry.name] = true
		local status
		if peer.compatible == false then
			status = Colored(COLOR_BAD, ns.T("PANEL_MEMBER_INCOMPATIBLE", tostring(peer.addonVersion or "?")))
		elseif peer.compatible then
			status = Colored(COLOR_OK, ns.T("PANEL_MEMBER_ADDON", tostring(peer.addonVersion or "?")))
		else
			status = Colored(COLOR_WARN, ns.T("PANEL_MEMBER_ADDON", tostring(peer.addonVersion or "?")))
		end
		lines[#lines + 1] = ns.ShortName(entry.name) .. " — " .. status
	end
	local members = ns.GroupSync.GetRosterNames()
	for _, name in ipairs(members) do
		if not known[name] then
			lines[#lines + 1] = ns.ShortName(name) .. " — " .. Colored(COLOR_MUTED, ns.T("PANEL_MEMBER_NO_ADDON"))
		end
	end
	if #lines == 0 then
		lines[1] = Colored(COLOR_MUTED, ns.T("PANEL_GROUP_EMPTY"))
	end
	return lines, #members, #peers
end

local function BuildOptions()
	return {
		{ key = "enabled", label = ns.T("OPT_ENABLED") },
		{ key = "receiveEnabled", label = ns.T("OPT_RECEIVE") },
		{ key = "shareEnabled", label = ns.T("OPT_SHARE") },
		{ key = "showMinimap", label = ns.T("OPT_SHOW_MINIMAP") },
		{ key = "showHerbs", label = ns.T("OPT_HERBS") },
		{ key = "showOres", label = ns.T("OPT_ORES") },
		{ key = "showMinimapButton", label = ns.T("OPT_BUTTON") },
		{ key = "debug", label = ns.T("OPT_DEBUG") },
	}
end

local function Protected(fn)
	return function(...)
		ns.SafeCall("SettingsPanel", fn, ...)
	end
end

local function AddText(parent, template, y, text)
	local fontString = parent:CreateFontString(nil, "OVERLAY", template)
	fontString:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, y)
	fontString:SetWidth(WIDTH - 2 * PADDING)
	fontString:SetJustifyH("LEFT")
	fontString:SetWordWrap(false) -- une ligne par texte : un nom très long est tronqué, jamais superposé
	if text then
		fontString:SetText(text)
	end
	return fontString
end

local function AddButton(parent, text, x, onClick)
	local actionButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	actionButton:SetSize(170, 22)
	actionButton:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, PADDING)
	actionButton:SetText(text)
	actionButton:SetScript("OnClick", Protected(onClick))
	return actionButton
end

local function Create()
	frame = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	frame:SetBackdropColor(0.06, 0.06, 0.08, 0.94)
	frame:SetBackdropBorderColor(0.83, 0.69, 0.22, 0.6)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	frame:SetScript("OnShow", Protected(function() SettingsPanel.Refresh() end))
	if UISpecialFrames then
		table.insert(UISpecialFrames, FRAME_NAME)
	end

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

	local y = -PADDING
	AddText(frame, "GameFontNormalLarge", y, "PartyGatherRadar")
	y = y - 22
	versionText = AddText(frame, "GameFontHighlightSmall", y)
	y = y - LINE_HEIGHT - 10

	AddText(frame, "GameFontNormal", y, ns.T("PANEL_GROUP_HEADER"))
	y = y - LINE_HEIGHT - 2
	summaryText = AddText(frame, "GameFontHighlightSmall", y)
	y = y - LINE_HEIGHT
	for i = 1, MAX_MEMBER_LINES + 1 do -- une ligne de plus pour « … et N autres »
		memberLines[i] = AddText(frame, "GameFontHighlightSmall", y)
		y = y - LINE_HEIGHT
	end
	y = y - 8

	AddText(frame, "GameFontNormal", y, ns.T("PANEL_OPTIONS_HEADER"))
	y = y - LINE_HEIGHT - 2
	for _, option in ipairs(BuildOptions()) do
		local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
		check:SetSize(24, 24)
		check:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING - 4, y)
		local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("LEFT", check, "RIGHT", 2, 0)
		label:SetWidth(WIDTH - 2 * PADDING - 30)
		label:SetJustifyH("LEFT")
		label:SetWordWrap(false)
		label:SetText(option.label)
		check.settingKey = option.key
		check:SetScript("OnClick", Protected(function(self)
			ns.Config.Set(self.settingKey, self:GetChecked() and true or false)
		end))
		checkboxes[#checkboxes + 1] = check
		y = y - CHECK_HEIGHT
	end

	y = y - 8
	AddButton(frame, ns.T("PANEL_BUTTON_TEST"), PADDING, function() ns.Commands.Handle("test") end)
	AddButton(frame, ns.T("PANEL_BUTTON_DIAG"), WIDTH - PADDING - 170, function() ns.Commands.Handle("diag") end)
	frame:SetSize(WIDTH, -y + 22 + PADDING)
	frame:Hide()
end

--- Met à jour la version, la liste des membres et l'état des cases. Sans effet si la fenêtre est fermée.
function SettingsPanel.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local build = ns.Diagnostics.GetBuild()
	versionText:SetText(ns.T("PANEL_VERSION", ns.VERSION, ns.Protocol.VERSION, tostring(build.version),
		tostring(build.build)))

	local lines, members, peers = SettingsPanel.BuildMemberLines()
	if ns.GroupSync.IsInGroup() then
		summaryText:SetText(ns.T("PANEL_GROUP_SUMMARY", members, peers))
	else
		summaryText:SetText("")
	end
	for i, fontString in ipairs(memberLines) do
		if i <= MAX_MEMBER_LINES then
			fontString:SetText(lines[i] or "")
		else
			local hidden = max(#lines - MAX_MEMBER_LINES, 0)
			fontString:SetText(hidden > 0 and Colored(COLOR_MUTED, ns.T("PANEL_MEMBERS_MORE", hidden)) or "")
		end
	end

	for _, check in ipairs(checkboxes) do
		check:SetChecked(ns.Config.Get(check.settingKey) and true or false)
	end
end

function SettingsPanel.Open()
	if not frame then
		Create()
	end
	frame:Show()
	SettingsPanel.Refresh()
end

function SettingsPanel.Close()
	if frame then
		frame:Hide()
	end
end

function SettingsPanel.Toggle()
	if frame and frame:IsShown() then
		SettingsPanel.Close()
	else
		SettingsPanel.Open()
	end
end

function SettingsPanel.IsOpen()
	return frame ~= nil and frame:IsShown()
end

--- Case à cocher d'un réglage (tests hors jeu).
function SettingsPanel.GetCheckbox(key)
	for _, check in ipairs(checkboxes) do
		if check.settingKey == key then
			return check
		end
	end
	return nil
end

--- Textes de version et de résumé du groupe (tests hors jeu).
function SettingsPanel.GetHeaderTexts()
	return versionText and versionText:GetText(), summaryText and summaryText:GetText()
end

function SettingsPanel.GetMemberTexts()
	local texts = {}
	for _, fontString in ipairs(memberLines) do
		texts[#texts + 1] = fontString:GetText()
	end
	return texts
end

local function RefreshSoon()
	if SettingsPanel.IsOpen() then
		ns.After(ROSTER_REFRESH_DELAY, "SettingsPanel", SettingsPanel.Refresh)
	end
end

ns.On("PGR_PEERS_CHANGED", "SettingsPanel", function() SettingsPanel.Refresh() end)
ns.On("PGR_SETTING_CHANGED", "SettingsPanel", function() SettingsPanel.Refresh() end)
ns.RegisterEvent("GROUP_ROSTER_UPDATE", "SettingsPanel", RefreshSoon)
