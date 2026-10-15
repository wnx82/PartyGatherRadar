-- PartyGatherRadar - Communication/Receiver.lua
-- Réception des messages d'addon (CHAT_MSG_ADDON) : vérifications strictes puis répartition.
--
-- Ordre des vérifications :
--   1. préfixe PGRadar ; 2. valeurs secrètes ; 3. canal de groupe autorisé (jamais de canal public
--   ni de chuchotement) ; 4. écho de nos propres messages ; 5. émetteur présent dans le groupe ;
--   6. décodage et validation du protocole ; 7. traitement selon le type.

local addonName, ns = ...

local Receiver = ns.NewModule("Receiver")
ns.Receiver = Receiver

local tostring = tostring

local ALLOWED_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
-- sources acceptées du réseau en 0.1.0 : HISTORY et MANUAL (sans expiration) arriveront avec le
-- mode de secours ; les accepter maintenant permettrait d'occuper la mémoire indéfiniment
local NETWORK_SOURCES = { LIVE = true, TEST = true }
local ROSTER_REFRESH_INTERVAL = 1

local lastRosterRefresh = -ROSTER_REFRESH_INTERVAL

local function OnNode(sender, message)
	if not ns.Config.Get("receiveEnabled") then
		ns.Diagnostics.Count("ignoredReceiveDisabled")
		return
	end
	if not NETWORK_SOURCES[message.source] then
		return ns.Diagnostics.Reject("source_not_supported", sender)
	end
	local peer = ns.GroupSync.GetPeerInfo(sender)
	if peer and peer.sharing == false then
		-- message parti avant son BYE, ou pair ayant arrêté le partage : ignoré
		ns.Diagnostics.Count("ignoredNotSharing")
		return
	end
	-- identifiant de carte fourni par un autre joueur : vérifié avant toute conversion C_Map
	if not ns.Coordinates.IsKnownMap(message.uiMapID) then
		return ns.Diagnostics.Reject("unknown_map", sender)
	end
	local marker, action = ns.MarkerManager.Upsert({
		sender = sender,
		id = message.id,
		source = message.source,
		kind = message.kind,
		state = message.state,
		uiMapID = message.uiMapID,
		x = message.x,
		y = message.y,
		accuracy = message.accuracy,
		age = message.age,
		resourceID = message.resourceID ~= 0 and message.resourceID or nil,
		name = message.name,
	})
	if not marker then
		ns.Diagnostics.Reject("marker_" .. tostring(action), sender)
		return
	end
	ns.Diagnostics.Log("RECV", "NODE %s de %s : %s (%s)", message.source, sender, tostring(message.name), action)
	ns.Fire("PGR_MARKERS_CHANGED")
end

local function OnRemove(sender, message)
	local touched = ns.MarkerManager.Remove(sender, message.id, false)
		or ns.MarkerManager.Remove(sender, message.id, true)
	if touched then
		ns.Fire("PGR_MARKERS_CHANGED")
	end
end

local HANDLERS = {
	H = function(sender, message) ns.GroupSync.OnHello(sender, message) end,
	h = function(sender, message) ns.GroupSync.OnHello(sender, message) end,
	B = function(sender) ns.GroupSync.OnBye(sender) end,
	P = function(sender, message) ns.GroupSync.OnPing(sender, message) end,
	p = function(sender, message) ns.GroupSync.OnPong(sender, message) end,
	N = OnNode,
	X = OnRemove,
}

local function IsVerifiedMember(fullName)
	if ns.GroupSync.IsGroupMember(fullName) then
		return true
	end
	-- la composition peut avoir changé avant GROUP_ROSTER_UPDATE : une relecture, limitée en fréquence
	local now = ns.Now()
	if now - lastRosterRefresh >= ROSTER_REFRESH_INTERVAL then
		lastRosterRefresh = now
		ns.GroupSync.RebuildRoster()
		return ns.GroupSync.IsGroupMember(fullName)
	end
	return false
end

--- Traite un message d'addon. Exposé pour les tests de simulation.
function Receiver.HandleAddonMessage(prefix, text, channel, sender)
	if ns.IsSecret(prefix) or prefix ~= ns.PREFIX then
		return
	end
	if not ns.Config.Get("enabled") then
		return
	end
	if ns.AnySecret(text, channel, sender) then
		return ns.Diagnostics.Reject("secret")
	end
	if not ALLOWED_CHANNELS[channel] then
		return ns.Diagnostics.Reject("channel", channel)
	end
	local fullName = ns.NormalizeName(sender)
	if not fullName then
		return ns.Diagnostics.Reject("sender")
	end
	if fullName == ns.GetPlayerFullName() then
		ns.Diagnostics.Count("echoes")
		return
	end
	if not IsVerifiedMember(fullName) then
		-- émetteur brut ajouté quand il diffère de l'identité comparée : sert à vérifier le format des noms en jeu
		return ns.Diagnostics.Reject("not_in_group", fullName == sender and fullName or (fullName .. " <- " .. sender))
	end
	local message, reason = ns.Protocol.Decode(text)
	if not message then
		if reason == "version_newer" or reason == "version_older" then
			ns.GroupSync.OnVersionMismatch(fullName, reason)
		end
		return ns.Diagnostics.Reject(reason, fullName)
	end
	ns.Diagnostics.Count("received")
	ns.GroupSync.OnPeerMessage(fullName, message)
	local handler = HANDLERS[message.type]
	if handler then
		handler(fullName, message, channel)
	end
end

ns.RegisterEvent("CHAT_MSG_ADDON", "Receiver", function(_, prefix, text, channel, sender)
	Receiver.HandleAddonMessage(prefix, text, channel, sender)
end)

-- Enregistrement du préfixe : obligatoire pour recevoir CHAT_MSG_ADDON ; perdu à chaque /reload.
local function RegisterPrefix()
	if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then
		ns.Diagnostics.RecordError("Receiver", "C_ChatInfo.RegisterAddonMessagePrefix absent")
		return
	end
	local result = C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
	-- 0 = Success, 1 = DuplicatePrefix (déjà inscrit) ; les anciens clients renvoient un booléen
	local ok = result == true or result == 0 or result == 1 or result == nil
	Receiver.prefixResult = result
	if ok then
		ns.Diagnostics.Log("CORE", "préfixe %s inscrit (résultat %s)", ns.PREFIX, tostring(result))
	else
		ns.Diagnostics.RecordError("Receiver", "inscription du préfixe refusée : " .. tostring(result))
		ns.Print(ns.T("PREFIX_REFUSED", ns.PREFIX, tostring(result)))
	end
end

RegisterPrefix()
