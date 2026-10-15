-- PartyGatherRadar - Core/Diagnostics.lua
-- Journal de diagnostic, compteurs, dernière erreur, sondes d'API et matrice de capacités.
-- Les sondes n'appellent que des fonctions publiques du client, protégées par pcall :
-- une API absente ou modifiée pendant la bêta produit un résultat "ABSENT"/"ERREUR", jamais une erreur Lua.

local addonName, ns = ...

local Diagnostics = ns.NewModule("Diagnostics")
ns.Diagnostics = Diagnostics

local pcall, type, tostring, pairs, ipairs, select = pcall, type, tostring, pairs, ipairs, select
local format, sqrt, abs = string.format, math.sqrt, math.abs

local LOG_MAX = 200           -- entrées gardées en mémoire
local PERSISTED_LOG_MAX = 300 -- entrées gardées dans les SavedVariables quand le mode journal est actif

-- Statuts des sondes
Diagnostics.OK = "OK"
Diagnostics.ABSENT = "ABSENT"
Diagnostics.ERROR = "ERREUR"
Diagnostics.UNAVAILABLE = "INDISPONIBLE"
Diagnostics.SECRET = "SECRET"
Diagnostics.WARN = "ATTENTION"
Diagnostics.INFO = "INFO"

Diagnostics.counters = {
	sent = 0,             -- messages acceptés localement par l'API (pas forcément reçus)
	sendRefused = 0,      -- messages refusés par l'API (code de retour non nul)
	throttled = 0,        -- refus pour limitation de fréquence
	lockdown = 0,         -- refus pour verrouillage de la messagerie des addons
	dropped = 0,          -- messages abandonnés (file pleine, expirés, pas de groupe)
	received = 0,         -- messages valides reçus d'un autre membre
	rejected = 0,         -- messages reçus rejetés (voir rejectReasons)
	echoes = 0,           -- nos propres messages renvoyés par le serveur (ignorés)
}
Diagnostics.rejectReasons = {}
Diagnostics.lastError = nil
Diagnostics.flags = {}       -- constats faits en jeu (ex. infobulle de minicarte observée)
Diagnostics.lastProbe = nil

local memoryLog = {}
local memoryLogFirst, memoryLogCount = 1, 0
local persistedLog -- table des SavedVariables, attachée par Config

---------------------------------------------------------------------------
-- Journal
---------------------------------------------------------------------------

local function IsDebugEnabled()
	return ns.db ~= nil and ns.db.settings ~= nil and ns.db.settings.debug == true
end

