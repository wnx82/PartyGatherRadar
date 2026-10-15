-- PartyGatherRadar - Communication/Protocol.lua
-- Format des messages d'addon (préfixe PGRadar). Module PUR : aucune API du jeu, testable hors jeu.
--
-- Format : champs séparés par ";" ; le premier champ est toujours la version du protocole,
-- le second le type de message. Taille maximale : 255 octets (limite Blizzard).
--
--   HELLO        <v>;H;<versionAddon>;<protoMin>;<capacités>      (réponse demandée)
--   HELLO_REPLY  <v>;h;<versionAddon>;<protoMin>;<capacités>      (réponse, sans nouvelle demande)
--   BYE          <v>;B                                            (arrêt du partage)
--   PING         <v>;P;<nonce>
--   PONG         <v>;p;<nonce>
--   NODE         <v>;N;<id>;<source>;<type>;<état>;<uiMapID>;<x>;<y>;<précision>;<âge>;<resID>;<nom>
--   REMOVE       <v>;X;<id>;<raison>
--
-- La disposition des trois premiers champs de HELLO est figée pour toutes les versions futures :
-- elle permet de détecter une incompatibilité sans comprendre le reste du message.

local addonName, ns = ...

local Protocol = {}
ns.Protocol = Protocol

local type, tostring, tonumber, floor = type, tostring, tonumber, math.floor
local find, sub, gsub, match, format, concat = string.find, string.sub, string.gsub, string.match, string.format,
	table.concat

Protocol.VERSION = 1
Protocol.MIN_COMPATIBLE = 1
Protocol.MAX_BYTES = 255
Protocol.SEP = ";"
Protocol.MAX_NAME_BYTES = 48
Protocol.COORD_SCALE = 100000 -- coordonnées de carte transmises en entiers 0..100000 (5 décimales)

Protocol.TYPE = {
	HELLO = "H",
	HELLO_REPLY = "h",
	BYE = "B",
	PING = "P",
	PONG = "p",
	NODE = "N",
	REMOVE = "X",
}

-- codes transmis -> valeurs internes
Protocol.SOURCES = { L = "LIVE", H = "HISTORY", M = "MANUAL", T = "TEST" }
Protocol.KINDS = { H = "HERB", O = "ORE", T = "TEST", X = "OTHER" }
Protocol.STATES = { D = "DETECTED", U = "UPDATED", I = "UNCERTAIN", G = "GONE" }
Protocol.REMOVE_REASONS = { G = "GATHERED", M = "MANUAL", E = "EXPIRED" }

-- capacités annoncées dans HELLO (champ de bits)
Protocol.CAPS = {
	SHARE = 1,          -- le client envoie ses informations
	RECEIVE = 2,        -- le client affiche les informations reçues
	HERB_TRACKING = 4,  -- Découverte d'herbes disponible
	ORE_TRACKING = 8,   -- Découverte de gisements disponible
	MINIMAP_PROBE = 16, -- sondage officiel de la minicarte disponible (expérimental)
}

local function Reverse(map)
	local reversed = {}
	for code, value in pairs(map) do
		reversed[value] = code
	end
	return reversed
end

local SOURCE_CODES = Reverse(Protocol.SOURCES)
local KIND_CODES = Reverse(Protocol.KINDS)
local STATE_CODES = Reverse(Protocol.STATES)
local REMOVE_CODES = Reverse(Protocol.REMOVE_REASONS)

-- nombre exact de champs (version et type compris) pour la version courante
local FIELD_COUNT = { H = 5, h = 5, B = 2, P = 3, p = 3, N = 13, X = 4 }

---------------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------------

--- Découpe `text` sur `sep` en conservant les champs vides. Renvoie nil si plus de `maxFields` champs.
function Protocol.Split(text, sep, maxFields)
	local fields, count, start = {}, 0, 1
	while true do
		count = count + 1
		if count > maxFields then
			return nil
		end
		local position = find(text, sep, start, true)
		if not position then
			fields[count] = sub(text, start)
			return fields, count
		end
		fields[count] = sub(text, start, position - 1)
		start = position + 1
	end
end

--- Entier positif strict (chiffres uniquement, longueur bornée) ou nil.
local function ParseUInt(text, maxDigits)
	if type(text) ~= "string" or #text == 0 or #text > maxDigits or not match(text, "^%d+$") then
		return nil
	end
	return tonumber(text)
end
Protocol.ParseUInt = ParseUInt

local function IsToken(text, maxLength)
	return type(text) == "string" and #text >= 1 and #text <= maxLength and match(text, "^[%w]+$") ~= nil
