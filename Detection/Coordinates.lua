-- PartyGatherRadar - Detection/Coordinates.lua
-- Positions sur les cartes (coordonnées normalisées 0..1 d'un uiMapID), conversions officielles
-- carte <-> monde (C_Map) et projection sur la minicarte.
--
-- Choix de conception : les positions échangées sont exprimées en coordonnées de carte (uiMapID, x, y).
-- Le passage d'une carte à une autre utilise exclusivement C_Map.GetWorldPosFromMapPos et
-- C_Map.GetMapPosFromWorldPos ; aucune convention d'axes du monde n'est supposée.
-- Toute valeur nil ou secrète rend la position indisponible : aucune position n'est inventée.

local addonName, ns = ...

local Coordinates = ns.NewModule("Coordinates")
ns.Coordinates = Coordinates

local type, floor, sqrt, abs, min = type, math.floor, math.sqrt, math.abs, math.min
local cos, sin = math.cos, math.sin

-- Rayons de vue de la minicarte (mètres/yards) par niveau de zoom 0..5, utilisés seulement si
-- C_Minimap.GetViewRadius est absent. Valeurs publiques largement documentées (moitié des diamètres).
local FALLBACK_RADIUS = {
	outdoor = { [0] = 233.333, 200, 166.667, 133.333, 100, 66.667 },
	indoor = { [0] = 150, 120, 90, 60, 40, 25 },
}

local FAILURE_RETRY = 5 -- secondes avant de retenter une conversion qui a échoué

local mapSizeCache = {}      -- [uiMapID] = { width, height } ou { failedAt = t }
local mapContinentCache = {} -- [uiMapID] = { continentID } ou { failedAt = t }
local knownMapCache = {}     -- [uiMapID] = true/false (C_Map.GetMapInfo)

---------------------------------------------------------------------------
-- Validation (fonctions pures)
---------------------------------------------------------------------------

function Coordinates.IsValidMapCoord(value)
	return type(value) == "number" and value == value and value >= 0 and value <= 1
end

function Coordinates.IsValidMapID(mapID)
	return type(mapID) == "number" and mapID > 0 and mapID < 10000000 and floor(mapID) == mapID
end

---------------------------------------------------------------------------
-- Accès aux API du client
---------------------------------------------------------------------------

local function ReadVector(vector)
	if ns.IsSecret(vector) or vector == nil or type(vector) ~= "table" then
		return nil
	end
	local x, y
	if vector.GetXY then
		x, y = vector:GetXY()
	else
		x, y = vector.x, vector.y
	end
	if ns.AnySecret(x, y) or type(x) ~= "number" or type(y) ~= "number" then
		return nil
	end
	return x, y
end

--- Appel protégé d'une fonction C_Map : un identifiant de carte inconnu (venant d'un autre joueur)
--- ne doit jamais lever d'erreur dans les modules appelants.
local function SafeMapCall(fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		return nil
	end
	return a, b
end

--- Vrai si le client connaît cette carte (C_Map.GetMapInfo), résultat mis en cache.
function Coordinates.IsKnownMap(mapID)
	if not Coordinates.IsValidMapID(mapID) then
		return false
	end
	local known = knownMapCache[mapID]
	if known == nil then
		known = false
		if C_Map and C_Map.GetMapInfo then
			local info = SafeMapCall(C_Map.GetMapInfo, mapID)
			known = info ~= nil and not ns.IsSecret(info)
		end
		knownMapCache[mapID] = known
	end
	return known
end

local function NewVector(x, y)
	if CreateVector2D then
		return CreateVector2D(x, y)
	end
	return { x = x, y = y }
end

--- Position du joueur : mapID, x, y — ou nil, raison ("api", "nomap", "instance", "secret", "invalid").
function Coordinates.GetPlayerMapPosition()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
		return nil, "api"
	end
	local mapID = C_Map.GetBestMapForUnit("player")
	if ns.IsSecret(mapID) then
		return nil, "secret"
	end
	if mapID == nil then
		return nil, "nomap"
	end
	local position = C_Map.GetPlayerMapPosition(mapID, "player")
	if ns.IsSecret(position) then
		return nil, "secret"
	end
	if position == nil then
		return nil, "instance"
	end
	local x, y = ReadVector(position)
	if x == nil then
		return nil, "secret"
	end
	if not (Coordinates.IsValidMapCoord(x) and Coordinates.IsValidMapCoord(y)) or (x == 0 and y == 0) then
		return nil, "invalid"
	end
	return mapID, x, y
end

--- Position monde (continentID, wx, wy) d'un point de carte, ou nil.
function Coordinates.MapToWorld(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos) then
		return nil
	end
	local continentID, worldPosition = SafeMapCall(C_Map.GetWorldPosFromMapPos, mapID, NewVector(x, y))
	if ns.IsSecret(continentID) or continentID == nil then
		return nil
	end
	local wx, wy = ReadVector(worldPosition)
	if wx == nil then
		return nil
	end
	return continentID, wx, wy
end

--- Coordonnées sur `mapID` d'une position monde, ou nil.
function Coordinates.WorldToMap(continentID, wx, wy, mapID)
	if not (C_Map and C_Map.GetMapPosFromWorldPos) then
		return nil
	end
	local _, mapPosition = SafeMapCall(C_Map.GetMapPosFromWorldPos, continentID, NewVector(wx, wy), mapID)
	return ReadVector(mapPosition)
end

--- Continent (instance monde) d'une carte, mis en cache.
function Coordinates.GetMapContinent(mapID)
	local cached = mapContinentCache[mapID]
	if cached == nil or (cached.failedAt and ns.Now() - cached.failedAt >= FAILURE_RETRY) then
		local continentID = Coordinates.MapToWorld(mapID, 0.5, 0.5)
		-- un échec (chargement en cours…) n'est mémorisé que quelques secondes
		cached = continentID and { continentID } or { failedAt = ns.Now() }
		mapContinentCache[mapID] = cached
	end
	return cached[1]
end

--- Dimensions de la carte en mètres (yards) : largeur, hauteur — ou nil.
function Coordinates.GetMapSizeYards(mapID)
	local cached = mapSizeCache[mapID]
	if cached == nil or (cached.failedAt and ns.Now() - cached.failedAt >= FAILURE_RETRY) then
		cached = { failedAt = ns.Now() }
		local width, height
		if C_Map and C_Map.GetMapWorldSize then
			width, height = SafeMapCall(C_Map.GetMapWorldSize, mapID)
		end
		if ns.AnySecret(width, height) or type(width) ~= "number" or width <= 0 then
			width, height = nil, nil
			-- repli : distance entre coins convertis en positions monde (indépendant des axes)
			local c0, x0, y0 = Coordinates.MapToWorld(mapID, 0, 0)
			local c1, x1, y1 = Coordinates.MapToWorld(mapID, 1, 0)
			local c2, x2, y2 = Coordinates.MapToWorld(mapID, 0, 1)
			if c0 and c1 and c2 then
				width = sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
				height = sqrt((x2 - x0) ^ 2 + (y2 - y0) ^ 2)
			end
		end
		if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
			cached = { width, height }
		end
		mapSizeCache[mapID] = cached
	end
	return cached[1], cached[2]
end

--- Convertit un point de `sourceMap` vers `targetMap`. Renvoie nil si les cartes ne partagent pas
--- le même continent ou si la conversion officielle échoue. `force` impose l'aller-retour même si
--- les cartes sont identiques (utilisé par les sondes).
function Coordinates.TranslateToMap(sourceMap, x, y, targetMap, force)
	if sourceMap == targetMap and not force then
		return x, y
	end
	local continentID, wx, wy = Coordinates.MapToWorld(sourceMap, x, y)
	if not continentID then
		return nil
	end
	local targetContinent = Coordinates.GetMapContinent(targetMap)
	if targetContinent ~= continentID then
		return nil
	end
	return Coordinates.WorldToMap(continentID, wx, wy, targetMap)
end

--- Rayon de vue de la minicarte en mètres et source de la valeur.
function Coordinates.GetMinimapRadiusYards()
	if not Minimap then
		return nil, "minicarte absente"
	end
	if C_Minimap and C_Minimap.GetViewRadius then
		local radius = C_Minimap.GetViewRadius()
		if not ns.IsSecret(radius) and type(radius) == "number" and radius > 0 then
			return radius, "C_Minimap.GetViewRadius"
		end
	end
	local zoom = Minimap.GetZoom and Minimap:GetZoom()
	if ns.IsSecret(zoom) or type(zoom) ~= "number" then
		return nil, "zoom indisponible"
	end
	local indoors = IsIndoors and IsIndoors()
	local radius = FALLBACK_RADIUS[indoors and "indoor" or "outdoor"][zoom]
	if not radius then
		return nil, "zoom inconnu"
	end
	return radius, "table de repli"
end

---------------------------------------------------------------------------
-- Géométrie (fonctions pures, testées hors jeu)
---------------------------------------------------------------------------

--- Décalage en mètres entre deux points d'une même carte : est (+ vers l'est), nord (+ vers le nord).
function Coordinates.OffsetYards(width, height, fromX, fromY, toX, toY)
	local east = (toX - fromX) * width
	local north = (fromY - toY) * height -- y de carte croît vers le sud
	return east, north