local function Append(line)
	if memoryLogCount < LOG_MAX then
		memoryLogCount = memoryLogCount + 1
		memoryLog[memoryLogCount] = line
	else
		memoryLog[memoryLogFirst] = line
		memoryLogFirst = memoryLogFirst % LOG_MAX + 1
	end
	if persistedLog and IsDebugEnabled() then
		persistedLog[#persistedLog + 1] = line
		while #persistedLog > PERSISTED_LOG_MAX do
			table.remove(persistedLog, 1)
		end
	end
end

--- Ajoute une ligne au journal. Affichée dans la discussion seulement en mode diagnostic.
function Diagnostics.Log(category, message, ...)
	if select("#", ...) > 0 then
		local ok, formatted = pcall(format, message, ...)
		message = ok and formatted or tostring(message)
	end
	local line = format("[%.1f] %s: %s", ns.Now(), tostring(category), tostring(message))
	Append(line)
	if IsDebugEnabled() then
		ns.Print("|cff999999%s|r", line)
	end
end

--- Renvoie les `count` dernières lignes du journal mémoire (ordre chronologique).
function Diagnostics.GetRecentLog(count)
	local result = {}
	local start = memoryLogCount - (count or memoryLogCount) + 1
	if start < 1 then
		start = 1
	end
	for i = start, memoryLogCount do
		local index = (memoryLogFirst + i - 2) % LOG_MAX + 1
		result[#result + 1] = memoryLog[index]
	end
	return result
end

--- Appelé par Config après le chargement des SavedVariables.
function Diagnostics.AttachStorage(storage)
	if type(storage.log) ~= "table" then
		storage.log = {}
	end
	persistedLog = storage.log
end

function Diagnostics.ClearPersistedLog()
	if persistedLog then
		ns.Wipe(persistedLog)
	end
end

---------------------------------------------------------------------------
-- Compteurs et erreurs
---------------------------------------------------------------------------

function Diagnostics.Count(name, amount)
	Diagnostics.counters[name] = (Diagnostics.counters[name] or 0) + (amount or 1)
end

local REJECT_LOG_LIMIT = 20 -- au-delà, les rejets d'un même motif sont seulement comptés

function Diagnostics.Reject(reason, detail)
	Diagnostics.Count("rejected")
	local count = (Diagnostics.rejectReasons[reason] or 0) + 1
	Diagnostics.rejectReasons[reason] = count
	-- n'importe quel joueur peut envoyer des messages PGRadar (chuchotement) : pas de flot dans le journal
	if count <= REJECT_LOG_LIMIT then
		Diagnostics.Log("RECV", "rejet (%s) %s", tostring(reason), detail and tostring(detail) or "")
	end
end

function Diagnostics.RecordError(source, err)
	Diagnostics.lastError = { source = tostring(source), message = tostring(err), at = ns.Now() }
	Diagnostics.Log("ERREUR", "%s : %s", tostring(source), tostring(err))
end

function Diagnostics.SetFlag(name, value)
	Diagnostics.flags[name] = value
end

---------------------------------------------------------------------------
-- Informations de build
---------------------------------------------------------------------------

--- Version du client. Renvoie une table (champs nil si l'API est absente).
function Diagnostics.GetBuild()
	local info = {}
	if GetBuildInfo then
		local ok, version, build, date, toc = pcall(GetBuildInfo)
		if ok then
			info.version, info.build, info.date, info.toc = version, build, date, tonumber(toc)
		end
	end
	info.projectID = WOW_PROJECT_ID
	info.camelotID = WOW_PROJECT_CAMELOT
	-- Forever tourne sur le client moderne avec des numéros d'interface 16xxx ; WOW_PROJECT_CAMELOT est
	-- utilisé en complément quand il est défini (constatée dans les addons Forever installés, non documentée).
	info.isForever = (info.toc ~= nil and info.toc >= 16000 and info.toc < 20000)
		or (WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT)
	info.matchesTarget = info.toc == ns.TARGET_INTERFACE
	return info
end

---------------------------------------------------------------------------
-- Sondes d'API
---------------------------------------------------------------------------

local function Exists(path)
	local value = _G
	for part in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then
			return false
		end
		value = value[part]
	end
	return value ~= nil
end

local function Add(results, id, status, detail)
	results[#results + 1] = { id = id, status = status, detail = detail }
end

local function ProbeExistence(results, paths)
	for _, path in ipairs(paths) do
		Add(results, path, Exists(path) and Diagnostics.OK or Diagnostics.ABSENT)
	end
end

local function ProbeLive(results, id, fn)
	local ok, status, detail = pcall(fn)
	if not ok then
		Add(results, id, Diagnostics.ERROR, tostring(status))
	else
		Add(results, id, status, detail)
	end
end

local API_PATHS = {
	"GetBuildInfo",
	"C_ChatInfo.RegisterAddonMessagePrefix",
	"C_ChatInfo.SendAddonMessage",
	"C_ChatInfo.IsAddonMessagePrefixRegistered",
	"C_ChatInfo.InChatMessagingLockdown",
	"C_ChatInfo.AreOutgoingAddonChatMessagesRestricted",
	"Enum.SendAddonMessageResult",
	"C_RestrictedActions.IsAddOnRestrictionActive",
	"C_Map.GetBestMapForUnit",
	"C_Map.GetPlayerMapPosition",
	"C_Map.GetWorldPosFromMapPos",
	"C_Map.GetMapPosFromWorldPos",
	"C_Map.GetMapInfo",
	"CreateVector2D",
	"UnitPosition",
	"GetPlayerFacing",
	"IsIndoors",
	"Minimap",
	"C_Minimap.GetViewRadius",
	"C_Minimap.GetNumTrackingTypes",
	"C_Minimap.GetTrackingInfo",
	"C_VignetteInfo.GetVignettes",
	"C_VignetteInfo.GetVignetteInfo",
	"C_VignetteInfo.GetVignettePosition",
	"C_Spell.GetSpellInfo",
	"C_Spell.GetSpellName",
	"C_Item.GetItemInfo",
	"C_AddOns.GetAddOnMetadata",
	"issecretvalue",
	"canaccessvalue",
	"C_Timer.NewTicker",
	"GetMinimapShape",
}

--- Exécute toutes les sondes. Renvoie la liste des résultats (aussi mémorisée pour /pgr diag).
function Diagnostics.RunProbes()
	local results = {}

	-- Build
	local build = Diagnostics.GetBuild()
	Add(results, "build", build.version and Diagnostics.INFO or Diagnostics.ABSENT,
		format("%s (%s) interface %s, WOW_PROJECT_ID=%s, WOW_PROJECT_CAMELOT=%s",
			tostring(build.version), tostring(build.build), tostring(build.toc),
			tostring(build.projectID), tostring(build.camelotID)))
	Add(results, "interface", build.matchesTarget and Diagnostics.OK or Diagnostics.WARN,
		format("attendue %d, client %s", ns.TARGET_INTERFACE, tostring(build.toc)))

	-- Présence des fonctions
	ProbeExistence(results, API_PATHS)

	-- Communication
	ProbeLive(results, "prefix.registered", function()
		if not (C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered) then
			return Diagnostics.ABSENT
		end
		local registered = C_ChatInfo.IsAddonMessagePrefixRegistered(ns.PREFIX)
		return registered and Diagnostics.OK or Diagnostics.UNAVAILABLE, ns.PREFIX
	end)
	ProbeLive(results, "comm.lockdown", function()
		if not (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) then
			return Diagnostics.ABSENT
		end
		local locked = C_ChatInfo.InChatMessagingLockdown()
		if ns.IsSecret(locked) then
			return Diagnostics.SECRET
		end
		return locked and Diagnostics.WARN or Diagnostics.OK, locked and "verrouillée" or "libre"
	end)
	ProbeLive(results, "comm.realmRestricted", function()
		if not (C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) then
			return Diagnostics.ABSENT
		end
		local restricted = C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()
		if ns.IsSecret(restricted) then
			return Diagnostics.SECRET
		end
		-- valeur informative seulement : signalée comme peu fiable, le code de retour de l'envoi fait foi
		return Diagnostics.INFO, tostring(restricted)
	end)
	ProbeLive(results, "comm.channel", function()
		local channel = ns.Sender and ns.Sender.GetChannel()
		return channel and Diagnostics.OK or Diagnostics.UNAVAILABLE, channel or "pas de groupe"
	end)

	-- Localisation
	ProbeLive(results, "map.player", function()
		local coords = ns.Coordinates
		local mapID, x, y = coords.GetPlayerMapPosition()
		if not mapID then
			return Diagnostics.UNAVAILABLE, tostring(x) -- x contient la raison
		end
		local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
		return Diagnostics.OK, format("carte %d (%s) x=%.4f y=%.4f", mapID, info and info.name or "?", x, y)
	end)
	ProbeLive(results, "map.size", function()
		local mapID = ns.Coordinates.GetPlayerMapPosition()
		if not mapID then
			return Diagnostics.UNAVAILABLE
		end
		local width, height = ns.Coordinates.GetMapSizeYards(mapID)
		if not width then
			return Diagnostics.UNAVAILABLE, "conversion monde impossible"
		end
		return Diagnostics.OK, format("%.0f x %.0f m", width, height)
	end)
	ProbeLive(results, "map.roundtrip", function()
		local mapID, x, y = ns.Coordinates.GetPlayerMapPosition()
		if not mapID then
			return Diagnostics.UNAVAILABLE
		end
		local rx, ry = ns.Coordinates.TranslateToMap(mapID, x, y, mapID, true)
		if not rx then
			return Diagnostics.UNAVAILABLE, "aller-retour carte -> monde -> carte impossible"
		end
		local err = sqrt((rx - x) ^ 2 + (ry - y) ^ 2)
		return err < 0.0005 and Diagnostics.OK or Diagnostics.WARN, format("écart %.6f", err)
	end)
	ProbeLive(results, "UnitPosition.live", function()
		if not UnitPosition then
			return Diagnostics.ABSENT
		end
		local a, b, c, instanceID = UnitPosition("player")
		if ns.AnySecret(a, b, instanceID) then
			return Diagnostics.SECRET
		end
		if a == nil then
			return Diagnostics.UNAVAILABLE, "nil (instance ?)"
		end
		return Diagnostics.OK, format("%.1f, %.1f instance %s", a, b, tostring(instanceID))
	end)

	-- Minicarte
	ProbeLive(results, "minimap.radius", function()
		local radius, source = ns.Coordinates.GetMinimapRadiusYards()
		if not radius then
			return Diagnostics.UNAVAILABLE, source
		end
		return Diagnostics.OK, format("%.1f m (%s), zoom %s", radius, source, tostring(Minimap and Minimap:GetZoom()))
	end)
	ProbeLive(results, "minimap.rotation", function()
		local rotate = ns.GetCVar("rotateMinimap") == "1"
		if not rotate then
			return Diagnostics.OK, "rotation désactivée"
		end
		local facing = GetPlayerFacing and GetPlayerFacing()
		if ns.IsSecret(facing) then
			return Diagnostics.SECRET
		end
		if facing == nil then
			return Diagnostics.UNAVAILABLE, "rotation active mais orientation indisponible"
		end
		return Diagnostics.WARN, format("rotation active (expérimental), orientation %.2f rad", facing)
	end)
	ProbeLive(results, "minimap.shape", function()
		local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
		return Diagnostics.INFO, tostring(shape)
	end)

	-- Détection
	ProbeLive(results, "tracking.types", function()
		local state = ns.Tracking and ns.Tracking.GetTrackingState()
		if not state then
			return Diagnostics.ABSENT
		end
		if not state.available then
			return Diagnostics.UNAVAILABLE, state.reason
		end
		return Diagnostics.INFO, format("%d types ; herbes : %s ; minerais : %s", state.count,
			state.herbs and (state.herbs.active and "actif" or "connu") or "non",
			state.ores and (state.ores.active and "actif" or "connu") or "non")
	end)
	ProbeLive(results, "detection.blipEnumeration", function()
		-- Aucune fonction publique ne liste les points de pistage dessinés sur la minicarte.
		return Diagnostics.UNAVAILABLE, "aucune API d'énumération des points de minicarte"
	end)
	ProbeLive(results, "detection.minimapProbeApi", function()
		-- Sondage officiel par point (client Forever) : expérimental, peut être restreint par Blizzard.
		local found = ns.Tracking and ns.Tracking.FindBlipApis() or {}
		if #found == 3 then
			return Diagnostics.WARN, "disponible (expérimental) : " .. table.concat(found, ", ")
		end
		if #found > 0 then
			return Diagnostics.UNAVAILABLE, "incomplet : " .. table.concat(found, ", ")
		end
		return Diagnostics.ABSENT
	end)
	ProbeLive(results, "detection.minimapScan", function()
		local result = Diagnostics.flags.minimapScanResult
		if result then
			return Diagnostics.WARN, "dernier balayage : " .. tostring(result)
		end
		return Diagnostics.INFO, "non exécuté (/pgr probe scan)"
	end)
	ProbeLive(results, "detection.minimapTooltip", function()
		local seen = Diagnostics.flags.minimapTooltipSeen
		if seen then
			return Diagnostics.WARN, "infobulle de minicarte lue (expérimental) : " .. tostring(seen)
		end
		return Diagnostics.INFO, "non observée (utiliser /pgr probe minimap puis survoler un point)"
	end)
	ProbeLive(results, "detection.vignettes", function()
		if not (C_VignetteInfo and C_VignetteInfo.GetVignettes) then
			return Diagnostics.ABSENT
		end
		local list = C_VignetteInfo.GetVignettes()
		return Diagnostics.INFO, format("%d vignette(s) visibles", type(list) == "table" and #list or 0)
	end)

	Diagnostics.lastProbe = { at = ns.Now(), results = results }
	Diagnostics.Log("DIAG", "sondes exécutées (%d résultats)", #results)
	return results
end

---------------------------------------------------------------------------
-- Matrice de capacités
---------------------------------------------------------------------------

--- Synthèse des quatre capacités clés. Chaque entrée : { status = "OUI"|"NON"|"PARTIEL"|"NON CONFIRMÉ", detail }.
function Diagnostics.GetCapabilities()
	local caps = {}

	-- A. Détection locale des ressources de la minicarte
	local probeApis = ns.Tracking and #ns.Tracking.FindBlipApis() == 3
	if Diagnostics.flags.minimapTooltipSeen then
		caps.localDetection = { status = "PARTIEL", detail = ns.T("CAP_DETECTION_TOOLTIP") }
	elseif probeApis then
		caps.localDetection = { status = "NON CONFIRMÉ", detail = ns.T("CAP_DETECTION_PROBE_API") }
	else
		caps.localDetection = { status = "NON", detail = ns.T("CAP_DETECTION_NONE") }
	end

	-- Localisation fiable
	local mapID, x, y = ns.Coordinates.GetPlayerMapPosition()
	if not mapID then
		caps.location = { status = "NON", detail = ns.T("CAP_LOCATION_NONE", tostring(x)) }
	else
		local rx, ry = ns.Coordinates.TranslateToMap(mapID, x, y, mapID, true)
		if rx and abs(rx - x) < 0.0005 and abs(ry - y) < 0.0005 then
			caps.location = { status = "OUI", detail = ns.T("CAP_LOCATION_OK") }
		else
			caps.location = { status = "PARTIEL", detail = ns.T("CAP_LOCATION_PARTIAL") }
		end
	end

	-- B. Synchronisation
	local registered = C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered
		and C_ChatInfo.IsAddonMessagePrefixRegistered(ns.PREFIX)
	local confirmedBy = Diagnostics.flags.peerMessageFrom
	if not registered then
		caps.sync = { status = "NON", detail = ns.T("CAP_SYNC_NOPREFIX") }
	elseif confirmedBy then
		caps.sync = { status = "OUI", detail = ns.T("CAP_SYNC_CONFIRMED", ns.ShortName(confirmedBy)) }
	else
		caps.sync = { status = "NON CONFIRMÉ", detail = ns.T("CAP_SYNC_UNCONFIRMED") }
	end

	-- C. Affichage sur la minicarte
	local radius = ns.Coordinates.GetMinimapRadiusYards()
	if Minimap and radius then
		caps.minimap = { status = "OUI", detail = ns.T("CAP_MINIMAP_OK") }
	else
		caps.minimap = { status = "NON", detail = ns.T("CAP_MINIMAP_NONE") }
	end

	return caps
end

---------------------------------------------------------------------------
-- Rapports dans la discussion
---------------------------------------------------------------------------

local STATUS_COLORS = {
	OK = "ff40ff40", ABSENT = "ffff4040", ERREUR = "ffff4040", INDISPONIBLE = "ffffa040",
	SECRET = "ffff40ff", ATTENTION = "ffffff40", INFO = "ff80c0ff",
	OUI = "ff40ff40", NON = "ffff4040", PARTIEL = "ffffff40", ["NON CONFIRMÉ"] = "ffffa040",
}

function Diagnostics.Colorize(status)
	local color = STATUS_COLORS[status] or "ffffffff"
	return "|c" .. color .. tostring(status) .. "|r"
end

function Diagnostics.PrintProbes(results)
	ns.Print(ns.T("DIAG_PROBES_HEADER"))
	for _, r in ipairs(results) do
		if r.detail then
			ns.Print("  %s : %s — %s", r.id, Diagnostics.Colorize(r.status), tostring(r.detail))
		else
			ns.Print("  %s : %s", r.id, Diagnostics.Colorize(r.status))
		end
	end
end

function Diagnostics.PrintCapabilities()
	local caps = Diagnostics.GetCapabilities()
	ns.Print(ns.T("DIAG_CAPS_HEADER"))
	local order = {
		{ "localDetection", "CAP_LABEL_DETECTION" },
		{ "location", "CAP_LABEL_LOCATION" },
		{ "sync", "CAP_LABEL_SYNC" },
		{ "minimap", "CAP_LABEL_MINIMAP" },
	}
	for _, entry in ipairs(order) do
		local cap = caps[entry[1]]
		ns.Print("  %s : %s — %s", ns.T(entry[2]), Diagnostics.Colorize(cap.status), cap.detail)
	end
end

function Diagnostics.PrintCounters()
	local c = Diagnostics.counters
	ns.Print(ns.T("DIAG_COUNTERS", c.sent, c.sendRefused, c.throttled, c.lockdown, c.dropped,
		c.received, c.rejected, c.echoes))
	local reasons = {}
	for reason, count in pairs(Diagnostics.rejectReasons) do
		reasons[#reasons + 1] = format("%s=%d", reason, count)
	end
	if #reasons > 0 then
		table.sort(reasons)
		ns.Print("  " .. ns.T("DIAG_REJECT_REASONS") .. " " .. table.concat(reasons, ", "))
	end
	local lastError = Diagnostics.lastError
	if lastError then
		ns.Print("  " .. ns.T("DIAG_LAST_ERROR", lastError.source, lastError.message,
			ns.Now() - lastError.at))
	else
		ns.Print("  " .. ns.T("DIAG_NO_ERROR"))
	end
end
