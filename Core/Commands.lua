-- PartyGatherRadar - Core/Commands.lua
-- Commandes /pgr. Dernier fichier chargé : tous les modules sont disponibles.

local addonName, ns = ...

local Commands = ns.NewModule("Commands")
ns.Commands = Commands

local pairs, ipairs, tostring, tonumber, format, floor = pairs, ipairs, tostring, tonumber, string.format, math.floor

local TEST_OFFSET_YARDS = 15 -- marqueur TEST posé à environ 21 m au nord-est du joueur
local testCounter = 0

local function YesNo(value)
	return value and ns.T("YES") or ns.T("NO")
end

---------------------------------------------------------------------------
-- Rapports
---------------------------------------------------------------------------

local function PrintVersion()
	local build = ns.Diagnostics.GetBuild()
	ns.Print(ns.T("VERSION_LINE", ns.VERSION, ns.Protocol.VERSION, tostring(build.version), tostring(build.build),
		tostring(build.toc), ns.TARGET_INTERFACE, YesNo(build.isForever)))
end

local function PrintStatus()
	local Config = ns.Config
	ns.Print(ns.T("STATUS_ADDON", ns.VERSION, YesNo(Config.Get("enabled")), YesNo(Config.Get("shareEnabled")),
		YesNo(Config.Get("receiveEnabled")), YesNo(Config.Get("showMinimap"))))
	local channel = ns.Sender.GetChannel()
	local peers = ns.GroupSync.GetPeers()
	local compatible = 0
	for _, entry in ipairs(peers) do
		if entry.peer.compatible then
			compatible = compatible + 1
		end
	end
	ns.Print(ns.T("STATUS_GROUP", channel or ns.T("NONE"), ns.GroupSync.GetRosterSize(), #peers, compatible))
	local c = ns.Diagnostics.counters
	ns.Print(ns.T("STATUS_MESSAGES", c.sent, c.received, c.rejected, ns.Sender.GetQueueLength(),
		YesNo(ns.Sender.IsPaused())))
	local real, test = ns.MarkerManager.Count()
	ns.Print(ns.T("STATUS_MARKERS", real, test, ns.MinimapOverlay.GetVisibleCount()))
	ns.Diagnostics.PrintCapabilities()
end

local function FormatCaps(caps)
	if not caps then
		return ns.T("UNKNOWN")
	end
	local decoded = ns.GroupSync.DecodeCaps(caps)
	local parts = {}
	for _, name in ipairs({ "SHARE", "RECEIVE", "HERB_TRACKING", "ORE_TRACKING", "MINIMAP_PROBE" }) do
		if decoded[name] then
			parts[#parts + 1] = ns.T("CAP_" .. name)
		end
	end
	return #parts > 0 and table.concat(parts, ", ") or ns.T("NONE")
end

local function PrintPeers()
	local peers = ns.GroupSync.GetPeers()
	if not ns.GroupSync.IsInGroup() then
		ns.Print(ns.T("PEERS_NO_GROUP"))
		return
	end
	ns.Print(ns.T("PEERS_HEADER", #peers))
	local now = ns.Now()
	local known = {}
	for _, entry in ipairs(peers) do
		local peer = entry.peer
		known[entry.name] = true
		local compat
		if peer.compatible == nil then
			compat = ns.T("PEER_COMPAT_UNKNOWN")
		else
			compat = peer.compatible and ns.T("PEER_COMPAT_OK") or ns.T("PEER_COMPAT_BAD")
		end
		ns.Print(ns.T("PEER_LINE", ns.ShortName(entry.name), tostring(peer.addonVersion or "?"),
			tostring(peer.proto or "?"), compat, floor(now - (peer.lastSeen or now)), peer.messages,
			peer.sharing and ns.T("YES") or ns.T("NO"), FormatCaps(peer.caps)))
	end
	-- membres du groupe sans addon détecté (aucun message reçu)
	local others = {}
	for i = 1, 40 do
		local unit = (IsInRaid() and "raid" or "party") .. i
		local name = ns.UnitFullNameSafe(unit)
		if name and not known[name] and name ~= ns.GetPlayerFullName() then
			others[#others + 1] = ns.ShortName(name)
		end
	end
	if #others > 0 then
		ns.Print(ns.T("PEERS_WITHOUT_ADDON", table.concat(others, ", ")))
	end
end

local function PrintDiagnostics()
	PrintVersion()
	local results = ns.Diagnostics.RunProbes()
	ns.Diagnostics.PrintProbes(results)
	ns.Diagnostics.PrintCapabilities()
	ns.Diagnostics.PrintCounters()
	ns.Diagnostics.SaveReport(results)
end

---------------------------------------------------------------------------
-- Test contrôlé (source TEST)
---------------------------------------------------------------------------

local function RunTest()
	if not ns.Config.Get("enabled") then
		ns.Print(ns.T("ADDON_DISABLED"))
		return
	end
	ns.Print(ns.T("TEST_START"))

	-- 1. Affichage local d'un marqueur TEST
	local mapID, x, y = ns.Coordinates.GetPlayerMapPosition()
	local node
	if not mapID then
		ns.Print(ns.T("TEST_NO_POSITION", tostring(x)))
	else
		local width, height = ns.Coordinates.GetMapSizeYards(mapID)
		if not width then
			ns.Print(ns.T("TEST_NO_MAPSIZE"))
		else
			local tx, ty = ns.Coordinates.ApplyOffset(width, height, x, y, TEST_OFFSET_YARDS, TEST_OFFSET_YARDS)
			tx, ty = ns.Clamp(tx, 0, 1), ns.Clamp(ty, 0, 1)
			testCounter = testCounter + 1
			node = {
				id = format("t%d%d", floor(ns.Now()) % 100000, testCounter),
				source = "TEST", kind = "TEST", state = "DETECTED",
				uiMapID = mapID, x = tx, y = ty, accuracy = 0, age = 0, resourceID = 0,
				name = "TEST",
			}
			local marker, action = ns.MarkerManager.Upsert({
				sender = ns.GetPlayerFullName() or "?", id = node.id, source = node.source, kind = node.kind,
				state = node.state, uiMapID = mapID, x = tx, y = ty, accuracy = 0, name = ns.T("TEST_MARKER_NAME"),
				isLocal = true,
			})
			if marker then
				ns.Fire("PGR_MARKERS_CHANGED")
				ns.Print(ns.T("TEST_LOCAL_MARKER", mapID, tx * 100, ty * 100))
			else
				ns.Print(ns.T("TEST_LOCAL_FAILED", tostring(action)))
			end
		end
	end

	-- 2. Communication : PING/PONG et diffusion du marqueur TEST
	if not ns.GroupSync.IsInGroup() then
		ns.Print(ns.T("TEST_NO_GROUP"))
		return
	end
	local ok, reason = ns.GroupSync.StartPingTest()
	if not ok then
		ns.Print(ns.T("TEST_PING_FAILED", tostring(reason)))
		return
	end
	ns.Print(ns.T("TEST_PING_SENT", ns.Sender.GetChannel() or "?"))
	if node then
		ns.Sender.SendNode(node)
	end
end

---------------------------------------------------------------------------
-- Sondes
---------------------------------------------------------------------------

local function PrintTracking()
	local state = ns.Tracking.GetTrackingState()
	if not state.available then
		ns.Print(ns.T("TRACKING_UNAVAILABLE", tostring(state.reason)))
		return
	end
	ns.Print(ns.T("TRACKING_STATE", state.count,
		state.herbs and format("%s (%s)", state.herbs.name, state.herbs.active and ns.T("ACTIVE") or ns.T("INACTIVE"))
			or ns.T("NONE"),
		state.ores and format("%s (%s)", state.ores.name, state.ores.active and ns.T("ACTIVE") or ns.T("INACTIVE"))
			or ns.T("NONE")))
end

local function PrintVignettes()
	if not (C_VignetteInfo and C_VignetteInfo.GetVignettes) then
		ns.Print(ns.T("VIGNETTES_UNAVAILABLE"))
		return
	end
	local list = C_VignetteInfo.GetVignettes() or {}
	ns.Print(ns.T("VIGNETTES_HEADER", #list))
	local mapID = ns.Coordinates.GetPlayerMapPosition()
	for i = 1, math.min(#list, 15) do
		local guid = list[i]
		local info = C_VignetteInfo.GetVignetteInfo(guid)
		if not ns.IsSecret(info) and info and not ns.AnySecret(info.name, info.atlasName) then
			local position = mapID and C_VignetteInfo.GetVignettePosition and C_VignetteInfo.GetVignettePosition(guid, mapID)
			local px, py
			if not ns.IsSecret(position) and type(position) == "table" then
				px, py = position:GetXY()
				if ns.AnySecret(px, py) then
					px, py = nil, nil
				end
			end
			ns.Print("  %s [%s] %s", tostring(info.name), tostring(info.atlasName),
				px and format("(%.1f, %.1f)", px * 100, py * 100) or ns.T("NO_POSITION"))
		end
	end
end

local function Probe(argument)
	if argument == "minimap" then
		ns.Tracking.TogglePassiveProbe()
	elseif argument == "scan" then
		local ok, reason = ns.Tracking.StartScanProbe()
		if not ok then
			ns.Print(ns.T("PROBE_SCAN_IMPOSSIBLE", tostring(reason)))
		end
	elseif argument == "tracking" then
		PrintTracking()
	elseif argument == "vignettes" then
		PrintVignettes()
	else
		ns.Diagnostics.PrintProbes(ns.Diagnostics.RunProbes())
		ns.Print(ns.T("PROBE_HINT"))
	end
end

---------------------------------------------------------------------------
-- Réglages simples en ligne de commande (la fenêtre de paramètres arrive en phase 4)
---------------------------------------------------------------------------

local TOGGLES = { share = "shareEnabled", receive = "receiveEnabled", minimap = "showMinimap" }

local function SetToggle(key, argument)
	local value
	if argument == "on" then
		value = true
	elseif argument == "off" then
		value = false
	else
		value = not ns.Config.Get(key)
	end
	ns.Config.Set(key, value)
	ns.Print(ns.T("SETTING_CHANGED", key, YesNo(value)))
end

---------------------------------------------------------------------------
-- Aide et routage
---------------------------------------------------------------------------

local HELP_KEYS = {
	"HELP_PGR", "HELP_HELP", "HELP_STATUS", "HELP_DEBUG", "HELP_TEST", "HELP_PEERS", "HELP_CLEAR", "HELP_VERSION",
	"HELP_DIAG", "HELP_PROBE", "HELP_LOG", "HELP_TOGGLES",
}

local function PrintHelp()
	ns.Print(ns.T("HELP_HEADER"))
	for _, key in ipairs(HELP_KEYS) do
		ns.Print("  " .. ns.T(key))
	end
end

local HANDLERS = {
	help = PrintHelp,
	status = PrintStatus,
	version = PrintVersion,
	peers = PrintPeers,
	test = RunTest,
	diag = PrintDiagnostics,
	probe = Probe,
	debug = function()
		local value = not ns.Config.Get("debug")
		ns.Config.Set("debug", value)
		ns.Print(ns.T(value and "DEBUG_ON" or "DEBUG_OFF"))
	end,
	clear = function(argument)
		if argument == "log" then
			ns.Diagnostics.ClearPersistedLog()
			ns.Print(ns.T("LOG_CLEARED"))
			return
		end
		local removed = ns.MarkerManager.ClearTemporary()
		ns.Fire("PGR_MARKERS_CHANGED")
		ns.Print(ns.T("CLEARED", removed))
	end,
	log = function(argument)
		local count = tonumber(argument) or 15
		for _, line in ipairs(ns.Diagnostics.GetRecentLog(count)) do
			ns.Print("|cff999999%s|r", line)
		end
	end,
	on = function() ns.Config.Set("enabled", true); ns.Print(ns.T("ADDON_ENABLED")) end,
	off = function() ns.Config.Set("enabled", false); ns.Print(ns.T("ADDON_DISABLED")) end,
}

function Commands.Handle(input)
	if not ns.db then
		ns.Print(ns.T("NOT_READY"))
		return
	end
	input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	local command, argument = input:match("^(%S+)%s*(.-)$")
	if not command then
		PrintHelp()
		ns.Print(ns.T("SETTINGS_WINDOW_LATER"))
		return
	end
	if TOGGLES[command] then
		SetToggle(TOGGLES[command], argument)
		return
	end
	local handler = HANDLERS[command]
	if handler then
		handler(argument)
	else
		ns.Print(ns.T("UNKNOWN_COMMAND", command))
	end
end

SLASH_PARTYGATHERRADAR1 = "/pgr"
SlashCmdList.PARTYGATHERRADAR = function(input)
	ns.SafeCall("Commands", Commands.Handle, input)
end

ns.RegisterEvent("PLAYER_LOGIN", "Commands", function()
	ns.UnregisterEvent("PLAYER_LOGIN", "Commands")
	local build = ns.Diagnostics.GetBuild()
	ns.Print(ns.T("LOADED", ns.VERSION))
	if not build.matchesTarget then
		ns.Print(ns.T("INTERFACE_MISMATCH", tostring(build.toc), ns.TARGET_INTERFACE))
	end
end)
