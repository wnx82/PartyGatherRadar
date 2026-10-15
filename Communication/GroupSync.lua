-- PartyGatherRadar - Communication/GroupSync.lua
-- Composition du groupe, découverte des autres clients PartyGatherRadar (HELLO), compatibilité
-- de protocole, nettoyage lors des départs, test de communication PING/PONG.
--
-- L'identité d'un émetteur est vérifiée contre la composition du groupe lue avec UnitFullName :
-- un message d'un joueur absent du groupe est rejeté par le récepteur.

local addonName, ns = ...

local GroupSync = ns.NewModule("GroupSync")
ns.GroupSync = GroupSync

local pairs, type, tostring, floor, random = pairs, type, tostring, math.floor, math.random
local format = string.format

local HELLO_MIN_INTERVAL = 10 -- secondes entre deux HELLO demandant une réponse
local HELLO_DELAY = 2         -- regroupe les événements de groupe rapprochés
local PING_TIMEOUT = 5
local REPLY_MIN_INTERVAL = 5  -- au plus une réponse HELLO (diffusée à tous) sur cette durée
local PONG_MIN_INTERVAL = 2   -- au plus un PONG par pair sur cette durée

local roster = {}  -- [nom complet] = unité ("party1", "raid3"...)
local peers = {}   -- [nom complet] = { addonVersion, proto, minProto, caps, compatible, firstSeen, lastSeen, messages, sharing }
local inGroup = false
local lastRosterSize = 0
local lastHelloAt = -HELLO_MIN_INTERVAL
local helloScheduled = false
local pingTest -- { nonce, sentAt, responses = { [nom] = rtt } }
local lastHelloReplyAt = -REPLY_MIN_INTERVAL
local helloReplyScheduled = false
local lastPongAt = {}  -- [nom] = heure de notre dernier PONG à ce pair

---------------------------------------------------------------------------
-- Capacités locales annoncées
---------------------------------------------------------------------------

function GroupSync.GetLocalCaps()
	local CAPS = ns.Protocol.CAPS
	local caps = 0
	if ns.Config.Get("shareEnabled") then
		caps = caps + CAPS.SHARE
	end
	if ns.Config.Get("receiveEnabled") then
		caps = caps + CAPS.RECEIVE
	end
	local tracking = ns.Tracking and ns.Tracking.GetTrackingState()
	if tracking and tracking.herbs then
		caps = caps + CAPS.HERB_TRACKING
	end
	if tracking and tracking.ores then
		caps = caps + CAPS.ORE_TRACKING
	end
	if ns.Tracking and #ns.Tracking.FindBlipApis() == 3 then
		caps = caps + CAPS.MINIMAP_PROBE
	end
	return caps
end

--- Décode le champ de capacités en table de booléens.
function GroupSync.DecodeCaps(caps)
	local result = {}
	for name, bit in pairs(ns.Protocol.CAPS) do
		result[name] = floor(caps / bit) % 2 == 1
	end
	return result
end

---------------------------------------------------------------------------
-- Composition du groupe
---------------------------------------------------------------------------

function GroupSync.IsGroupMember(fullName)
	return fullName ~= nil and roster[fullName] ~= nil
end

function GroupSync.GetRosterSize()
	local count = 0
	for _ in pairs(roster) do
		count = count + 1
	end
	return count
end

--- Identités des autres membres du groupe (vous exclu), triées.
function GroupSync.GetRosterNames()
	local names = {}
	for name in pairs(roster) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

local function RemovePeer(name, reason)
	local peer = peers[name]
	peers[name] = nil
	lastPongAt[name] = nil
	local touched = ns.MarkerManager.RemoveBySender(name)
	ns.Diagnostics.Log("GROUP", "%s retiré (%s), %d marqueur(s) nettoyé(s)", name, reason, touched)
	if peer or touched > 0 then
		ns.Fire("PGR_PEERS_CHANGED")
		ns.Fire("PGR_MARKERS_CHANGED")
	end
end

--- Supprime toutes les données venant d'autres joueurs (sortie du groupe).
local function ForgetGroup()
	for name in pairs(peers) do
		RemovePeer(name, "groupe quitté")
	end
	-- marqueurs d'émetteurs qui n'avaient pas encore envoyé HELLO
	local others = {}
	local me = ns.GetPlayerFullName()
	ns.MarkerManager.ForEach(function(marker)
		for reporter in pairs(marker.reporters) do
			if reporter ~= me then
				others[reporter] = true
			end
		end
	end)
	for name in pairs(others) do
		ns.MarkerManager.RemoveBySender(name)
	end
	ns.Sender.Clear()
	pingTest = nil
	ns.Wipe(lastPongAt)
	ns.Fire("PGR_PEERS_CHANGED")
	ns.Fire("PGR_MARKERS_CHANGED")
end

