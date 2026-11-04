-- PartyGatherRadar - Detection/ResourceNames.lua
-- Tri des noms lus dans l'infobulle de la minicarte : herbe, minerai ou autre chose (zone de quête,
-- joueur, PNJ...). Module pur, testable hors jeu.
--
-- Constaté en jeu le 2026-10-15 : l'infobulle de la minicarte renvoie aussi les zones d'objectif de quête
-- et les noms des joueurs. Un nom n'est donc retenu que s'il est connu :
--   * herbes : liste des herbes (français et anglais), comparée sans accents ni majuscules ;
--   * minerais : liste, plus la forme des noms de gisements (« Filon de ... », « ... Vein ») ;
--   * noms appris à la récolte : le nom ciblé par Cueillette ou Minage est une ressource (SavedVariables).
-- Un nom inconnu n'est jamais partagé : il est seulement signalé dans le journal de diagnostic.

local addonName, ns = ...

local ResourceNames = {}
ns.ResourceNames = ResourceNames

local type, pairs, ipairs = type, pairs, ipairs
local lower, gsub = string.lower, string.gsub

ResourceNames.MAX_LEARNED = 200 -- noms appris gardés par type (SavedVariables bornées)

-- Lettres accentuées (UTF-8) ramenées à leur lettre de base, en minuscules.
local ACCENTS = {
	["à"] = "a", ["â"] = "a", ["ä"] = "a", ["á"] = "a", ["ã"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a",
	["ç"] = "c", ["Ç"] = "c",
	["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e",
	["î"] = "i", ["ï"] = "i", ["í"] = "i", ["Î"] = "i", ["Ï"] = "i",
	["ô"] = "o", ["ö"] = "o", ["ó"] = "o", ["õ"] = "o", ["Ô"] = "o", ["Ö"] = "o",
	["û"] = "u", ["ü"] = "u", ["ù"] = "u", ["ú"] = "u", ["Û"] = "u", ["Ü"] = "u", ["Ù"] = "u",
	["ÿ"] = "y", ["ñ"] = "n", ["Ñ"] = "n", ["œ"] = "oe", ["Œ"] = "oe", ["æ"] = "ae", ["Æ"] = "ae",
	["’"] = "'", ["\194\160"] = " ",
}

--- Forme de comparaison d'un nom : minuscules, sans accents, espaces simplifiés. nil si inexploitable.
function ResourceNames.Normalize(name)
	if ns.IsSecret(name) or type(name) ~= "string" then
		return nil
	end
	-- un caractère UTF-8 à la fois (2 puis 3 octets) ; les caractères absents de ACCENTS sont gardés
	local text = gsub(name, "[\194-\223][\128-\191]", ACCENTS)
	text = gsub(text, "[\224-\239][\128-\191][\128-\191]", ACCENTS)
	text = lower(text)
	text = gsub(text, "%s+", " ")
	text = gsub(text, "^ ", "")
	text = gsub(text, " $", "")
	if text == "" then
		return nil
	end
	return text
end

-- Herbes de la récolte classique, noms du client (anglais et français).
local HERBS = {
	-- anglais
	"Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp", "Bruiseweed",
	"Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker",
	"Wintersbite", "Firebloom", "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom",
	"Gromsblood", "Golden Sansam", "Dreamfoil", "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus",
	"Bloodthistle",
	-- français (« Pacifique » et « Eglantine » vus en jeu le 2026-10-15)
	"Pacifique", "Feuillargent", "Terrestrine", "Mage royal", "Églantine", "Étouffante", "Doulourante",
	"Aciérite sauvage", "Tombeline", "Sang-royal", "Vietérule", "Pâlerette", "Dorépine", "Moustache de Khadgar",
	"Hivernale", "Fleur de feu", "Lotus pourpre", "Larmes d'Arthas", "Soleillette", "Aveuglette",
	"Champignon fantôme", "Gromsang", "Sansam doré", "Feuillerêve", "Sauge-argent des montagnes",
	"Fleur de peste", "Calot de glace", "Lotus noir", "Chardon sanglant",
}

-- Gisements de minerai (anglais et français).
local ORES = {
	"Copper Vein", "Tin Vein", "Silver Vein", "Iron Deposit", "Gold Vein", "Mithril Deposit",
	"Truesilver Deposit", "Dark Iron Deposit", "Small Thorium Vein", "Rich Thorium Vein",
	"Incendicite Mineral Vein", "Indurium Mineral Vein", "Lesser Bloodstone Deposit", "Small Obsidian Chunk",
	"Large Obsidian Chunk", "Hakkari Thorium Vein",
	"Filon de cuivre", "Filon d'étain", "Filon d'argent", "Gisement de fer", "Filon d'or", "Gisement de mithril",
	"Gisement de vrai-argent", "Gisement de sombrefer", "Petit filon de thorium", "Riche filon de thorium",
	"Filon d'incendicite", "Filon d'indurium", "Gisement de pierre de sang inférieure",
	"Petit morceau d'obsidienne", "Grand morceau d'obsidienne", "Filon de thorium hakkari",
}

-- Forme des noms de gisements (après Normalize) : couvre les variantes absentes de la liste.
local ORE_PATTERNS = {
	"^filon ", "^gisement ", "^petit filon ", "^riche filon ", "morceau d'obsidienne$",
	" vein$", " deposit$", "obsidian chunk$",
}

local known = { HERB = {}, ORE = {} }
for _, name in ipairs(HERBS) do
	known.HERB[ResourceNames.Normalize(name)] = true
end
for _, name in ipairs(ORES) do
	known.ORE[ResourceNames.Normalize(name)] = true
end

local learned -- { HERB = { [nom normalisé] = nom affiché }, ORE = { ... } }, dans les SavedVariables

--- Rattache la table des noms appris (PartyGatherRadarDB.learnedNames) en la validant.
function ResourceNames.AttachStorage(storage)
	for _, kind in ipairs({ "HERB", "ORE" }) do
		if type(storage[kind]) ~= "table" then
			storage[kind] = {}
		end
		local count = 0
		for key, value in pairs(storage[kind]) do
			count = count + 1
			if type(key) ~= "string" or type(value) ~= "string" or count > ResourceNames.MAX_LEARNED then
				storage[kind][key] = nil
			end
		end
	end
	learned = storage
end

--- Type d'un nom d'infobulle : "HERB", "ORE" ou nil (autre chose, jamais partagé).
function ResourceNames.Classify(name)
	local key = ResourceNames.Normalize(name)
	if not key then
		return nil
	end
	if known.HERB[key] or (learned and learned.HERB[key]) then
		return "HERB"
	end
	if known.ORE[key] or (learned and learned.ORE[key]) then
		return "ORE"
	end
	for _, pattern in ipairs(ORE_PATTERNS) do
		if key:find(pattern) then
			return "ORE"
		end
	end
	return nil
end

--- Mémorise un nom de ressource vu à la récolte. Renvoie true s'il était inconnu.
function ResourceNames.Learn(kind, name)
	if not learned or (kind ~= "HERB" and kind ~= "ORE") then
		return false
	end
	local key = ResourceNames.Normalize(name)
	if not key or ResourceNames.Classify(name) == kind then
		return false
	end
	local count = 0
	for _ in pairs(learned[kind]) do
		count = count + 1
	end
	if count >= ResourceNames.MAX_LEARNED then
		return false
	end
	learned[kind][key] = name
	return true
end

ns.On("PGR_CONFIG_LOADED", "ResourceNames", function()
	if type(ns.db.learnedNames) ~= "table" then
		ns.db.learnedNames = {}
	end
	ResourceNames.AttachStorage(ns.db.learnedNames)
end)
