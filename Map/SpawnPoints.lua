-- PartyGatherRadar - Map/SpawnPoints.lua
-- Points d'apparition : endroits où une herbe ou un filon peut pousser, lus dans QuestieDB (addon tiers, licence
-- GPL-3) quand il est installé. Rien de QuestieDB n'est copié dans l'addon : ses données sont lues en jeu, par son
-- interface publique (_G.LibQuestieDB : Object.spawns, Object.name, Support.Get("ZoneDB")).
--
-- Pourquoi : depuis la mise à jour Forever de novembre 2026 (build 70862), la minicarte n'est plus lisible à
-- distance (« Minimap is off limits », Stanzilla/WoWUIBugs#894). Ces points montrent sans survol où chercher ; leur
-- présence actuelle n'est jamais affirmée. Map/MinimapOverlay.lua les masque près d'une détection ou d'un
-- emplacement connu (Map/KnownSpots.lua), qui en disent plus.
--
-- Vérifié hors jeu le 2026-11-09 : les coordonnées de QuestieDB 1.0.13 (Forever) tombent à 0,1-0,3 % de carte
-- (5 à 15 m) des emplacements vus en jeu par Aedot (Bois de la Pénombre, Loch Modan, Steppes ardentes).
--
-- Construction par carte, à la demande, quelques objets par image et jamais en combat ; les 4 dernières cartes
-- sont gardées. Un point = { x, y (coordonnées de carte 0..1), k = "HERB"|"ORE", ids = { objets }, key = clé de
-- cadre }. Deux objets au même endroit (filons de cuivre et d'étain qui partagent leurs points) font un seul point.

local addonName, ns = ...

local SpawnPoints = ns.NewModule("SpawnPoints")
ns.SpawnPoints = SpawnPoints

local type, pairs, ipairs, pcall, floor = type, pairs, ipairs, pcall, math.floor

SpawnPoints.CONTRACT = 4            -- version de l'interface de QuestieDB attendue (X-Contract-Version)
SpawnPoints.OBJECTS_PER_STEP = 8    -- objets lus par image pendant la construction d'une carte
SpawnPoints.COMBAT_RETRY = 1        -- secondes avant de réessayer après un combat
SpawnPoints.MAX_CACHED_MAPS = 4
SpawnPoints.MAX_NAMES = 3           -- noms différents dans l'infobulle d'un point partagé
SpawnPoints.version = 0             -- incrémenté quand une carte est construite (rafraîchissement de l'affichage)

-- Objets de récolte (identifiants du jeu) : herbes et filons du client classique et de Forever. Liste établie le
-- 2026-11-09 à partir des objets de QuestieDB 1.0.13 portant ces noms (variantes de Forever comprises :
-- « Wilted Peacebloom », « Stunted Silverleaf », « Poor Copper Vein »...). Les noms seuls ne suffisent pas :
-- QuestieDB contient aussi des objets de quête homonymes de ressources (« Arathi Basin Doomweed01 »...).
SpawnPoints.OBJECTS = {}
local HERB_IDS = {
	1618, 3724, 657382, 657456, 656160, 657454,        -- Peacebloom, Wilted Peacebloom
	1617, 3725, 657380, 657457, 656161, 657455,        -- Silverleaf, Stunted Silverleaf
	1619, 3726, 657383, 657458,                        -- Earthroot
	1620, 3727, 657459,                                -- Mageroyal
	1621, 3729, 657385, 657460,                        -- Briarthorn
	2045, 657394,                                      -- Stranglekelp
	1622, 3730, 657386, 657461,                        -- Bruiseweed
	1623, 657387,                                      -- Wild Steelbloom
	1628, 1624, 2041, 657390, 2042, 2046, 2043, 2044, 2866, -- Grave Moss ... Firebloom
	142140, 180165, 142141, 176642, 142142, 176636, 180164, -- Purple Lotus, Arthas' Tears, Sungrass
	142143, 183046, 142144, 142145, 176637,            -- Blindweed, Ghost Mushroom, Gromsblood
	176583, 176638, 180167, 176584, 176639, 180168,    -- Golden Sansam, Dreamfoil
	176586, 176640, 180166, 176587, 176641, 176588, 176589, -- Mountain Silversage, Plaguebloom, Icecap, Black Lotus
	694732, 176753, 175566, 13891, 439762, 439810,     -- Forever : Tomb/Doom/Gloom Weed, Serpentbloom, Star Lotus, Moonroot
}
local ORE_IDS = {
	1731, 2055, 3763, 103713, 181248, 562111,          -- Copper Vein, Poor Copper Vein
	1732, 2054, 3764, 103711, 181249,                  -- Tin Vein
	1733, 105569, 73940,                               -- Silver Vein (et recouvert de vase)
	1735,                                              -- Iron Deposit
	1734, 150080, 181109, 73941,                       -- Gold Vein
	2040, 150079, 176645, 123310,                      -- Mithril Deposit
	2047, 150081, 181108, 123309,                      -- Truesilver Deposit
	165658,                                            -- Dark Iron Deposit
	324, 150082, 176643, 123848, 175404, 177388,       -- Small / Rich Thorium Vein
	1610, 1667, 2653,                                  -- Incendicite, Lesser Bloodstone
	656332, 656333, 439778, 439628,                    -- Forever : Chunk of Amber, Starsilver, Fool's Gold
}
local OBJECT_LIST = {} -- ordre de lecture stable
for _, id in ipairs(HERB_IDS) do
	SpawnPoints.OBJECTS[id] = "HERB"
	OBJECT_LIST[#OBJECT_LIST + 1] = id
end
for _, id in ipairs(ORE_IDS) do
	SpawnPoints.OBJECTS[id] = "ORE"
	OBJECT_LIST[#OBJECT_LIST + 1] = id
end

local cache = {}      -- [mapID] = { points = { ... }, usedAt = compteur }
local cacheCount = 0
local useCounter = 0
local job             -- construction en cours : { mapID, index, points, byPlace }
local stepScheduled = false
local library         -- LibQuestieDB, une fois vérifiée
local areaToMap       -- [areaId de QuestieDB] = uiMapID, lu une fois
local unavailable     -- raison pour laquelle QuestieDB est inutilisable, une fois constatée
local names = {}      -- [objectID] = nom lu (false : illisible)

---------------------------------------------------------------------------
-- Accès à QuestieDB
---------------------------------------------------------------------------

--- Bibliothèque de QuestieDB si elle est présente et compatible ; sinon nil et une raison ("absent", "contract").
local function Library()
	local lib = LibQuestieDB
	if type(lib) ~= "table" or type(lib.Object) ~= "table" or type(lib.Object.spawns) ~= "function" then
		return nil, "absent"
	end
	if type(lib.RequireContract) == "function" then
		local ok, supported = pcall(lib.RequireContract, SpawnPoints.CONTRACT)
		if not ok or not supported then
			return nil, "contract"
		end
	end
	return lib
end

--- Table de QuestieDB (texte « return { ... } » ou table) : [areaId] = uiMapID. Une valeur 0 retire la zone.
local function MergeAreaTable(target, value)
	if type(value) == "string" and loadstring then
		local chunk = loadstring(value)
		local ok, result = false, nil
		if chunk then
			ok, result = pcall(chunk)
		end
		value = ok and result or nil
	end
	if type(value) ~= "table" then
		return false
	end
	for area, uiMapID in pairs(value) do
		if type(area) == "number" and type(uiMapID) == "number" then
			target[area] = uiMapID > 0 and uiMapID or nil
		end
	end
	return true
end

--- Correspondance zone de QuestieDB -> carte du jeu ; nil si QuestieDB ne la publie pas.
local function LoadAreaTable(lib)
	local support = lib.Support
	if type(support) ~= "table" or type(support.Get) ~= "function" then
		return nil
	end
	local ok, zoneDB = pcall(support.Get, "ZoneDB")
	local private = ok and type(zoneDB) == "table" and zoneDB.private
	if type(private) ~= "table" then
		return nil
	end
	local result = {}
	if not MergeAreaTable(result, private.areaIdToUiMapId) then
		return nil
	end
	MergeAreaTable(result, private.areaIdToUiMapIdOverride) -- facultative : alias et zones retirées
	return result
end

--- Bibliothèque prête à l'emploi (table des zones comprise), ou nil et une raison. Vérifiée une fois : l'affichage
--- la demande à chaque rafraîchissement.
local function Ready()
	if library then
		return library
	end
	if unavailable then
		return nil, unavailable
	end
	local lib, reason = Library()
	if not lib then
		return nil, reason -- QuestieDB absent : redemandé plus tard (chargé à la demande par un autre addon)
	end
	areaToMap = LoadAreaTable(lib)
	if not areaToMap then
		unavailable = "zones"
		ns.Diagnostics.Log("SPAWNS", "QuestieDB présent mais sans table des zones : points d'apparition indisponibles")
		return nil, unavailable
	end
	library = lib
	return lib
end

--- Vrai si QuestieDB est utilisable.
function SpawnPoints.IsAvailable()
	return Ready() ~= nil
end

---------------------------------------------------------------------------
-- Construction d'une carte
---------------------------------------------------------------------------

local function IsPercent(value)
	return type(value) == "number" and value == value and value >= 0 and value <= 100
end

--- Ajoute les points de l'objet `id` situés sur la carte du travail en cours.
local function AddObject(lib, id)
	local ok, spawns = pcall(lib.Object.spawns, id)
	if not ok or type(spawns) ~= "table" then
		return
	end
	local kind = SpawnPoints.OBJECTS[id]
	for area, list in pairs(spawns) do
		if areaToMap[area] == job.mapID and type(list) == "table" then
			for _, coord in ipairs(list) do
				local x, y = type(coord) == "table" and coord[1], type(coord) == "table" and coord[2]
				-- (-1, -1) : objet d'instance, sans position sur la carte
				if IsPercent(x) and IsPercent(y) then
					-- même endroit au centième de pourcent : un seul point (objets qui partagent leurs points)
					local place = kind .. floor(x * 100 + 0.5) .. ":" .. floor(y * 100 + 0.5)
					local point = job.byPlace[place]
					if point then
						local ids = point.ids
						if ids[#ids] ~= id then
							ids[#ids + 1] = id
						end
					else
						local points = job.points
						point = { x = x / 100, y = y / 100, k = kind, ids = { id },
							key = job.mapID * 100000 + #points + 1 }
						points[#points + 1] = point
						job.byPlace[place] = point
					end
				end
			end
		end
	end
end

local function Evict()
	while cacheCount > SpawnPoints.MAX_CACHED_MAPS do
		local victim, oldest
		for mapID, entry in pairs(cache) do
			if not oldest or entry.usedAt < oldest then
				victim, oldest = mapID, entry.usedAt
			end
		end
		cache[victim] = nil
		cacheCount = cacheCount - 1
	end
end

local ScheduleStep

local function Step()
	stepScheduled = false
	if not job then
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		ScheduleStep(SpawnPoints.COMBAT_RETRY) -- jamais de lecture en combat
		return
	end
	local lib = Ready()
	if not lib then
		job = nil
		return
	end
	local last = job.index + SpawnPoints.OBJECTS_PER_STEP - 1
	for i = job.index, last do
		local id = OBJECT_LIST[i]
		if not id then
			break
		end
		AddObject(lib, id)
	end
	job.index = last + 1
	if job.index <= #OBJECT_LIST then
		ScheduleStep(0)
		return
	end
	useCounter = useCounter + 1
	if not cache[job.mapID] then
		cacheCount = cacheCount + 1
	end
	cache[job.mapID] = { points = job.points, usedAt = useCounter }
	ns.Diagnostics.Log("SPAWNS", "carte %d : %d point(s) d'apparition (QuestieDB)", job.mapID, #job.points)
	job = nil
	Evict()
	SpawnPoints.version = SpawnPoints.version + 1
	ns.Fire("PGR_SPAWNS_CHANGED")
end

ScheduleStep = function(delay)
	if stepScheduled then
		return
	end
	stepScheduled = true
	ns.After(delay, "SpawnPoints", Step)
end

--- Points de la carte `mapID` s'ils sont prêts ; sinon lance leur construction (PGR_SPAWNS_CHANGED à la fin) et
--- renvoie nil.
local function Request(mapID)
	local entry = cache[mapID]
	if entry then
		useCounter = useCounter + 1
		entry.usedAt = useCounter
		return entry.points
	end
	if not ns.Coordinates.IsValidMapID(mapID) or not Ready() then
		return nil
	end
	if not job or job.mapID ~= mapID then
		-- le joueur a changé de carte : la carte quittée sera reconstruite si elle est demandée de nouveau
		job = { mapID = mapID, index = 1, points = {}, byPlace = {} }
	end
	ScheduleStep(0)
	return nil
end

---------------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------------

--- Appelle fn(point) pour chaque point d'apparition de la carte `mapID` (rien tant que la carte se construit).
function SpawnPoints.ForEachOnMap(mapID, fn)
	local points = Request(mapID)
	if not points then
		return
	end
	for _, point in ipairs(points) do
		fn(point)
	end
end

--- Nombre de points d'apparition prêts : sur la carte `mapID`, ou sur les cartes gardées sans argument.
function SpawnPoints.Count(mapID)
	if mapID ~= nil then
		local entry = cache[mapID]
		return entry and #entry.points or 0
	end
	local total = 0
	for _, entry in pairs(cache) do
		total = total + #entry.points
	end
	return total
end

--- État pour /pgr status : "ready", "building", "absent", "contract" ou "zones".
function SpawnPoints.GetState()
	local lib, reason = Ready()
	if not lib then
		return reason
	end
	return job and "building" or "ready"
end

local function ObjectName(id)
	local cached = names[id]
	if cached == nil then
		cached = false
		local lib = Ready()
		local name
		if lib and type(lib.Object.name) == "function" then
			local ok, value = pcall(lib.Object.name, id)
			name = ok and value or nil
		end
		if type(name) == "string" and name ~= "" and not ns.IsSecret(name) then
			cached = ns.Utf8Truncate(name, 60)
		end
		names[id] = cached
	end
	return cached or nil
end

--- Nom affichable d'un point : noms de ses objets (langue du client si QuestieDB la fournit), sans doublon ;
--- nil si aucun n'est lisible.
function SpawnPoints.GetName(point)
	local list, seen = {}, {}
	for _, id in ipairs(point.ids) do
		local name = ObjectName(id)
		if name and not seen[name] then
			seen[name] = true
			list[#list + 1] = name
			if #list >= SpawnPoints.MAX_NAMES then
				break
			end
		end
	end
	if #list == 0 then
		return nil
	end
	return table.concat(list, " / ")
end

--- Oublie les cartes construites et l'état de QuestieDB (tests, rechargement des données).
function SpawnPoints.Reset()
	ns.Wipe(cache)
	ns.Wipe(names)
	cacheCount, job, library, areaToMap, unavailable = 0, nil, nil, nil, nil
	SpawnPoints.version = SpawnPoints.version + 1
end

-- fin de combat : une construction en attente reprend au prochain essai (au plus COMBAT_RETRY secondes)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", "SpawnPoints", function()
	if job then
		ScheduleStep(0)
	end
end)
