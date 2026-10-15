-- PartyGatherRadar - Communication/Sender.lua
-- File d'envoi des messages d'addon : choix du canal de groupe, limitation de fréquence,
-- regroupement des mises à jour, gestion des refus de l'API.
--
-- Rappels :
--   * un message accepté par C_ChatInfo.SendAddonMessage n'est PAS forcément reçu par tous ;
--   * aucun canal public n'est utilisé (seulement PARTY, RAID, INSTANCE_CHAT) ;
--   * limite Blizzard documentée : 10 messages par préfixe puis 1 par seconde (modifiable par le serveur).
--     Notre seau reste nettement en dessous.

local addonName, ns = ...

local Sender = ns.NewModule("Sender")
ns.Sender = Sender

local pcall, type, tostring, min = pcall, type, tostring, math.min

local QUEUE_MAX = 30
local BUCKET_CAPACITY = 5
local BUCKET_REFILL_PER_SECOND = 0.8
local TICK_INTERVAL = 0.2
local THROTTLE_BACKOFF = 2
local LOCKDOWN_BACKOFF = 10
local DEFAULT_TTL = 30 -- secondes avant abandon d'un message non envoyé

Sender.PRIORITY_HIGH = 1
Sender.PRIORITY_NORMAL = 2

-- valeurs de repli si Enum.SendAddonMessageResult est absent (documentation 12.x)
local RESULT_FALLBACK = {
	[0] = "Success", [1] = "InvalidPrefix", [2] = "InvalidMessage", [3] = "AddonMessageThrottle",
	[4] = "InvalidChatType", [5] = "NotInGroup", [6] = "TargetRequired", [7] = "InvalidChannel",
	[8] = "ChannelThrottle", [9] = "GeneralError", [10] = "NotInGuild", [11] = "AddOnMessageLockdown",
	[12] = "TargetOffline",
}

local queue = {}
local tokens = BUCKET_CAPACITY
local lastRefill
local pausedUntil = 0
local ticker

Sender.lastResult = nil -- { at, code, name, outcome, channel }

---------------------------------------------------------------------------
-- Canal
---------------------------------------------------------------------------

local function InGroup(category)
	if not IsInGroup then
		return false
	end
	return IsInGroup(category) and true or false
end

--- Canal de groupe à utiliser, ou nil (pas de groupe, ou canal désactivé dans les réglages).
function Sender.GetChannel()
	local home = LE_PARTY_CATEGORY_HOME
	local instance = LE_PARTY_CATEGORY_INSTANCE
	if InGroup(home) then
		if IsInRaid and IsInRaid(home) then
			-- sans l'option raid, le canal PARTY ne touche que le sous-groupe
			return ns.Config.Get("allowRaid") and "RAID" or "PARTY"
		end
		return "PARTY"
	end
	if instance and InGroup(instance) then
		return ns.Config.Get("allowInstanceChat") and "INSTANCE_CHAT" or nil
	end
	return nil
end

---------------------------------------------------------------------------
-- Résultats de l'API
---------------------------------------------------------------------------

local function ResultName(code)
	local enum = Enum and Enum.SendAddonMessageResult
	if type(enum) == "table" then
		for name, value in pairs(enum) do
			if value == code then
				return name
			end
		end
	end
	return RESULT_FALLBACK[code] or tostring(code)
end
Sender.ResultName = ResultName

--- Classe le retour de SendAddonMessage : "ok", "throttle", "lockdown", "nogroup", "refused".
function Sender.ClassifyResult(result)
	if result == nil or result == true or result == 0 then
		return "ok"
	end
	if result == false then
		return "refused"
	end
	local name = ResultName(result)
	if name == "AddonMessageThrottle" or name == "ChannelThrottle" then
		return "throttle"
	end
	if name == "AddOnMessageLockdown" then
		return "lockdown"
	end
	if name == "NotInGroup" then
		return "nogroup"
	end
	return "refused"
end

---------------------------------------------------------------------------
-- File d'attente
---------------------------------------------------------------------------

