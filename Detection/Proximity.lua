-- PartyGatherRadar - Detection/Proximity.lua
-- Détection de proximité, sans souris : la cible d'interaction douce du jeu (unité "softinteract", celle de la
-- touche d'interaction) désigne l'objet le plus proche du joueur. Quand c'est une herbe ou un filon reconnu
-- (Detection/ResourceNames.lua), il est suivi et partagé comme une ressource survolée
-- (AutoDetect.ReportNearby), à la position du joueur : à ±5 m s'il est à portée d'interaction, sinon à ±15 m.
-- Le pistage n'est pas nécessaire : la cible douce voit l'objet lui-même.
--
-- Constaté (tiers) : des addons Forever publiés (ForeverLootSparkles, OneForAll, NaowhForever_QoL, RareScanner)
-- s'appuient sur cette cible pour les herbes, les filons et les coffres ; un objet du monde n'y est pas une unité
-- (UnitExists faux) mais a un GUID « GameObject-… » ; Forever lâche la cible au-delà d'environ 15 m.
-- Vérifié en jeu le 2026-11-09 (build 70862, deux clients) : GUID et nom des herbes lisibles, herbes partagées
-- sans survol ni pistage ; première vue à environ 4 à 13 m de la plante. Une herbe cueillie reste ciblée un
-- instant : AutoDetect l'ignore (AutoDetect.GATHERED_IGNORE_SECONDS).
--
-- La cible douce n'existe que si le jeu l'active (option « touche d'interaction », CVar SoftTargetInteract). Le
-- réglage « Détection de proximité » (/pgr near on) l'active, tout autour du joueur et au-delà de la portée
-- d'interaction. Les valeurs d'origine sont gardées dans PartyGatherRadarDB.proximityCVars et rétablies quand le
-- réglage est coupé (/pgr near off), sauf celles que le joueur ou un autre addon a changées entre-temps. La
-- portée n'est jamais réduite. Rien n'est changé en combat (appliqué à la fin du combat) ; un rétablissement
-- interrompu par un /reload ou une déconnexion est repris à l'entrée suivante dans le monde. La cible douce
-- n'est lue que si le réglage est actif, même quand le joueur l'a activée lui-même dans le jeu.
--
-- Jamais en combat ni pendant une restriction d'addons. Aucune touche n'est liée ; l'addon ne cible, ne déplace
-- ni ne récolte rien : il lit seulement la cible choisie par le jeu.

local addonName, ns = ...

local Proximity = ns.NewModule("Proximity")
ns.Proximity = Proximity

local ipairs, type, tonumber, pcall = ipairs, type, tonumber, pcall

-- distance maximale de la cible douce : portée demandée, et limite de Forever (environ 15 m, constat tiers ; en
-- jeu, premières vues à environ 4 à 13 m ; le journal note la distance parcourue jusqu'à la portée d'interaction)
Proximity.RANGE_YARDS = 15
Proximity.REACH_YARDS = 5      -- cible à portée d'interaction
Proximity.CHECK_INTERVAL = 0.5 -- secondes entre deux lectures, en plus de PLAYER_SOFT_INTERACT_CHANGED
-- même cible gardée : présence confirmée toutes les 5 s (le renvoi au groupe suit AutoDetect.RESEND_INTERVAL)
Proximity.REFRESH_INTERVAL = 5

local UNIT = "softinteract"

-- Réglages du jeu posés par la détection de proximité, dans cet ordre. atLeast : valeur minimale.
local WANTED = {
	{ name = "SoftTargetInteract", value = "3" },            -- cible douce toujours active (clavier et manette)
	{ name = "SoftTargetInteractArc", value = "2" },         -- tout autour du joueur
	{ name = "SoftTargetInteractOnlyInRange", value = "0" }, -- aussi au-delà de la portée d'interaction
	{ name = "SoftTargetInteractRange", value = tostring(Proximity.RANGE_YARDS), atLeast = true },
}
Proximity.WANTED = WANTED

local pending       -- "apply" ou "restore" : réglages à poser à la fin du combat
local lastGUID, lastReach, lastReportAt
local firstGUID, firstX, firstY, firstMapID -- première vue hors de portée de la cible courante (journal)
local namelessLogged = false

---------------------------------------------------------------------------
-- Réglages du jeu
---------------------------------------------------------------------------

local function InCombat()
	return InCombatLockdown and InCombatLockdown()
end

local function Readable(value)
	return not ns.IsSecret(value) and type(value) == "string"
end

--- Valeur à poser pour `entry`, la valeur actuelle étant `current`.
local function Wanted(entry, current)
	if entry.atLeast then
		local number, minimum = tonumber(current), tonumber(entry.value)
		if number and number >= minimum then
			return current
		end
	end
	return entry.value
end

--- Active la cible douce du jeu (valeurs d'origine gardées). Renvoie false si l'action est remise à la fin du
--- combat, sinon true et le nombre de réglages changés.
function Proximity.ApplyCVars()
	if InCombat() then
		pending = "apply"
		return false
	end
	pending = nil
	local saved = ns.db.proximityCVars
	if type(saved) ~= "table" then
		saved = {}
		ns.db.proximityCVars = saved
	end
	local changed = 0
	for _, entry in ipairs(WANTED) do
		local current = ns.GetCVar(entry.name)
		-- réglage inconnu de ce client : ignoré
		if Readable(current) then
			local wanted = Wanted(entry, current)
			if current ~= wanted then
				if saved[entry.name] == nil then
					saved[entry.name] = current
				end
				if ns.SetCVar(entry.name, wanted) then
					changed = changed + 1
				end
			end
		end
	end
	ns.Diagnostics.Log("DETECT", "proximité : cible douce du jeu activée (%d réglage(s) changé(s))", changed)
	return true, changed
end

--- Rétablit les valeurs d'origine encore égales à celles posées par l'addon. Renvoie false si l'action est
--- remise à la fin du combat, sinon true et le nombre de réglages rétablis.
function Proximity.RestoreCVars()
	if InCombat() then
		pending = "restore"
		return false
	end
	pending = nil
	local saved = ns.db.proximityCVars
	local restored = 0
	if type(saved) == "table" then
		for _, entry in ipairs(WANTED) do
			local original, current = saved[entry.name], ns.GetCVar(entry.name)
			if type(original) == "string" and Readable(current) and current == entry.value
				and ns.SetCVar(entry.name, original) then
				restored = restored + 1
			end
		end
	end
	ns.db.proximityCVars = nil
	ns.Diagnostics.Log("DETECT", "proximité : %d réglage(s) du jeu rétabli(s)", restored)
	return true, restored
end

--- Vrai si la cible douce du jeu est active au clavier (SoftTargetInteract 2 ou 3).
function Proximity.IsSoftTargetOn()
	local value = ns.GetCVar("SoftTargetInteract")
	return Readable(value) and (value == "2" or value == "3")
end

---------------------------------------------------------------------------
-- Lecture de la cible douce
---------------------------------------------------------------------------

local function SafeUnitCall(fn)
	if not fn then
		return nil
	end
	local ok, value = pcall(fn, UNIT)
	if not ok or ns.IsSecret(value) then
		return nil
	end
	return value
end

--- Cible douce s'il s'agit d'une herbe ou d'un filon : guid, nom, type, à portée — sinon nil.
local function ReadTarget()
	local guid = SafeUnitCall(UnitGUID)
	-- objet du monde : pas une unité (UnitExists faux), mais un GUID "GameObject-…" ; PNJ et joueurs exclus
	if type(guid) ~= "string" or guid:match("^([^%-]+)") ~= "GameObject" then
		return nil
	end
	local name = SafeUnitCall(UnitName)
	if type(name) ~= "string" or name == "" then
		if not namelessLogged then
			namelessLogged = true
			ns.Diagnostics.Log("DETECT", "proximité : objet ciblé sans nom lisible (%s)", guid)
		end
		return nil
	end
	local kind = ns.ResourceNames.Classify(name)
	if not kind then
		return nil -- coffre, boîte aux lettres, objet de quête… : jamais partagé
	end
	return guid, name, kind, SafeUnitCall(UnitIsInInteractRange) == true
end

--- Journal : distance parcourue par le joueur entre la première vue d'un objet hors de portée et l'arrivée à
--- portée d'interaction. C'est la distance de ciblage à REACH_YARDS près : de quoi vérifier la limite de 15 m en jeu.
local function NoteTargetDistance(guid, name, reach, mapID, x, y)
	if guid ~= firstGUID then
		firstGUID, firstX, firstY, firstMapID = guid, (not reach) and x or nil, y, mapID
		return
	end
	if reach and firstX and firstMapID == mapID then
		local width, height = ns.Coordinates.GetMapSizeYards(mapID)
		if width then
			local dx, dy = (x - firstX) * width, (y - firstY) * height
			ns.Diagnostics.Log("DETECT", "proximité : %s ciblé à environ %.0f m (±%d m) avant la portée d'interaction",
				name, math.sqrt(dx * dx + dy * dy), Proximity.REACH_YARDS)
		end
		firstX = nil
	end
end

--- Lit la cible douce et signale une herbe ou un filon nouvellement ciblé, devenu accessible, ou toujours ciblé
--- après REFRESH_INTERVAL secondes. Renvoie true si une ressource a été signalée.
function Proximity.Check(now)
	if not ns.Config.Get("enabled") or not ns.Config.Get("autoDetect") or not ns.Config.Get("proximityDetect") then
		lastGUID, lastReach = nil, nil
		return false
	end
	if InCombat() or ns.AutoDetect.IsAddOnRestricted() then
		return false
	end
	local guid, name, kind, reach = ReadTarget()
	if not guid then
		lastGUID, lastReach = nil, nil
		return false
	end
	if guid == lastGUID and (lastReach or not reach) and now - lastReportAt < Proximity.REFRESH_INTERVAL then
		return false
	end
	local mapID, x, y = ns.Coordinates.GetPlayerMapPosition()
	if not mapID then
		return false
	end
	local accuracy = reach and Proximity.REACH_YARDS or Proximity.RANGE_YARDS
	-- le GUID identifie l'objet : vu de deux côtés, il reste une seule ressource
	if not ns.AutoDetect.ReportNearby(name, kind, mapID, x, y, accuracy, now, guid) then
		return false
	end
	NoteTargetDistance(guid, name, reach, mapID, x, y)
	lastGUID, lastReach, lastReportAt = guid, reach, now
	return true
end

--- Résumé pour /pgr status : réglage, cible douce du jeu, ressources vues de près.
function Proximity.Describe()
	return ns.Config.Get("proximityDetect"), Proximity.IsSoftTargetOn(), ns.AutoDetect.stats.near
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

local function OnTick()
	if pending and not InCombat() then
		if pending == "apply" then
			Proximity.ApplyCVars()
		else
			Proximity.RestoreCVars()
		end
	end
	Proximity.Check(ns.Now())
end

ns.On("PGR_CONFIG_LOADED", "Proximity", function()
	ns.NewTicker(Proximity.CHECK_INTERVAL, "Proximity", OnTick)
	ns.RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", "Proximity", function()
		Proximity.Check(ns.Now())
	end)
end)

-- réglages du compte synchronisés par le serveur : ils peuvent arriver après PLAYER_LOGIN. Un rétablissement
-- remis à la fin d'un combat puis perdu (/reload, déconnexion) est repris : réglage coupé, valeurs gardées.
ns.RegisterEvent("PLAYER_ENTERING_WORLD", "Proximity", function()
	if not ns.db then
		return
	end
	if ns.Config.Get("proximityDetect") then
		Proximity.ApplyCVars()
	elseif type(ns.db.proximityCVars) == "table" then
		Proximity.RestoreCVars()
	end
end)

ns.On("PGR_SETTING_CHANGED", "Proximity", function(_, key, value)
	if key ~= "proximityDetect" then
		return
	end
	local done
	if value then
		done = Proximity.ApplyCVars()
	else
		done = Proximity.RestoreCVars()
	end
	if not done then
		ns.Print(ns.T("PROXIMITY_COMBAT"))
	elseif value then
		ns.Print(ns.T("PROXIMITY_ON"))
	else
		ns.Print(ns.T("PROXIMITY_OFF"))
	end
end)
