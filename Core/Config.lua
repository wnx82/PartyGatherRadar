-- PartyGatherRadar - Core/Config.lua
-- Paramètres par défaut, initialisation et validation des SavedVariables (PartyGatherRadarDB).
-- Les SavedVariables ne sont lisibles qu'à partir de ADDON_LOADED pour cet addon.

local addonName, ns = ...

local Config = ns.NewModule("Config")
ns.Config = Config

local type, pairs = type, pairs

Config.SCHEMA = 1

Config.DEFAULTS = {
	-- Général
	enabled = true,
	shareEnabled = true,        -- envoyer nos informations au groupe
	receiveEnabled = true,      -- afficher les informations reçues
	showMinimap = true,
	showWorldMap = false,       -- prévu en phase 3, non implémenté dans le prototype
	allowRaid = true,           -- canal RAID en raid (expérimental)
	allowInstanceChat = false,  -- canal INSTANCE_CHAT en groupe de recherche (expérimental)

	-- Détection automatique (pistage actif, minicarte sondée toutes les 2 s)
	autoDetect = true,
	showOwnDetections = false,  -- nos détections sur notre minicarte (contrôle de la superposition)

	-- Ressources
	showHerbs = true,
	showOres = true,
	showLive = true,
	showHistory = true,

	-- Apparence
	iconSize = 14,
	iconAlpha = 0.9,
	showTooltipName = true,
	showTooltipReporter = true,
	showTooltipAge = true,
	colors = {
		live = { r = 0.20, g = 0.95, b = 0.20 },
		uncertain = { r = 0.60, g = 0.60, b = 0.60 },
		history = { r = 0.85, g = 0.75, b = 0.40 },
		test = { r = 0.30, g = 0.60, b = 1.00 },
	},

	-- Bouton autour de la minicarte (ouvre la fenêtre de réglages)
	showMinimapButton = true,
	minimapButtonAngle = 225,   -- degrés, 0 = est, sens trigonométrique (225 = en bas à gauche)

	-- Durées (secondes)
	liveTTL = 60,        -- détection considérée récente
	uncertainTTL = 240,  -- durée supplémentaire en état incertain avant suppression
	testTTL = 120,       -- durée de vie des marqueurs TEST

	-- Diagnostic
	debug = false,
}

-- Bornes des réglages numériques : { min, max }
local NUMERIC_BOUNDS = {
	iconSize = { 8, 32 },
	iconAlpha = { 0.2, 1 },
	liveTTL = { 10, 900 },
	uncertainTTL = { 0, 3600 },
	testTTL = { 10, 600 },
	minimapButtonAngle = { 0, 360 },
}

local function SanitizeColor(color, fallback)
	for _, channel in pairs({ "r", "g", "b" }) do
		local value = color[channel]
		if type(value) ~= "number" or value ~= value then
			color[channel] = fallback[channel]
		else
			color[channel] = ns.Clamp(value, 0, 1)
		end
	end
end

--- Corrige les valeurs hors bornes ou de mauvais type (fichier modifié à la main, ancienne version…).
function Config.Sanitize(settings)
	ns.MergeDefaults(settings, Config.DEFAULTS)
	for key, bounds in pairs(NUMERIC_BOUNDS) do
		local value = settings[key]
		if type(value) ~= "number" or value ~= value then
			settings[key] = Config.DEFAULTS[key]
		else
			settings[key] = ns.Clamp(value, bounds[1], bounds[2])
		end
	end
	for name, fallback in pairs(Config.DEFAULTS.colors) do
		SanitizeColor(settings.colors[name], fallback)
	end
	return settings
end

local function Migrate(db)
	-- Schéma 1 : version initiale. Les futures migrations s'ajoutent ici, dans l'ordre.
	db.schema = Config.SCHEMA
end

local function InitializeDatabase()
	local db = PartyGatherRadarDB
	if type(db) ~= "table" then
		db = {}
	end
	if type(db.schema) ~= "number" or db.schema < Config.SCHEMA then
		Migrate(db)
	end
	if type(db.settings) ~= "table" then
		db.settings = {}
	end
	Config.Sanitize(db.settings)
	if type(db.diagnostics) ~= "table" then
		db.diagnostics = {}
	end
	PartyGatherRadarDB = db
	ns.db = db
	ns.Diagnostics.AttachStorage(db.diagnostics)
end

function Config.Get(key)
	local settings = ns.db and ns.db.settings
	if settings then
		return settings[key]
	end
	return Config.DEFAULTS[key]
end

--- Modifie un réglage (valeur validée) et prévient les modules via PGR_SETTING_CHANGED.
function Config.Set(key, value)
	if not ns.db then
		return false
	end
	local default = Config.DEFAULTS[key]
	if default == nil or type(value) ~= type(default) then
		return false
	end
	local bounds = NUMERIC_BOUNDS[key]
	if bounds then
		value = ns.Clamp(value, bounds[1], bounds[2])
	end
	ns.db.settings[key] = value
	ns.Fire("PGR_SETTING_CHANGED", key, value)
	return true
end

ns.RegisterEvent("ADDON_LOADED", "Config", function(_, loadedName)
	if loadedName ~= addonName then
		return
	end
	ns.UnregisterEvent("ADDON_LOADED", "Config")
	InitializeDatabase()
	ns.Diagnostics.Log("CORE", "SavedVariables chargées (schéma %d)", ns.db.schema)
	ns.Fire("PGR_CONFIG_LOADED")
end)