end

local function IsVersionString(text)
	return type(text) == "string" and #text >= 1 and #text <= 16 and match(text, "^[%w%.%-%+]+$") ~= nil
end

local function Utf8Truncate(text, maxBytes)
	if ns.Utf8Truncate then
		return ns.Utf8Truncate(text, maxBytes)
	end
	return sub(text, 1, maxBytes)
end

--- Nettoie un nom de ressource : supprime séparateurs, caractères de contrôle et "|" (codes d'échappement
--- WoW : couleurs, textures, liens), puis tronque à MAX_NAME_BYTES octets UTF-8.
function Protocol.SanitizeName(name)
	if type(name) ~= "string" then
		return ""
	end
	name = gsub(name, "[%c;|]", "")
	name = gsub(name, "^%s+", "")
	name = gsub(name, "%s+$", "")
	return Utf8Truncate(name, Protocol.MAX_NAME_BYTES)
end

local function EncodeCoord(value)
	return tostring(floor(value * Protocol.COORD_SCALE + 0.5))
end

local function Finish(fields)
	local text = concat(fields, Protocol.SEP)
	if #text > Protocol.MAX_BYTES then
		return nil, "too_long"
	end
	return text
end

---------------------------------------------------------------------------
-- Encodage
---------------------------------------------------------------------------

--- info = { addonVersion, minProto, caps }
function Protocol.EncodeHello(info, isReply)
	if not IsVersionString(info.addonVersion) then
		return nil, "bad_version"
	end
	local caps = info.caps or 0
	if type(caps) ~= "number" or caps < 0 or caps > 65535 or floor(caps) ~= caps then
		return nil, "bad_caps"
	end
	return Finish({
		tostring(Protocol.VERSION),
		isReply and Protocol.TYPE.HELLO_REPLY or Protocol.TYPE.HELLO,
		info.addonVersion,
		tostring(info.minProto or Protocol.MIN_COMPATIBLE),
		tostring(caps),
	})
end

function Protocol.EncodeBye()
	return Finish({ tostring(Protocol.VERSION), Protocol.TYPE.BYE })
end

function Protocol.EncodePing(nonce, isPong)
	if not IsToken(nonce, 8) then
		return nil, "bad_nonce"
	end
	return Finish({ tostring(Protocol.VERSION), isPong and Protocol.TYPE.PONG or Protocol.TYPE.PING, nonce })
end

--- node = { id, source, kind, state, uiMapID, x, y, accuracy, age, resourceID, name }
function Protocol.EncodeNode(node)
	if not IsToken(node.id, 12) then
		return nil, "bad_id"
	end
	local source, kind, state = SOURCE_CODES[node.source], KIND_CODES[node.kind], STATE_CODES[node.state]
	if not (source and kind and state) then
		return nil, "bad_enum"
	end
	local mapID = node.uiMapID
	if type(mapID) ~= "number" or mapID <= 0 or mapID >= 10000000 or floor(mapID) ~= mapID then
		return nil, "bad_map"
	end
	local x, y = node.x, node.y
	if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then
		return nil, "bad_coord"
	end
	local accuracy = floor((node.accuracy or 0) + 0.5)
	local age = floor((node.age or 0) + 0.5)
	local resourceID = node.resourceID or 0
	if accuracy < 0 or accuracy > 999 or age < 0 or age > 99999
		or type(resourceID) ~= "number" or resourceID < 0 or resourceID > 99999999 or floor(resourceID) ~= resourceID then
		return nil, "bad_number"
	end
	return Finish({
		tostring(Protocol.VERSION), Protocol.TYPE.NODE, node.id, source, kind, state, tostring(mapID),
		EncodeCoord(x), EncodeCoord(y), tostring(accuracy), tostring(age), tostring(resourceID),
		Protocol.SanitizeName(node.name),
	})
end

function Protocol.EncodeRemove(id, reason)
	local code = REMOVE_CODES[reason]
	if not IsToken(id, 12) or not code then
		return nil, "bad_remove"
	end
	return Finish({ tostring(Protocol.VERSION), Protocol.TYPE.REMOVE, id, code })
end

---------------------------------------------------------------------------
-- Décodage et validation stricte
---------------------------------------------------------------------------

local function DecodeHello(fields, message)
	local addonVersion, minProto, caps = fields[3], ParseUInt(fields[4], 4), ParseUInt(fields[5], 5)
	if not IsVersionString(addonVersion) or not minProto or not caps or caps > 65535 then
		return nil, "bad_hello"
	end
	message.addonVersion, message.minProto, message.caps = addonVersion, minProto, caps
	message.wantsReply = fields[2] == Protocol.TYPE.HELLO
	return message
