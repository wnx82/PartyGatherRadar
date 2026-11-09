-- PartyGatherRadar - UI/ChatFilter.lua
-- Masque le message système « Aucun joueur nommé '…' ne joue actuellement » quand il vise un membre du groupe
-- connecté (réglage hideNotFound, /pgr quiet on|off, activé par défaut). Ce message vient d'un AUTRE addon :
-- PartyGatherRadar n'envoie jamais de chuchotement (PARTY, RAID ou INSTANCE_CHAT seulement). Sur Forever, des
-- addons chuchotent les membres du groupe sous la forme « Prénom-Nom », que le serveur lit comme « Prénom » sur le
-- royaume « Nom » : il répond que ce joueur n'existe pas, à chaque essai. Constaté le 2026-11-09 avec ForeverGuide
-- 1.39.5 (préfixe FGD), qui inondait la discussion.
--
-- Le membre visé est dans le groupe et connecté : le message est faux. Seul ce message est masqué ; un joueur hors
-- du groupe, ou un membre déconnecté, garde le sien. Les envois de l'autre addon continuent : seul l'affichage
-- change. Filtre officiel de la discussion (ChatFrameUtil.AddMessageEventFilter), sans lecture d'autres addons.

local addonName, ns = ...

local ChatFilter = ns.NewModule("ChatFilter")
ns.ChatFilter = ChatFilter

local EVENT = "CHAT_MSG_SYSTEM"
local MAX_LOGGED = 5 -- noms journalisés par session, au plus

ChatFilter.hidden = 0 -- messages masqués depuis le chargement

local pattern  -- motif tiré de ERR_CHAT_PLAYER_NOT_FOUND_S ; nil : format inconnu, rien n'est masqué
local registered = false
local logged, loggedCount = {}, 0

--- Motif Lua d'un format de message du jeu dont "%s" (ou "%1$s") est le nom du joueur, ou nil.
function ChatFilter.BuildPattern(format)
	if ns.IsSecret(format) or type(format) ~= "string" then
		return nil
	end
	local escaped = format:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	local result, count = escaped:gsub("%%%%1%%%$s", "(.+)", 1)
	if count == 0 then
		result, count = escaped:gsub("%%%%s", "(.+)", 1)
	end
	if count == 0 then
		return nil
	end
	return "^" .. result .. "$"
end

--- Prénom : premier mot d'un nom (« Prénom Nom », « Prénom-Nom » ou « Prénom-Royaume »).
local function FirstName(name)
	return name:match("^([^%s%-]+)")
end

--- Identité du membre du groupe connecté désigné par `target`, ou nil.
local function OnlineMember(target)
	local first = FirstName(target)
	if not first then
		return nil
	end
	local lower, found = first:lower(), nil
	ns.GroupSync.ForEachMember(function(name, unit)
		local memberFirst = not found and FirstName(name)
		if memberFirst and (memberFirst == first or memberFirst:lower() == lower) then
			local ok, connected = pcall(UnitIsConnected, unit)
			if ok and not ns.IsSecret(connected) and connected == true then
				found = name
			end
		end
	end)
	return found
end

--- Vrai si le message système doit être masqué.
function ChatFilter.ShouldHide(message)
	if not pattern or not ns.Config.Get("enabled") or not ns.Config.Get("hideNotFound") then
		return false
	end
	if ns.IsSecret(message) or type(message) ~= "string" then
		return false
	end
	local target = message:match(pattern)
	if not target or not OnlineMember(target) then
		return false
	end
	ChatFilter.hidden = ChatFilter.hidden + 1
	ns.Diagnostics.Count("hiddenNotFound")
	if not logged[target] and loggedCount < MAX_LOGGED then
		logged[target], loggedCount = true, loggedCount + 1
		ns.Diagnostics.Log("COMM", "message « joueur introuvable » masqué : %s est dans le groupe et connecté "
			.. "(chuchotement d'un autre addon)", target)
	end
	return true
end

local function Filter(_, _, message)
	local ok, hide = ns.SafeCall("ChatFilter", ChatFilter.ShouldHide, message)
	return ok and hide == true
end

ns.On("PGR_CONFIG_LOADED", "ChatFilter", function()
	if registered then
		return
	end
	pattern = ChatFilter.BuildPattern(ERR_CHAT_PLAYER_NOT_FOUND_S)
	local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if not pattern or not add then
		ns.Diagnostics.Log("CORE", "filtre « joueur introuvable » indisponible (format ou API absents)")
		return
	end
	add(EVENT, Filter)
	registered = true
end)
