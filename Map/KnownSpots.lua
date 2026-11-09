-- PartyGatherRadar - Map/KnownSpots.lua
-- Emplacements connus : chaque herbe ou filon détecté (balayage, survol, proximité), reçu du groupe ou récolté
-- est mémorisé par carte, d'une session à l'autre (PartyGatherRadarDB.knownSpots). Les herbes et les filons
-- repoussent aux mêmes endroits : la minicarte montre ces emplacements comme positions historiques (marqueur
-- discret), sans que personne ait à survoler la minicarte. Leur présence actuelle n'est jamais affirmée :
-- seule une détection récente l'est (Map/MinimapOverlay.lua masque un emplacement près d'une détection).
--
-- Module sans cadre graphique, testable hors jeu. Un emplacement par ressource physique : même type à moins de
-- MERGE_YARDS, ou de la somme des deux précisions (au plus MAX_MERGE_YARDS : une herbe vue à ±15 m de deux côtés
-- opposés), la position la plus précise est gardée. Bornes : 300 emplacements par carte, 3000 en tout ; le moins
-- récemment vu part en premier, ceux reçus du groupe avant ceux vus par ce joueur. Une ressource récoltée
-- (MarkGathered) n'est pas affichée pendant GATHERED_HIDE_SECONDS : elle vient de disparaître.
--
-- Format gardé (clés courtes, SavedVariables compactes) :
--   [mapID] = { { x, y (coordonnées de carte), k = "HERB"|"ORE", n = nom, a = précision (m),
--                 t = dernière vue (heure murale, time()), c = nombre de vues, m = vu par ce joueur,
--                 g = récoltée (heure murale), levée par une nouvelle vue } }

local addonName, ns = ...

local KnownSpots = ns.NewModule("KnownSpots")
ns.KnownSpots = KnownSpots

local type, pairs, ipairs, sqrt, floor, min, max = type, pairs, ipairs, math.sqrt, math.floor, math.min, math.max