function GroupSync.RebuildRoster()
	ns.Wipe(roster)
	local nowInGroup = IsInGroup and IsInGroup() or false
	if nowInGroup then
		local isRaid = IsInRaid and IsInRaid() or false
		local total = GetNumGroupMembers and GetNumGroupMembers() or 0
		local count = isRaid and total or (total - 1)
		local me = ns.GetPlayerFullName()
		for i = 1, count do
			local unit = (isRaid and "raid" or "party") .. i
			local name = ns.UnitFullNameSafe(unit)
			if name and name ~= me then
				roster[name] = unit
			end
		end
	end

	local wasInGroup = inGroup
	inGroup = nowInGroup
	local previousSize = lastRosterSize
	lastRosterSize = GroupSync.GetRosterSize()
	if wasInGroup and not nowInGroup then
		ForgetGroup()
		ns.Diagnostics.Log("GROUP", "groupe quitté")
		return
	end
	for name in pairs(peers) do
		if not roster[name] then
			RemovePeer(name, "a quitté le groupe")
		end
	end
	if nowInGroup and not wasInGroup then
		ns.Diagnostics.Log("GROUP", "groupe rejoint (%d autre(s) membre(s))", lastRosterSize)
		GroupSync.RequestHello("groupe rejoint")
	elseif nowInGroup and lastRosterSize ~= previousSize then
		-- la composition arrive parfois après GROUP_JOINED : trace utile pour vérifier les identités en jeu
		ns.Diagnostics.Log("GROUP", "composition : %d autre(s) membre(s)", lastRosterSize)
	end
end

---------------------------------------------------------------------------
-- HELLO
---------------------------------------------------------------------------

--- Programme un HELLO (réponse demandée). Regroupe les demandes rapprochées et respecte l'intervalle minimal.
function GroupSync.RequestHello(reason)
	if helloScheduled then
		return
	end
	helloScheduled = true
	ns.After(HELLO_DELAY, "GroupSync", function()
		helloScheduled = false
		if not inGroup or not ns.Config.Get("enabled") then
			return
		end
		local now = ns.Now()
		if now - lastHelloAt < HELLO_MIN_INTERVAL then
			return
		end
		lastHelloAt = now
		ns.Diagnostics.Log("GROUP", "HELLO (%s)", tostring(reason))
		ns.Sender.SendHello(false)
	end)
end

local function GetPeer(sender, proto)
	local now = ns.Now()
	local peer = peers[sender]
	if not peer then
		peer = { firstSeen = now, messages = 0, sharing = true, proto = proto }
		peers[sender] = peer
	end
	peer.lastSeen = now
	return peer
end

--- Tout message valide reçu d'un membre du groupe met à jour son entrée (appelé une fois par message).
function GroupSync.OnPeerMessage(sender, message)
	local peer = GetPeer(sender, message.proto)
	peer.messages = peer.messages + 1
	if not ns.Diagnostics.flags.peerMessageFrom then
		ns.Diagnostics.SetFlag("peerMessageFrom", sender)
	end
end

function GroupSync.OnHello(sender, message)
	local peer = GetPeer(sender, message.proto)
	local isNew = peer.addonVersion == nil
	peer.addonVersion = message.addonVersion
	peer.proto = message.proto
	peer.minProto = message.minProto
	peer.caps = message.caps
	peer.sharing = true
	peer.compatible = ns.Protocol.IsCompatible(message.proto, message.minProto)
	if isNew and not peer.mismatchWarned then
		if peer.compatible then
			ns.Print(ns.T("PEER_DISCOVERED", ns.ShortName(sender), message.addonVersion, message.proto))
		else
			ns.Print(ns.T("PEER_INCOMPATIBLE", ns.ShortName(sender), message.addonVersion, message.proto))
		end
		ns.Fire("PGR_PEERS_CHANGED")
	end
	if message.wantsReply then
		GroupSync.ScheduleHelloReply()
	end
end

