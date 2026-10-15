-- PartyGatherRadar - Core/Init.lua
-- Espace de noms commun, constantes et utilitaires sans dépendance envers les autres modules.
-- Premier fichier chargé par le TOC : tous les autres modules s'appuient sur `ns`.

local addonName, ns = ...

ns.ADDON_NAME = addonName or "PartyGatherRadar"
ns.VERSION = "0.1.0"
ns.PREFIX = "PGRadar"            -- préfixe des messages d'addon (16 caractères maximum)
ns.TARGET_INTERFACE = 16001       -- interface de la bêta WoW Forever ciblée
ns.TARGET_BUILD = "1.60.1"

ns.L = ns.L or {}                 -- rempli par Localization/*.lua
ns.modules = ns.modules or {}

local type, select, tostring, pairs = type, select, tostring, pairs
local format, floor, byte, sub = string.format, math.floor, string.byte, string.sub

---------------------------------------------------------------------------
-- Horloge
---------------------------------------------------------------------------

--- Temps monotone en secondes. Les tests hors jeu remplacent cette fonction.
function ns.Now()
	if GetTime then
		return GetTime()
	end
	return os.clock()
end

---------------------------------------------------------------------------
-- Valeurs secrètes (client moderne : issecretvalue peut être absent)
---------------------------------------------------------------------------

--- Vrai si la valeur est une valeur secrète que le code d'addon ne doit ni comparer ni calculer.
function ns.IsSecret(value)
	local check = issecretvalue
	if check == nil then
		return false
	end
	return check(value) and true or false
end

--- Vrai si au moins un des arguments est secret.
function ns.AnySecret(...)
	for i = 1, select("#", ...) do
		if ns.IsSecret((select(i, ...))) then
			return true
		end
	end
	return false
end

--- Lecture d'une variable de configuration du client (C_CVar sur le client moderne).
function ns.GetCVar(name)
	if C_CVar and C_CVar.GetCVar then
		return C_CVar.GetCVar(name)
	end
	if GetCVar then
		return GetCVar(name)
	end
	return nil
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------

--- Déclare un module. Un module désactivé (erreurs répétées) n'est plus appelé par le répartiteur d'événements.
function ns.NewModule(name)
	local module = ns.modules[name]
	if not module then
		module = { name = name, enabled = true, errors = 0 }
		ns.modules[name] = module
	end
	return module
end

function ns.IsModuleEnabled(name)
	local module = ns.modules[name]
	return module == nil or module.enabled
end

---------------------------------------------------------------------------
-- Affichage dans la discussion
---------------------------------------------------------------------------

local CHAT_PREFIX = "|cff33ff99PartyGatherRadar|r : "

function ns.Print(message, ...)
	if select("#", ...) > 0 then
		message = format(message, ...)
	end
	local frame = DEFAULT_CHAT_FRAME
	if frame and frame.AddMessage then
		frame:AddMessage(CHAT_PREFIX .. tostring(message))
	elseif print then
		print(CHAT_PREFIX .. tostring(message))
	end
end

--- Traduction : renvoie la chaîne localisée, formatée si des arguments sont fournis.
function ns.T(key, ...)
	local text = ns.L[key] or key
	if select("#", ...) > 0 then
		return format(text, ...)
	end
	return text
end

---------------------------------------------------------------------------
-- Utilitaires de tables et de chaînes
---------------------------------------------------------------------------

function ns.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = ns.DeepCopy(v)
	end
	return copy
end

--- Complète `target` avec les clés absentes de `defaults`, sans écraser les valeurs existantes du bon type.
function ns.MergeDefaults(target, defaults)
	for k, v in pairs(defaults) do
		local current = target[k]
		if current == nil or type(current) ~= type(v) then
			target[k] = ns.DeepCopy(v)
		elseif type(v) == "table" then
			ns.MergeDefaults(current, v)
		end
	end
	return target
end

function ns.Clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	elseif value > maxValue then
		return maxValue
	end
	return value
end

function ns.Round(value, decimals)
	local factor = 10 ^ (decimals or 0)
	return floor(value * factor + 0.5) / factor
end

function ns.Wipe(t)
	for k in pairs(t) do
		t[k] = nil
	end
	return t
end

--- Tronque une chaîne UTF-8 à `maxBytes` octets sans couper un caractère multioctet.
function ns.Utf8Truncate(text, maxBytes)
	if #text <= maxBytes then
		return text
	end
	local cut = maxBytes
	-- recule tant que l'octet suivant la coupure est un octet de continuation (10xxxxxx)
	while cut > 0 do
		local nextByte = byte(text, cut + 1)
		if not nextByte or nextByte < 0x80 or nextByte >= 0xC0 then
			break
		end
		cut = cut - 1
	end
	return sub(text, 1, cut)
end

---------------------------------------------------------------------------
-- Identité des joueurs
---------------------------------------------------------------------------

local function PlayerRealm()
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	if ns.IsSecret(realm) or realm == nil or realm == "" then
		return nil
	end
	return realm
end

--- Complète un nom en "Nom-Royaume" (format utilisé par CHAT_MSG_ADDON). Renvoie nil si le nom est inexploitable.
function ns.NormalizeName(name)
	if ns.IsSecret(name) or type(name) ~= "string" or name == "" then
		return nil
	end
	if name:find("-", 1, true) then
		return name
	end
	local realm = PlayerRealm()
	if realm then
		return name .. "-" .. realm
	end
	return name
end

--- Nom complet d'une unité ("Nom-Royaume") ou nil si indisponible ou secret.
function ns.UnitFullNameSafe(unit)
	if not UnitFullName then
		return nil
	end
	local name, realm = UnitFullName(unit)
	-- valeurs secrètes testées AVANT toute comparaison (comparer un secret lève une erreur)
	if ns.AnySecret(name, realm) or name == nil or name == "" then
		return nil
	end
	if realm == nil or realm == "" then
		realm = PlayerRealm()
	end
	if realm then
		return name .. "-" .. realm
	end
	return name
end

function ns.GetPlayerFullName()
	if ns.playerFullName then
		return ns.playerFullName
	end
	local fullName = ns.UnitFullNameSafe("player")
	-- avant PLAYER_LOGIN le royaume peut manquer : ne mettre en cache qu'un nom complet "Nom-Royaume"
	if fullName and fullName:find("-", 1, true) then
		ns.playerFullName = fullName
	end
	return fullName
end

--- Nom sans royaume, pour l'affichage.
function ns.ShortName(fullName)
	if type(fullName) ~= "string" then
		return "?"
	end
	return fullName:match("^([^%-]+)") or fullName
end