end

local function DecodePing(fields, message)
	if not IsToken(fields[3], 8) then
		return nil, "bad_nonce"
	end
	message.nonce = fields[3]
	return message
end

local function DecodeNode(fields, message)
	local id = fields[3]
	local source, kind, state = Protocol.SOURCES[fields[4]], Protocol.KINDS[fields[5]], Protocol.STATES[fields[6]]
	local mapID = ParseUInt(fields[7], 7)
	local x, y = ParseUInt(fields[8], 6), ParseUInt(fields[9], 6)
	local accuracy, age, resourceID = ParseUInt(fields[10], 3), ParseUInt(fields[11], 5), ParseUInt(fields[12], 8)
	if not IsToken(id, 12) then
		return nil, "bad_id"
	end
	if not (source and kind and state) then
		return nil, "bad_enum"
	end
	if not mapID or mapID == 0 then
		return nil, "bad_map"
	end
	if not x or not y or x > Protocol.COORD_SCALE or y > Protocol.COORD_SCALE then
		return nil, "bad_coord"
	end
	if not accuracy or not age or not resourceID then
		return nil, "bad_number"
	end
	-- incohérences : un marqueur TEST doit être de type TEST et inversement
	if (source == "TEST") ~= (kind == "TEST") then
		return nil, "test_mismatch"
	end
	local name = fields[13]
	if Protocol.SanitizeName(name) ~= name then
		return nil, "bad_name"
	end
	message.id, message.source, message.kind, message.state = id, source, kind, state
	message.uiMapID = mapID
	message.x, message.y = x / Protocol.COORD_SCALE, y / Protocol.COORD_SCALE
	message.accuracy, message.age, message.resourceID = accuracy, age, resourceID
	message.name = name
	return message
end

local function DecodeRemove(fields, message)
	local reason = Protocol.REMOVE_REASONS[fields[4]]
	if not IsToken(fields[3], 12) or not reason then
		return nil, "bad_remove"
	end
	message.id, message.reason = fields[3], reason
	return message
end

local DECODERS = {
	H = DecodeHello, h = DecodeHello,
	B = function(_, message) return message end,
	P = DecodePing, p = DecodePing,
	N = DecodeNode,
	X = DecodeRemove,
}

--- Décode un message reçu. Renvoie une table { proto, type, ... } ou nil et un code de rejet :
--- not_string, too_long, malformed, bad_version, version_newer, version_older, unknown_type,
--- field_count, ou un code de validation propre au type.
function Protocol.Decode(text)
	if type(text) ~= "string" then
		return nil, "not_string"
	end
	if #text == 0 or #text > Protocol.MAX_BYTES then
		return nil, "too_long"
	end
	local fields, count = Protocol.Split(text, Protocol.SEP, 16)
	if not fields or count < 2 then
		return nil, "malformed"
	end
	local proto = ParseUInt(fields[1], 4)
	if not proto or proto == 0 then
		return nil, "bad_version"
	end
	local messageType = fields[2]
	local message = { proto = proto, type = messageType }

	-- HELLO reste lisible quelle que soit la version (disposition figée), pour signaler l'incompatibilité
	if messageType == Protocol.TYPE.HELLO or messageType == Protocol.TYPE.HELLO_REPLY then
		if count < 5 then
			return nil, "field_count"
		end
		if proto == Protocol.VERSION and count ~= FIELD_COUNT[messageType] then
			return nil, "field_count"
		end
		return DecodeHello(fields, message)
	end

	if proto > Protocol.VERSION then
		return nil, "version_newer"
	end
	if proto < Protocol.MIN_COMPATIBLE then
		return nil, "version_older"
	end
	local decoder = DECODERS[messageType]
	if not decoder then
		return nil, "unknown_type"
	end
	if count ~= FIELD_COUNT[messageType] then
		return nil, "field_count"
	end
	return decoder(fields, message)
end

--- Compatibilité avec un pair d'après son HELLO : vrai si chacun sait lire l'autre. Les messages
--- d'un pair portent sa version : au-delà de VERSION, Decode les refuse (version_newer).
function Protocol.IsCompatible(peerProto, peerMinProto)
	return type(peerProto) == "number" and type(peerMinProto) == "number"
		and peerProto >= Protocol.MIN_COMPATIBLE and peerProto <= Protocol.VERSION
		and Protocol.VERSION >= peerMinProto
end