local function Refill(now)
	if lastRefill then
		tokens = min(BUCKET_CAPACITY, tokens + (now - lastRefill) * BUCKET_REFILL_PER_SECOND)
	end
	lastRefill = now
end

local function DropOne()
	-- abandonne d'abord le plus ancien message de priorité normale
	for i = 1, #queue do
		if queue[i].priority == Sender.PRIORITY_NORMAL then
			table.remove(queue, i)
			ns.Diagnostics.Count("dropped")
			return
		end
	end
	table.remove(queue, 1)
	ns.Diagnostics.Count("dropped")
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local Process

local function StartTicker()
	if not ticker then
		ticker = ns.NewTicker(TICK_INTERVAL, "Sender", Process)
	end
end

local function TrySend(entry, channel)
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, entry.text, channel)
	if not ok then
		return "refused", nil, tostring(result)
	end
	return Sender.ClassifyResult(result), result
end

Process = function()
	local now = ns.Now()
	Refill(now)
	if #queue == 0 then
		StopTicker()
		return
	end
	if now < pausedUntil then
		return
	end
	local channel = Sender.GetChannel()
	if not channel then
		-- plus de groupe : la file n'a plus de destinataire
		ns.Diagnostics.Count("dropped", #queue)
		ns.Wipe(queue)
		StopTicker()
		return
	end
	while #queue > 0 and tokens >= 1 do
		local entry = queue[1]
		if now > entry.expiresAt then
			table.remove(queue, 1)
			ns.Diagnostics.Count("dropped")
		else
			local outcome, code, errorText = TrySend(entry, channel)
			Sender.lastResult = {
				at = now, code = code, name = code ~= nil and ResultName(code) or errorText,
				outcome = outcome, channel = channel, label = entry.label,
			}
			if outcome == "ok" then
				tokens = tokens - 1
				table.remove(queue, 1)
				ns.Diagnostics.Count("sent")
				ns.Diagnostics.Log("SEND", "%s accepté (%s)", entry.label, channel)
			elseif outcome == "throttle" then
				ns.Diagnostics.Count("throttled")
				tokens = 0
				pausedUntil = now + THROTTLE_BACKOFF
				ns.Diagnostics.Log("SEND", "%s limité par le serveur, nouvel essai dans %d s", entry.label,
					THROTTLE_BACKOFF)
				return
			elseif outcome == "lockdown" then
				ns.Diagnostics.Count("lockdown")
				pausedUntil = now + LOCKDOWN_BACKOFF
				ns.Diagnostics.Log("SEND", "messagerie des addons verrouillée, pause de %d s", LOCKDOWN_BACKOFF)
				return
			else
				table.remove(queue, 1)
				ns.Diagnostics.Count("sendRefused")
				ns.Diagnostics.Log("SEND", "%s refusé : %s", entry.label, tostring(Sender.lastResult.name))
				if outcome == "nogroup" then
					ns.Wipe(queue)
					return
				end
			end
		end
	end
end

--- Ajoute un message à la file. opts = { priority, key (regroupement), ttl, label, force }.
--- `force` autorise l'envoi alors que l'addon vient d'être désactivé (BYE).
--- Renvoie false si l'envoi est impossible (addon désactivé, message invalide, pas de groupe).
function Sender.Enqueue(text, opts)
	opts = opts or {}
	if not opts.force and not ns.Config.Get("enabled") then
		return false, "disabled"
	end
	if type(text) ~= "string" or #text == 0 or #text > ns.Protocol.MAX_BYTES then
		return false, "invalid"
	end
	if not Sender.GetChannel() then
		return false, "nogroup"
	end
	local now = ns.Now()
	local entry = {
		text = text,
		priority = opts.priority or Sender.PRIORITY_NORMAL,
		key = opts.key,
		label = opts.label or "message",
		expiresAt = now + (opts.ttl or DEFAULT_TTL),
	}
	if entry.key then
		for i = 1, #queue do
			if queue[i].key == entry.key then
				queue[i] = entry -- remplace la version en attente par la plus récente
				StartTicker()
				return true
			end
		end
	end
	if #queue >= QUEUE_MAX then
		DropOne()
	end
	local position = #queue + 1
	if entry.priority == Sender.PRIORITY_HIGH then
		position = 1
		while position <= #queue and queue[position].priority == Sender.PRIORITY_HIGH do
			position = position + 1
		end
	end
	table.insert(queue, position, entry)
	StartTicker()
	Process()
	return true
end

function Sender.GetQueueLength()
	return #queue
end

function Sender.IsPaused()
	return ns.Now() < pausedUntil
end

--- Vide la file (changement de groupe, désactivation).
function Sender.Clear()
	ns.Wipe(queue)
	StopTicker()
end

---------------------------------------------------------------------------
-- Messages typés
---------------------------------------------------------------------------

local function EnqueueEncoded(text, err, opts)
	if not text then
		ns.Diagnostics.Log("SEND", "encodage impossible (%s) : %s", opts.label or "?", tostring(err))
		return false, err
	end
	return Sender.Enqueue(text, opts)
end

function Sender.SendHello(isReply)
	local text, err = ns.Protocol.EncodeHello({
		addonVersion = ns.VERSION,
		minProto = ns.Protocol.MIN_COMPATIBLE,
		caps = ns.GroupSync and ns.GroupSync.GetLocalCaps() or 0,
	}, isReply)
	return EnqueueEncoded(text, err, {
		priority = Sender.PRIORITY_HIGH, key = isReply and "hello-reply" or "hello", ttl = 15,
		label = isReply and "HELLO(réponse)" or "HELLO",
	})
end

--- Abandonne les messages en attente d'une priorité donnée (BYE : plus aucun marqueur après lui).
function Sender.DropPriority(priority)
	for i = #queue, 1, -1 do
		if queue[i].priority == priority then
			table.remove(queue, i)
			ns.Diagnostics.Count("dropped")
		end
	end
end

function Sender.SendBye()
	Sender.DropPriority(Sender.PRIORITY_NORMAL)
	local text, err = ns.Protocol.EncodeBye()
	return EnqueueEncoded(text, err, {
		priority = Sender.PRIORITY_HIGH, key = "bye", ttl = 10, label = "BYE", force = true,
	})
end

--- PING (isPong faux) ou PONG. Un seul PONG en attente par demandeur (`target`).
function Sender.SendPing(nonce, isPong, target)
	local text, err = ns.Protocol.EncodePing(nonce, isPong)
	return EnqueueEncoded(text, err, {
		priority = Sender.PRIORITY_HIGH, key = isPong and ("pong:" .. tostring(target or nonce)) or ("ping:" .. tostring(nonce)),
		ttl = 10,
		label = isPong and "PONG" or "PING",
	})
end

--- Diffuse un marqueur. Les sources réelles exigent le partage activé ; TEST seulement pour /pgr test.
function Sender.SendNode(node)
	if node.source ~= "TEST" and not ns.Config.Get("shareEnabled") then
		return false, "sharing_disabled"
	end
	local text, err = ns.Protocol.EncodeNode(node)
	return EnqueueEncoded(text, err, {
		priority = Sender.PRIORITY_NORMAL, key = "node:" .. tostring(node.id), ttl = 20, label = "NODE " .. node.source,
	})
end

function Sender.SendRemove(id, reason)
	local text, err = ns.Protocol.EncodeRemove(id, reason)
	return EnqueueEncoded(text, err, {
		priority = Sender.PRIORITY_NORMAL, key = "node:" .. tostring(id), ttl = 20, label = "REMOVE",
	})
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

-- Levée anticipée de la pause quand la restriction "Chat" (type 5) redevient inactive (état 0).
ns.RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "Sender", function(_, restrictionType, state)
	if ns.AnySecret(restrictionType, state) then
		return
	end
	local chatType = Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Chat or 5
	local inactive = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
	if restrictionType == chatType and state == inactive and pausedUntil > 0 then
		pausedUntil = 0
		ns.Diagnostics.Log("SEND", "restriction de messagerie levée")
		if #queue > 0 then
			StartTicker()
		end
	end
end)