--- Répond à un HELLO. La réponse est diffusée au groupe, donc une seule réponse sert tous les
--- demandeurs : au plus une toutes les REPLY_MIN_INTERVAL secondes ; une demande arrivée trop tôt
--- (rechargement d'un pair juste après sa première annonce) reçoit une réponse différée, jamais aucune.
function GroupSync.ScheduleHelloReply()
	local now = ns.Now()
	local wait = lastHelloReplyAt + REPLY_MIN_INTERVAL - now
	if wait <= 0 then
		lastHelloReplyAt = now
		ns.Sender.SendHello(true)
		return
	end
	ns.Diagnostics.Count("repliesDeferred")
	if helloReplyScheduled then
		return
	end
	helloReplyScheduled = true
	ns.After(wait, "GroupSync", function()
		helloReplyScheduled = false
		if inGroup then
			lastHelloReplyAt = ns.Now()
			ns.Sender.SendHello(true)
		end
	end)
end

--- Informations connues sur un pair (ou nil).
function GroupSync.GetPeerInfo(name)
	return peers[name]
end

--- Un pair dont la version est plus récente envoie des messages illisibles : on le signale une fois.
function GroupSync.OnVersionMismatch(sender, reason)
	local peer = GetPeer(sender, nil)
	peer.compatible = false
	if not peer.mismatchWarned then
		peer.mismatchWarned = true
		ns.Print(ns.T("PEER_VERSION_MISMATCH", ns.ShortName(sender), reason))
		ns.Fire("PGR_PEERS_CHANGED")
	end
end

function GroupSync.OnBye(sender)
	local peer = GetPeer(sender, nil)
	peer.sharing = false
	local touched = ns.MarkerManager.RemoveBySender(sender)
	ns.Diagnostics.Log("GROUP", "%s arrête le partage, %d marqueur(s) retiré(s)", sender, touched)
	ns.Fire("PGR_PEERS_CHANGED")
	ns.Fire("PGR_MARKERS_CHANGED")
end

--- Liste des pairs triée par nom : { name, peer }.
function GroupSync.GetPeers()
	local list = {}
	for name, peer in pairs(peers) do
		list[#list + 1] = { name = name, peer = peer }
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

function GroupSync.IsInGroup()
	return inGroup
end

---------------------------------------------------------------------------
-- Test PING/PONG
---------------------------------------------------------------------------

local function NewNonce()
	local chars = "0123456789abcdefghijklmnopqrstuvwxyz"
	local nonce = {}
	for i = 1, 6 do
		local index = random(1, #chars)
		nonce[i] = chars:sub(index, index)
	end
	return table.concat(nonce)
end

--- Envoie un PING au groupe ; le bilan est affiché après PING_TIMEOUT secondes.
function GroupSync.StartPingTest()
	if not inGroup then
		return false, "nogroup"
	end
	local nonce = NewNonce()
	local ok, reason = ns.Sender.SendPing(nonce, false)
	if not ok then
		return false, reason
	end
	pingTest = { nonce = nonce, sentAt = ns.Now(), responses = {} }
	local current = pingTest
	ns.After(PING_TIMEOUT, "GroupSync", function()
		if pingTest ~= current then
			return
		end
		pingTest = nil
		local count = 0
		for name, rtt in pairs(current.responses) do
			count = count + 1
			ns.Print(ns.T("TEST_PONG_FROM", ns.ShortName(name), rtt * 1000))
			ns.Diagnostics.Log("TEST", "PONG reçu de %s en %.0f ms", name, rtt * 1000)
		end
		if count == 0 then
			ns.Print(ns.T("TEST_NO_PONG", PING_TIMEOUT))
			ns.Diagnostics.Log("TEST", "aucun PONG reçu en %d s", PING_TIMEOUT)
		end
		local last = ns.Sender.lastResult
		if last then
			ns.Print(ns.T("TEST_LAST_SEND", tostring(last.label), tostring(last.outcome), tostring(last.name),
				tostring(last.channel)))
		end
	end)
	return true
end

function GroupSync.OnPing(sender, message)
	local now = ns.Now()
	if now - (lastPongAt[sender] or -PONG_MIN_INTERVAL) < PONG_MIN_INTERVAL then
		ns.Diagnostics.Count("repliesSkipped")
		return
	end
	lastPongAt[sender] = now
	ns.Sender.SendPing(message.nonce, true, sender)
end

function GroupSync.OnPong(sender, message)
	if pingTest and pingTest.nonce == message.nonce and not pingTest.responses[sender] then
		pingTest.responses[sender] = ns.Now() - pingTest.sentAt
	end
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

local function OnRosterChanged()
	GroupSync.RebuildRoster()
end

ns.RegisterEvent("GROUP_ROSTER_UPDATE", "GroupSync", OnRosterChanged)
ns.RegisterEvent("GROUP_JOINED", "GroupSync", OnRosterChanged)
ns.RegisterEvent("GROUP_LEFT", "GroupSync", OnRosterChanged)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", "GroupSync", function(_, isInitialLogin, isReloadingUi)
	ns.playerFullName = nil -- le royaume peut être indisponible avant la première entrée dans le monde
	GroupSync.RebuildRoster()
	-- après une connexion ou un /reload, les autres clients ne nous connaissent plus : nouvelle annonce
	if inGroup and (isInitialLogin or isReloadingUi) then
		GroupSync.RequestHello("connexion")
	end
end)

ns.On("PGR_SETTING_CHANGED", "GroupSync", function(_, key, value)
	if key == "shareEnabled" or key == "enabled" then
		if value then
			lastHelloAt = -HELLO_MIN_INTERVAL
			GroupSync.RequestHello("partage activé")
		elseif inGroup then
			ns.Sender.SendBye()
		end
	end
end)
