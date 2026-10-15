-- PartyGatherRadar - Map/MarkerManager.lua
-- Stockage des marqueurs, statuts, déduplication et expiration. Module sans cadre graphique,
-- testable hors jeu (horloge passée en paramètre).
--
-- Séparation stricte des données :
--   * magasin "real" : détections LIVE, positions HISTORY, marqueurs MANUAL ;
--   * magasin "test" : marqueurs TEST (tests contrôlés, sondes de calibration), jamais fusionnés
--     avec les données réelles, jamais convertis en données réelles.
--
-- Statuts affichés :
--   ACTIVE    détection récente confirmée par la source (vert)
--   UNCERTAIN détection devenue trop ancienne ou signalée incertaine (gris)
--   HISTORY   position historique : présence actuelle NON confirmée (marqueur discret)
--   MANUAL    marqueur posé à la main
--   TEST      donnée fictive de test

local addonName, ns = ...

local MarkerManager = {}
ns.MarkerManager = MarkerManager

local type, pairs, next, floor, sqrt, max = type, pairs, next, math.floor, math.sqrt, math.max

MarkerManager.MAX_REAL = 400
MarkerManager.MAX_TEST = 60
MarkerManager.MAX_REAL_PER_SENDER = 150 -- un seul émetteur ne peut pas évincer tous les autres
MarkerManager.MAX_TEST_PER_SENDER = 20
MarkerManager.MAX_ALIASES = 800        -- alias de fusion, bornés (mémoire)
MarkerManager.MERGE_RADIUS_YARDS = 5
MarkerManager.version = 0 -- incrémenté à chaque modification (rafraîchissement de l'affichage)

local VALID_SOURCES = { LIVE = true, HISTORY = true, MANUAL = true, TEST = true }
local VALID_KINDS = { HERB = true, ORE = true, TEST = true, OTHER = true }
local VALID_STATES = { DETECTED = true, UPDATED = true, UNCERTAIN = true, GONE = true }

local DEFAULT_TTL = { liveTTL = 60, uncertainTTL = 240, testTTL = 120 }

local stores = {
	real = { markers = {}, aliases = {}, count = 0, aliasCount = 0, max = MarkerManager.MAX_REAL,
		maxPerSender = MarkerManager.MAX_REAL_PER_SENDER },
	test = { markers = {}, aliases = {}, count = 0, aliasCount = 0, max = MarkerManager.MAX_TEST,
		maxPerSender = MarkerManager.MAX_TEST_PER_SENDER },
}

local function Setting(key)
	local value = ns.Config and ns.Config.Get and ns.Config.Get(key)
	if type(value) == "number" then
		return value
	end
	return DEFAULT_TTL[key]
end

local function Touch()
	MarkerManager.version = MarkerManager.version + 1
end

local function StoreFor(source)
	return source == "TEST" and stores.test or stores.real
end

local function MakeKey(sender, id)
	return sender .. "#" .. id
end

---------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------

local function IsCoord(value)
	return type(value) == "number" and value == value and value >= 0 and value <= 1
end

--- Vérifie une entrée de marqueur. Renvoie true ou false, raison.
function MarkerManager.Validate(data)
	if type(data) ~= "table" then
		return false, "not_table"
	end
	if type(data.sender) ~= "string" or data.sender == "" then
		return false, "bad_sender"
	end
	if type(data.id) ~= "string" or data.id == "" then
		return false, "bad_id"
	end
	if not VALID_SOURCES[data.source] then
		return false, "bad_source"
	end
	if not VALID_KINDS[data.kind] then
		return false, "bad_kind"
	end
	if not VALID_STATES[data.state] then
		return false, "bad_state"
	end
	-- séparation TEST / réel : une donnée TEST est toujours de type TEST, et réciproquement
	if (data.source == "TEST") ~= (data.kind == "TEST") then
		return false, "test_mismatch"
	end
	local mapID = data.uiMapID
	if type(mapID) ~= "number" or mapID <= 0 or floor(mapID) ~= mapID then
		return false, "bad_map"
	end
	if not IsCoord(data.x) or not IsCoord(data.y) then
		return false, "bad_coord"
	end
	return true
end

---------------------------------------------------------------------------
-- Distance et déduplication
---------------------------------------------------------------------------

--- Distance en mètres entre deux points d'une même carte (nil si la taille de la carte est inconnue).
local function DistanceYards(mapID, x1, y1, x2, y2)
	local width, height
	if ns.Coordinates and ns.Coordinates.GetMapSizeYards then
		width, height = ns.Coordinates.GetMapSizeYards(mapID)
	end
	if not width then
		return nil
	end
	local dx, dy = (x2 - x1) * width, (y2 - y1) * height
	return sqrt(dx * dx + dy * dy)
end
MarkerManager.DistanceYards = DistanceYards

local function FindMergeTarget(store, data)
	for _, marker in pairs(store.markers) do
		if marker.source == data.source and marker.kind == data.kind and marker.uiMapID == data.uiMapID then
			local distance = DistanceYards(data.uiMapID, marker.x, marker.y, data.x, data.y)
			if distance and distance <= MarkerManager.MERGE_RADIUS_YARDS then
				return marker
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Suppression
---------------------------------------------------------------------------

local function DeleteMarker(store, marker)
	if not store.markers[marker.key] then
		return false
	end
	store.markers[marker.key] = nil
	store.count = store.count - 1
	for alias, target in pairs(store.aliases) do
		if target == marker.key then
			store.aliases[alias] = nil
			store.aliasCount = store.aliasCount - 1
		end
	end
	Touch()
	return true
end

--- Ajoute un alias de fusion. Un émetteur n'a qu'un alias par marqueur cible (le plus récent) et le
--- nombre total d'alias est borné : un flot d'identifiants nouveaux au même endroit ne fait pas
--- grossir la mémoire.
local function AddAlias(store, key, sender, targetKey)
	local prefix = sender .. "#"
	for alias, target in pairs(store.aliases) do
		if target == targetKey and alias:sub(1, #prefix) == prefix then
			store.aliases[alias] = nil
			store.aliasCount = store.aliasCount - 1
		end
	end
	if store.aliasCount >= MarkerManager.MAX_ALIASES then
		local victim = next(store.aliases)
		if victim then
			store.aliases[victim] = nil
			store.aliasCount = store.aliasCount - 1
		end
	end
	store.aliases[key] = targetKey
	store.aliasCount = store.aliasCount + 1
end

--- Nombre de marqueurs dont `sender` est l'émetteur principal, et le plus ancien d'entre eux.
local function SenderUsage(store, sender)
	local count, oldest = 0, nil
	for _, marker in pairs(store.markers) do
		if marker.sender == sender then
			count = count + 1
			if not oldest or marker.lastSeen < oldest.lastSeen then
				oldest = marker
			end
		end
	end
	return count, oldest
end

local function EvictOldest(store)
	local oldest
	for _, marker in pairs(store.markers) do
		if not oldest or marker.lastSeen < oldest.lastSeen then
			oldest = marker
		end
	end
	if oldest then
		DeleteMarker(store, oldest)
	end
end

--- Retire la contribution d'un émetteur ; supprime le marqueur s'il n'a plus aucun émetteur.
local function RemoveReporter(store, marker, sender)
	marker.reporters[sender] = nil
	if next(marker.reporters) == nil then
		return DeleteMarker(store, marker)
	end
	if marker.sender == sender then
		-- l'émetteur principal part : un autre émetteur prend le relais
		marker.sender = next(marker.reporters)
	end
	Touch()
	return false
end

local function Resolve(store, key)
	local marker = store.markers[key]
	if marker then
		return marker
	end
	local target = store.aliases[key]
	return target and store.markers[target] or nil
end

---------------------------------------------------------------------------
-- Ajout et mise à jour
---------------------------------------------------------------------------

--- Ajoute ou met à jour un marqueur. Renvoie marker, action ("created", "updated", "merged", "removed")
--- ou nil, raison. `now` (facultatif) : horloge locale.
function MarkerManager.Upsert(data, now)
	local valid, reason = MarkerManager.Validate(data)
	if not valid then
		return nil, reason
	end
	now = now or ns.Now()
	local store = StoreFor(data.source)
	local key = MakeKey(data.sender, data.id)
	local seenAt = now - ((type(data.age) == "number" and data.age > 0) and data.age or 0)
	local existing = Resolve(store, key)

	if data.state == "GONE" then
		if existing then
			RemoveReporter(store, existing, data.sender)
			return existing, "removed"
		end
		return nil, "unknown_marker"
	end

	if existing then
		if existing.sender == data.sender or existing.key == key then
			existing.x, existing.y, existing.uiMapID = data.x, data.y, data.uiMapID
			existing.viewMapID = nil -- position modifiée : cache de projection invalide
		end
		existing.state = data.state
		existing.lastSeen = max(existing.lastSeen, seenAt)
		existing.reporters[data.sender] = seenAt
		if data.name and data.name ~= "" then
			existing.name = data.name
		end
		existing.accuracy = data.accuracy or existing.accuracy
		Touch()
		return existing, "updated"
	end

	if store == stores.real and (data.source == "LIVE" or data.source == "HISTORY") then
		local target = FindMergeTarget(store, data)
		if target then
			AddAlias(store, key, data.sender, target.key)
			target.reporters[data.sender] = seenAt
			target.lastSeen = max(target.lastSeen, seenAt)
			if data.state == "DETECTED" or data.state == "UPDATED" then
				target.state = data.state
			end
			Touch()
			return target, "merged"
		end
	end

	local used, oldestOfSender = SenderUsage(store, data.sender)
	if used >= store.maxPerSender and oldestOfSender then
		DeleteMarker(store, oldestOfSender)
	elseif store.count >= store.max then
		EvictOldest(store)
	end
	local marker = {
		key = key,
		sender = data.sender,
		id = data.id,
		source = data.source,
		kind = data.kind,
		state = data.state,
		uiMapID = data.uiMapID,
		x = data.x,
		y = data.y,
		accuracy = data.accuracy,
		resourceID = data.resourceID,
		name = data.name,
		firstSeen = seenAt,
		lastSeen = seenAt,
		reporters = { [data.sender] = seenAt },
		isLocal = data.isLocal and true or false,
	}
	store.markers[key] = marker
	store.count = store.count + 1
	Touch()
	return marker, "created"
end

--- Supprime la contribution `sender`/`id` (message REMOVE). Renvoie true si un marqueur a été touché.
function MarkerManager.Remove(sender, id, isTest)
	local store = isTest and stores.test or stores.real
	local marker = Resolve(store, MakeKey(sender, id))
	if not marker then
		return false
	end
	RemoveReporter(store, marker, sender)
	return true
end

--- Supprime toutes les contributions d'un émetteur (départ du groupe, BYE). Renvoie le nombre de marqueurs touchés.
function MarkerManager.RemoveBySender(sender)
	local touched = 0
	for _, store in pairs(stores) do
		local list = {}
		for _, marker in pairs(store.markers) do
			if marker.reporters[sender] then
				list[#list + 1] = marker
			end
		end
		for i = 1, #list do
			RemoveReporter(store, list[i], sender)
			touched = touched + 1
		end
		for alias in pairs(store.aliases) do
			if alias:sub(1, #sender + 1) == sender .. "#" then
				store.aliases[alias] = nil
				store.aliasCount = store.aliasCount - 1
			end
		end
	end
	return touched
end

--- Supprime les marqueurs temporaires : détections LIVE et marqueurs TEST. Les positions historiques
--- et marqueurs manuels sont conservés. Renvoie le nombre supprimé.
function MarkerManager.ClearTemporary()
	local removed = 0
	for key, marker in pairs(stores.real.markers) do
		if marker.source == "LIVE" then
			stores.real.markers[key] = nil
			removed = removed + 1
		end
	end
	stores.real.count = stores.real.count - removed
	ns.Wipe(stores.real.aliases)
	stores.real.aliasCount = 0
	removed = removed + MarkerManager.ClearTest()
	Touch()
	return removed
end

function MarkerManager.ClearTest()
	local removed = stores.test.count
	ns.Wipe(stores.test.markers)
	ns.Wipe(stores.test.aliases)
	stores.test.count = 0
	stores.test.aliasCount = 0
	Touch()
	return removed
end

--- Vide tout (tests unitaires).
function MarkerManager.Reset()
	for _, store in pairs(stores) do
		ns.Wipe(store.markers)
		ns.Wipe(store.aliases)
		store.count = 0
		store.aliasCount = 0
	end
	Touch()
end

--- Nombre d'alias de fusion (tests et diagnostics).
function MarkerManager.AliasCount()
	return stores.real.aliasCount, stores.test.aliasCount
end

---------------------------------------------------------------------------
-- Statuts et expiration
---------------------------------------------------------------------------

--- Statut d'affichage d'un marqueur, ou nil s'il est expiré.
function MarkerManager.GetStatus(marker, now)
	now = now or ns.Now()
	local age = now - marker.lastSeen
	if marker.source == "TEST" then
		return age <= Setting("testTTL") and "TEST" or nil
	end
	if marker.source == "HISTORY" then
		return "HISTORY"
	end
	if marker.source == "MANUAL" then
		return "MANUAL"
	end
	local liveTTL = Setting("liveTTL")
	if age > liveTTL + Setting("uncertainTTL") then
		return nil
	end
	if marker.state == "UNCERTAIN" or age > liveTTL then
		return "UNCERTAIN"
	end
	return "ACTIVE"
end

--- Supprime les marqueurs expirés. Renvoie le nombre supprimé.
function MarkerManager.Expire(now)
	now = now or ns.Now()
	local removed = 0
	for _, store in pairs(stores) do
		local expired
		for _, marker in pairs(store.markers) do
			if MarkerManager.GetStatus(marker, now) == nil then
				expired = expired or {}
				expired[#expired + 1] = marker
			end
		end
		if expired then
			for i = 1, #expired do
				if DeleteMarker(store, expired[i]) then
					removed = removed + 1
				end
			end
		end
	end
	return removed
end

---------------------------------------------------------------------------
-- Lecture
---------------------------------------------------------------------------

--- Appelle fn(marker, status) pour chaque marqueur non expiré. `which` : "real", "test" ou nil (tous).
function MarkerManager.ForEach(fn, now, which)
	now = now or ns.Now()
	for name, store in pairs(stores) do
		if which == nil or which == name then
			for _, marker in pairs(store.markers) do
				local status = MarkerManager.GetStatus(marker, now)
				if status then
					fn(marker, status)
				end
			end
		end
	end
end

function MarkerManager.Get(sender, id, isTest)
	return Resolve(isTest and stores.test or stores.real, MakeKey(sender, id))
end

--- Nombre de marqueurs : réels, test.
function MarkerManager.Count()
	return stores.real.count, stores.test.count
end