end

--- Applique un décalage en mètres à un point de carte. Ne valide pas les bornes.
function Coordinates.ApplyOffset(width, height, x, y, eastYards, northYards)
	return x + eastYards / width, y - northYards / height
end

--- Projette un décalage (est, nord) sur la minicarte, en unités de cadre relatives au centre.
--- `facing` (radians, 0 = nord, sens antihoraire) n'est fourni que si la minicarte tourne.
function Coordinates.ProjectToMinimap(eastYards, northYards, radiusYards, halfWidth, halfHeight, facing)
	local x, y = eastYards, northYards
	if facing then
		local c, s = cos(facing), sin(facing)
		x = eastYards * c + northYards * s
		y = -eastYards * s + northYards * c
	end
	return x * halfWidth / radiusYards, y * halfHeight / radiusYards
end

--- Vrai si un point projeté (relatif au centre) reste dans la minicarte. Les formes autres que
--- "ROUND" sont traitées comme carrées (limitation documentée).
function Coordinates.IsInsideMinimap(px, py, halfWidth, halfHeight, isRound, margin)
	margin = margin or 0
	if isRound then
		local radius = min(halfWidth, halfHeight) - margin
		return px * px + py * py <= radius * radius
	end
	return abs(px) <= halfWidth - margin and abs(py) <= halfHeight - margin
end

--- Vide les caches (changement de carte majeur, tests).
function Coordinates.ResetCaches()
	ns.Wipe(mapSizeCache)
	ns.Wipe(mapContinentCache)
	ns.Wipe(knownMapCache)
end