KnownSpots.MERGE_YARDS = 15       -- même type à moins de 15 m : même emplacement
KnownSpots.MAX_MERGE_YARDS = 30   -- au plus, quand les deux positions sont imprécises
KnownSpots.GATHERED_HIDE_SECONDS = 300 -- emplacement d'une ressource récoltée masqué 5 min
KnownSpots.MAX_PER_MAP = 300
KnownSpots.MAX_TOTAL = 3000
KnownSpots.DEFAULT_ACCURACY = 15  -- précision inconnue (message ancien ou incomplet)
KnownSpots.MOVE_NOTIFY_YARDS = 2  -- un emplacement déplacé de plus de 2 m redessine l'affichage
KnownSpots.MAX_COUNT = 9999
KnownSpots.version = 0            -- incrémenté à chaque modification visible (rafraîchissement de l'affichage)

local VALID_KINDS = { HERB = true, ORE = true }
local MAX_NAME_BYTES = 60

local storage -- PartyGatherRadarDB.knownSpots
local total = 0

local function Touch()
	KnownSpots.version = KnownSpots.version + 1
	ns.Fire("PGR_SPOTS_CHANGED")
end

local function IsCoord(value)
	return type(value) == "number" and value == value and value >= 0 and value <= 1
end

local function IsPositiveNumber(value)
	return type(value) == "number" and value == value and value > 0 and value < math.huge
end

local function Distance(width, height, x1, y1, x2, y2)
	local dx, dy = (x2 - x1) * width, (y2 - y1) * height
	return sqrt(dx * dx + dy * dy)
end

local function CleanName(name)
	if ns.IsSecret(name) or type(name) ~= "string" or name == "" then
		return nil
	end
	return ns.Utf8Truncate(name, MAX_NAME_BYTES)
end

---------------------------------------------------------------------------
-- Bornes
---------------------------------------------------------------------------

--- Emplacement le moins récemment vu de `list` ; `ownToo` faux : seulement parmi ceux reçus du groupe.
local function OldestIndex(list, ownToo)
	local index, oldest
	for i, spot in ipairs(list) do
		if (ownToo or not spot.m) and (not oldest or spot.t < oldest) then
			index, oldest = i, spot.t
		end
	end
	return index, oldest
end

--- Index de l'emplacement à retirer de `list` : le plus ancien reçu du groupe, sinon le plus ancien.
local function VictimIndex(list)
	return OldestIndex(list, false) or OldestIndex(list, true)
end

local EVICTION_PASSES = { false, true }

--- Retire l'emplacement le moins récemment vu, toutes cartes confondues : d'abord parmi ceux reçus du groupe. Un
--- membre qui envoie beaucoup de ressources n'efface donc pas ce que ce joueur a vu lui-même.
local function EvictOldest()
	local victimMap, victimIndex, victimTime
	for _, ownToo in ipairs(EVICTION_PASSES) do
		for mapID, list in pairs(storage) do
			local index, seenAt = OldestIndex(list, ownToo)
			if index and (not victimTime or seenAt < victimTime) then
				victimMap, victimIndex, victimTime = mapID, index, seenAt
			end
		end
		if victimMap then
			break
		end
	end
	if not victimMap then
		return
	end
	local list = storage[victimMap]
	table.remove(list, victimIndex)
	total = total - 1
	if #list == 0 then
		storage[victimMap] = nil
	end
end

---------------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------------

local function ValidSpot(spot)
	return type(spot) == "table" and IsCoord(spot.x) and IsCoord(spot.y) and VALID_KINDS[spot.k] == true
		and IsPositiveNumber(spot.t)
end

--- Rattache la table des SavedVariables : entrées invalides retirées (fichier modifié à la main, ancienne
--- version), bornes appliquées.
function KnownSpots.AttachStorage(db)
	total = 0
	for mapID, list in pairs(db) do
		if not ns.Coordinates.IsValidMapID(mapID) or type(list) ~= "table" then
			db[mapID] = nil
		else
			local kept = {}
			for _, spot in ipairs(list) do
				if ValidSpot(spot) and #kept < KnownSpots.MAX_PER_MAP then
					spot.n = CleanName(spot.n)
					spot.a = IsPositiveNumber(spot.a) and spot.a or KnownSpots.DEFAULT_ACCURACY
					spot.c = (IsPositiveNumber(spot.c) and spot.c >= 1) and min(floor(spot.c), KnownSpots.MAX_COUNT) or 1
					spot.m = spot.m == true or nil
					spot.g = IsPositiveNumber(spot.g) and spot.g or nil
					kept[#kept + 1] = spot
				end
			end
			-- remplacer la valeur d'une clé existante pendant le parcours est permis en Lua
			db[mapID] = #kept > 0 and kept or nil
			total = total + #kept
		end
	end
	storage = db
	while total > KnownSpots.MAX_TOTAL do
		EvictOldest()
	end
	Touch()
end

---------------------------------------------------------------------------
-- Enregistrement
---------------------------------------------------------------------------

--- Emplacement du type `kind` le plus proche de (x, y) sur la liste, à moins de MERGE_YARDS ou de la somme des
--- précisions (bornée à MAX_MERGE_YARDS) : deux vues imprécises d'un même objet peuvent être éloignées.
local function FindMatch(list, kind, width, height, x, y, accuracy)
	local best, bestDistance
	for _, spot in ipairs(list) do
		if spot.k == kind then
			local distance = Distance(width, height, spot.x, spot.y, x, y)
			local limit = max(KnownSpots.MERGE_YARDS, min(accuracy + spot.a, KnownSpots.MAX_MERGE_YARDS))
			if distance <= limit and (not bestDistance or distance < bestDistance) then
				best, bestDistance = spot, distance
			end
		end
	end
	return best, bestDistance
end

--- Mémorise un emplacement, ou met à jour le plus proche du même type (FindMatch). `isOwn` : vu par ce joueur
--- (détection ou récolte), pas seulement reçu du groupe. `now` (facultatif) : heure murale. Une nouvelle vue lève
--- la marque de récolte. Renvoie l'emplacement et "created" ou "updated", ou nil et une raison.
function KnownSpots.Record(kind, name, mapID, x, y, accuracy, isOwn, now)
	if not storage then
		return nil, "not_ready"
	end
	if not VALID_KINDS[kind] then
		return nil, "bad_kind"
	end
	if not ns.Coordinates.IsValidMapID(mapID) or not IsCoord(x) or not IsCoord(y) then
		return nil, "bad_position"
	end
	local width, height = ns.Coordinates.GetMapSizeYards(mapID)
	if not width then
		return nil, "no_map_size"
	end
	now = now or ns.Epoch()
	accuracy = IsPositiveNumber(accuracy) and accuracy or KnownSpots.DEFAULT_ACCURACY
	name = CleanName(name)

	local list = storage[mapID]
	local best, bestDistance
	if list then
		best, bestDistance = FindMatch(list, kind, width, height, x, y, accuracy)
	end

	if best then
		best.t = now
		best.c = min(best.c + 1, KnownSpots.MAX_COUNT)
		best.n = name or best.n
		local visible = best.g ~= nil -- revue après une récolte : de nouveau affichable
		best.g = nil
		if isOwn and not best.m then
			best.m = true
			visible = true -- affiché désormais même avec la réception désactivée
		end
		-- la position la plus précise gagne (une récolte, à portée, l'emporte sur un survol)
		if accuracy <= best.a then
			visible = visible or bestDistance >= KnownSpots.MOVE_NOTIFY_YARDS
			best.x, best.y, best.a = x, y, accuracy
		end
		if visible then
			Touch()
		end
		return best, "updated"
	end

	if not list then
		list = {}
	end
	if #list >= KnownSpots.MAX_PER_MAP then
		table.remove(list, (VictimIndex(list)))
		total = total - 1
	elseif total >= KnownSpots.MAX_TOTAL then
		EvictOldest()
	end
	local spot = { x = x, y = y, k = kind, n = name, a = accuracy, t = now, c = 1, m = isOwn and true or nil }
	list[#list + 1] = spot
	storage[mapID] = list -- EvictOldest peut avoir retiré une liste devenue vide
	total = total + 1
	Touch()
	return spot, "created"
end

--- Marque récolté l'emplacement d'une ressource disparue (FindMatch). `now` (facultatif) : heure murale.
--- Renvoie l'emplacement, ou nil.
function KnownSpots.MarkGathered(kind, mapID, x, y, accuracy, now)
	local list = storage and storage[mapID]
	if not list or not VALID_KINDS[kind] or not IsCoord(x) or not IsCoord(y) then
		return nil
	end
	local width, height = ns.Coordinates.GetMapSizeYards(mapID)
	if not width then
		return nil
	end
	accuracy = IsPositiveNumber(accuracy) and accuracy or KnownSpots.DEFAULT_ACCURACY
	local spot = FindMatch(list, kind, width, height, x, y, accuracy)
	if spot then
		spot.g = now or ns.Epoch()
		Touch()
	end
	return spot
end

--- Vrai si l'emplacement a été récolté il y a moins de GATHERED_HIDE_SECONDS (heure murale `now`).
function KnownSpots.IsRecentlyGathered(spot, now)
	return spot.g ~= nil and now >= spot.g and now - spot.g < KnownSpots.GATHERED_HIDE_SECONDS
end

---------------------------------------------------------------------------
-- Lecture et effacement
---------------------------------------------------------------------------

--- Appelle fn(spot) pour chaque emplacement connu de la carte `mapID`.
function KnownSpots.ForEachOnMap(mapID, fn)
	local list = storage and storage[mapID]
	if not list then
		return
	end
	for _, spot in ipairs(list) do
		fn(spot)
	end
end

--- Nombre d'emplacements connus : sur la carte `mapID`, ou en tout sans argument.
function KnownSpots.Count(mapID)
	if not storage then
		return 0
	end
	if mapID ~= nil then
		local list = storage[mapID]
		return list and #list or 0
	end
	return total
end

--- Efface tous les emplacements connus. Renvoie le nombre effacé.
function KnownSpots.Clear()
	if not storage then
		return 0
	end
	local removed = total
	ns.Wipe(storage)
	total = 0
	Touch()
	return removed
end

ns.On("PGR_CONFIG_LOADED", "KnownSpots", function()
	if type(ns.db.knownSpots) ~= "table" then
		ns.db.knownSpots = {}
	end
	KnownSpots.AttachStorage(ns.db.knownSpots)
end)
