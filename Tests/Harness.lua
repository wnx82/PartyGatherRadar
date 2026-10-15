-- PartyGatherRadar - Tests/Harness.lua
-- Banc de test HORS JEU (Lua 5.1) : mini-cadre de tests, bouchons de l'API WoW et simulation de
-- plusieurs clients reliés par un faux réseau de messages d'addon.
--
-- Limites : ces bouchons reproduisent le comportement DOCUMENTÉ de l'API, pas le client réel.
-- Un test réussi ici ne remplace pas les scénarios en jeu de Tests/TestPlan.md.

local H = {}

local format, unpack = string.format, unpack or table.unpack

---------------------------------------------------------------------------
-- Mini-cadre de tests
---------------------------------------------------------------------------

H.results = { passed = 0, failed = 0, failures = {} }
H.currentSuite = "?"

function H.suite(name)
	H.currentSuite = name
	print("== " .. name)
end

function H.test(name, fn)
	local ok, err = xpcall(fn, function(e)
		return debug.traceback(tostring(e), 2)
	end)
	if ok then
		H.results.passed = H.results.passed + 1
		print("  [OK]    " .. name)
	else
		H.results.failed = H.results.failed + 1
		H.results.failures[#H.results.failures + 1] = H.currentSuite .. " > " .. name .. "\n" .. tostring(err)
		print("  [ECHEC] " .. name)
		print("          " .. tostring(err):gsub("\n", "\n          "))
	end
end

local function Describe(value)
	if type(value) == "string" then
		return format("%q", value)
	end
	return tostring(value)
end

function H.eq(actual, expected, message)
	if actual ~= expected then
		error(format("%s : attendu %s, obtenu %s", message or "égalité", Describe(expected), Describe(actual)), 2)
	end
end

function H.ok(value, message)
	if not value then
		error((message or "condition fausse") .. " (valeur : " .. Describe(value) .. ")", 2)
	end
end

function H.near(actual, expected, tolerance, message)
	if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
		error(format("%s : attendu %s ± %s, obtenu %s", message or "proximité", tostring(expected),
			tostring(tolerance), Describe(actual)), 2)
	end
end

function H.contains(list, predicate, message)
	for _, item in ipairs(list) do
		if predicate(item) then
			return item
		end
	end
	error(message or "élément introuvable", 2)
end

---------------------------------------------------------------------------
-- Lecture du TOC
---------------------------------------------------------------------------

function H.ReadToc(root)
	local handle = assert(io.open(root .. "/PartyGatherRadar.toc", "r"), "TOC introuvable")
	local metadata, files = {}, {}
	for line in handle:lines() do
		line = line:gsub("\r$", "")
		local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
		if key then
			metadata[key] = value
		elseif line:match("%S") and not line:match("^#") then
			files[#files + 1] = (line:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", ""))
		end
	end
	handle:close()
	return metadata, files
end

---------------------------------------------------------------------------
-- Monde simulé : horloge, cartes, réseau
---------------------------------------------------------------------------

local World = {}
World.__index = World

-- Cartes simulées : conversion linéaire carte <-> monde (nord = +wy). Les dimensions sont en mètres.
local MAPS = {
	[1429] = { name = "Forêt d'Elwynn", continent = 0, originX = 1000, originY = 5000, width = 3470, height = 2315 },
	[1436] = { name = "Marche de l'Ouest", continent = 0, originX = 1000, originY = 2685, width = 3500, height = 2333 },
	[1411] = { name = "Durotar", continent = 1, originX = 9000, originY = 3000, width = 5287, height = 3525 },
}
H.MAPS = MAPS

H.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

function H.NewWorld(root)
	local world = setmetatable({}, World)
	world.root = root
	world.time = 1000
	world.clients = {}
	world.group = nil      -- liste ordonnée des clients du groupe principal
	world.inbox = {}       -- messages en transit
	world.metadata, world.tocFiles = H.ReadToc(root)
	return world
end

function World:Now()
	return self.time
end

--- Remet les messages en transit à leurs destinataires.
function World:Flush()
	local guard = 0
	while #self.inbox > 0 do
		guard = guard + 1
		assert(guard < 1000, "boucle de messages infinie")
		local pending = self.inbox
		self.inbox = {}
		for _, message in ipairs(pending) do
			for _, client in ipairs(message.recipients) do
				if client.loaded and client.prefixes[message.prefix] then
					client:FireEvent("CHAT_MSG_ADDON", message.prefix, message.text, message.channel,
						message.sender, "", 0, 0, "", 0)
				end
			end
		end
	end
end

--- Avance l'horloge par pas de 0,05 s : minuteurs, OnUpdate et réseau.
function World:Advance(seconds)
	local step = 0.05
	local elapsed = 0
	while elapsed < seconds - 1e-9 do
		local dt = math.min(step, seconds - elapsed)
		self.time = self.time + dt
		elapsed = elapsed + dt
		for _, client in ipairs(self.clients) do
			if client.loaded then
				client:RunTimers()
				client:RunOnUpdate(dt)
			end
		end
		self:Flush()
	end
end

function World:GroupOf(client)
	if self.group then
		for _, member in ipairs(self.group) do
			if member == client then
				return self.group
			end
		end
	end
	return nil
end

--- Définit la composition du groupe et déclenche les événements correspondants.
function World:SetGroup(members, isRaid)
	local previous = self.group or {}
	self.group = (#members > 1) and members or nil
	self.isRaid = isRaid or false
	local inNew = {}
	for _, member in ipairs(members) do
		inNew[member] = true
	end
	for _, client in ipairs(previous) do
		-- un groupe réduit à une personne est dissous : le dernier membre le quitte aussi
		if (not inNew[client] or not self.group) and client.loaded then
			client:FireEvent("GROUP_LEFT")
			client:FireEvent("GROUP_ROSTER_UPDATE")
		end
	end
	local wasIn = {}
	for _, client in ipairs(previous) do
		wasIn[client] = true
	end
	if self.group then
		for _, client in ipairs(members) do
			if client.loaded then
				if not wasIn[client] then
					client:FireEvent("GROUP_JOINED")
				end
				client:FireEvent("GROUP_ROSTER_UPDATE")
			end
		end
	end
	self:Flush()
end

---------------------------------------------------------------------------
-- Client simulé
---------------------------------------------------------------------------

local Client = {}
Client.__index = Client

local KNOWN_EVENTS = {
	ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_ENTERING_WORLD = true, CHAT_MSG_ADDON = true,
	GROUP_ROSTER_UPDATE = true, GROUP_JOINED = true, GROUP_LEFT = true, MINIMAP_UPDATE_ZOOM = true,
	ZONE_CHANGED_NEW_AREA = true, CVAR_UPDATE = true, ADDON_RESTRICTION_STATE_CHANGED = true,
	UNIT_SPELLCAST_SENT = true,
}

local ALLOWED_GLOBALS = { SLASH_PARTYGATHERRADAR1 = true, PartyGatherRadarDB = true }

--- opts : { name, surname, realm, locale, hasAddon, mapID, x, y, inInstance, tracking }
--- Avec world.regionalNames (noms régionaux de WoW Forever), l'émetteur des messages a la forme
--- "Prénom Nom-Royaume", comme constaté en jeu le 2026-10-15 ("Aedot Wnx-ClassicBetaPvE2").
function World:NewClient(opts)
	local client = setmetatable({}, Client)
	client.world = self
	client.name = opts.name
	client.surname = opts.surname
	client.realm = opts.realm or "Realm"
	if self.regionalNames and client.surname then
		client.fullName = client.name .. " " .. client.surname .. "-" .. client.realm
	else
		client.fullName = client.name .. "-" .. client.realm
	end
	client.locale = opts.locale or "frFR"
	client.hasAddon = opts.hasAddon ~= false
	client.mapID = opts.mapID or 1429
	client.x, client.y = opts.x or 0.5, opts.y or 0.5
	client.inInstance = opts.inInstance or false
	client.cvars = { rotateMinimap = "0" }
	client.facing = 0
	client.savedVariables = nil
	client.chat = {}
	client.sent = {}
	client.sendResult = nil -- code forcé renvoyé par SendAddonMessage (tests de refus)
	client.blips = {}       -- points de minicarte simulés : { name, dx, dy } (unités du cadre)
	-- types de pistage connus du personnage (C_Minimap.GetTrackingInfo)
	client.tracking = opts.tracking or {}
	self.clients[#self.clients + 1] = client
	return client
end

function Client:FireEvent(event, ...)
	for _, frame in ipairs(self.frames) do
		if frame.events[event] and frame.scripts.OnEvent then
			frame.scripts.OnEvent(frame, event, ...)
		end
	end
end

function Client:RunTimers()
	local now = self.world.time
	local due = {}
	for i = #self.timers, 1, -1 do
		local timer = self.timers[i]
		if timer.cancelled then
			table.remove(self.timers, i)
		elseif now >= timer.at then
			due[#due + 1] = timer
			if timer.interval then
				timer.at = timer.at + timer.interval
			else
				table.remove(self.timers, i)
			end
		end
	end
	for i = #due, 1, -1 do
		if not due[i].cancelled then
			due[i].callback()
		end
	end
end

function Client:RunOnUpdate(dt)
	for _, frame in ipairs(self.frames) do
		local script = frame.scripts.OnUpdate
		if script then
			script(frame, dt)
		end
	end
end

function Client:ChatContains(pattern)
	for _, line in ipairs(self.chat) do
		if line:find(pattern) then
			return line
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Bouchons de l'API WoW pour un client
---------------------------------------------------------------------------

local function NewVector(x, y)
	return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end

local function NewRegion(kind)
	local region = { kind = kind, shown = true }
	local noop = function() end
	for _, method in ipairs({ "SetAllPoints", "SetColorTexture", "SetTexture", "SetVertexColor", "SetDesaturated",
		"AddMaskTexture", "SetDrawLayer" }) do
		region[method] = noop
	end
	function region:SetPoint(_, _, _, x, y) self.point = { x = x, y = y } end
	function region:ClearAllPoints() self.point = nil end
	return region
end

local function MakeFrameFactory(client)
	local function CreateFrame(frameType, name, parent)
		local frame = {
			frameType = frameType, name = name, parent = parent, events = {}, scripts = {}, shown = true,
			width = 0, height = 0, level = 1, alpha = 1,
		}
		function frame:RegisterEvent(event)
			if not KNOWN_EVENTS[event] then
				error("Attempt to register unknown event \"" .. tostring(event) .. "\"")
			end
			self.events[event] = true
		end
		function frame:UnregisterEvent(event) self.events[event] = nil end
		function frame:SetScript(script, fn) self.scripts[script] = fn end
		function frame:GetScript(script) return self.scripts[script] end
		function frame:HookScript(script, fn) self.scripts[script] = fn end
		function frame:Show() self.shown = true end
		function frame:Hide() self.shown = false end
		function frame:IsShown() return self.shown end
		function frame:IsVisible() return self.shown end
		function frame:SetSize(w, h) self.width, self.height = w, h end
		function frame:GetWidth() return self.width end
		function frame:GetHeight() return self.height end
		function frame:SetPoint(_, _, _, x, y) self.point = { x = x, y = y } end
		function frame:ClearAllPoints() self.point = nil end
		function frame:SetFrameLevel(level) self.level = level end
		function frame:GetFrameLevel() return self.level end
		function frame:SetAlpha(alpha) self.alpha = alpha end
		function frame:EnableMouse() end
		function frame:IsMouseOver() return false end
		function frame:GetEffectiveScale() return 1 end
		function frame:GetName() return self.name end
		function frame:CreateTexture() return NewRegion("Texture") end
		function frame:CreateMaskTexture() return NewRegion("MaskTexture") end
		client.frames[#client.frames + 1] = frame
		return frame
	end
	return CreateFrame
end

local function BuildEnvironment(client)
	local world = client.world
	local env = {}
	local api = {}

	-- bibliothèques Lua disponibles dans le bac à sable WoW
	for _, name in ipairs({ "pairs", "ipairs", "next", "type", "tostring", "tonumber", "select", "pcall", "xpcall",
		"error", "assert", "setmetatable", "getmetatable", "rawget", "rawset", "unpack", "string", "table", "math" }) do
		api[name] = _G[name]
	end
	api.unpack = unpack
	api.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		client.chat[#client.chat + 1] = table.concat(parts, " ")
	end
	api.os = { clock = os.clock, time = os.time }

	client.frames, client.timers = {}, {}
	api.CreateFrame = MakeFrameFactory(client)

	api.GetTime = function() return world.time end
	api.GetLocale = function() return client.locale end
	api.GetBuildInfo = function() return "1.60.1", "70374", "Oct 12 2026", 16001, "", " " end
	api.WOW_PROJECT_ID = 18
	api.WOW_PROJECT_CAMELOT = 18
	api.LE_PARTY_CATEGORY_HOME = 1
	api.LE_PARTY_CATEGORY_INSTANCE = 2
	api.SlashCmdList = {}
	api.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) client.chat[#client.chat + 1] = text end }
	api.GameTooltip = {
		SetOwner = function() end, AddLine = function() end, AddDoubleLine = function() end,
		Show = function() end, Hide = function() end, IsOwned = function() return false end,
	}
	api.issecretvalue = function(value) return value == H.SECRET end
	api.InCombatLockdown = function() return false end
	api.IsIndoors = function() return false end
	api.GetPlayerFacing = function() return client.facing end
	api.GetCursorPosition = function() return 0, 0 end
	api.C_CVar = { GetCVar = function(name) return client.cvars[name] end }
	api.CreateVector2D = NewVector

	api.Enum = {
		SendAddonMessageResult = {
			Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3, InvalidChatType = 4,
			NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9,
			NotInGuild = 10, AddOnMessageLockdown = 11, TargetOffline = 12,
		},
		AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
		AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
	}

	api.C_Timer = {
		After = function(delay, callback)
			client.timers[#client.timers + 1] = { at = world.time + delay, callback = callback }
		end,
		NewTicker = function(interval, callback)
			local timer = { at = world.time + interval, interval = interval, callback = callback }
			function timer:Cancel() self.cancelled = true end
			client.timers[#client.timers + 1] = timer
			return timer
		end,
	}

	-- identité et groupe
	api.GetNormalizedRealmName = function() return client.realm end
	api.UnitName = function(unit)
		if unit == "player" then
			return client.name
		end
		local other = client:UnitClient(unit)
		return other and other.name or nil
	end
	if client.world.regionalNames ~= nil then
		-- noms régionaux (Forever) : UnitName/UnitNameUnmodified renvoient (prénom, nom de famille), voir NameUtil.lua
		-- (Camelot) de Blizzard ; world.joinedNames simule l'autre forme ("Prénom Nom", nil). UnitFullName garde le
		-- comportement classique (prénom, royaume) : son comportement réel sur Forever n'est pas documenté.
		local regional = client.world.regionalNames
		api.RegionalUniqueNamesEnabled = function() return regional end
		api.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
		local function RegionalName(unit)
			local target = unit == "player" and client or client:UnitClient(unit)
			if not target then
				return nil
			end
			if target.secretName then
				return H.SECRET, H.SECRET
			end
			if not regional or not target.surname then
				return target.name
			end
			if client.world.joinedNames then
				return target.name .. " " .. target.surname, nil
			end
			return target.name, target.surname
		end
		api.UnitName = RegionalName
		api.UnitNameUnmodified = RegionalName
	end
	api.UnitFullName = function(unit)
		local target = unit == "player" and client or client:UnitClient(unit)
		if not target then
			return nil
		end
		if target.secretName then
			return H.SECRET, nil
		end
		return target.name, target.realm ~= client.realm and target.realm or nil
	end
	api.UnitExists = function(unit) return unit == "player" or client:UnitClient(unit) ~= nil end
	api.IsInGroup = function(category)
		if category == 2 then
			return false
		end
		return world:GroupOf(client) ~= nil
	end
	api.IsInRaid = function() return world:GroupOf(client) ~= nil and world.isRaid end
	api.GetNumGroupMembers = function()
		local group = world:GroupOf(client)
		return group and #group or 0
	end

	-- messagerie d'addon
	api.C_ChatInfo = {
		RegisterAddonMessagePrefix = function(prefix)
			if #prefix > 16 then
				return 2
			end
			if client.prefixes[prefix] then
				return 1
			end
			client.prefixes[prefix] = true
			return 0
		end,
		IsAddonMessagePrefixRegistered = function(prefix) return client.prefixes[prefix] == true end,
		InChatMessagingLockdown = function() return false end,
		SendAddonMessage = function(prefix, text, channel)
			assert(type(text) == "string" and #text <= 255, "message trop long")
			assert(channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT",
				"canal inattendu : " .. tostring(channel))
			if client.sendResult then
				return client.sendResult
			end
			local group = world:GroupOf(client)
			if not group then
				return 5
			end
			client.sent[#client.sent + 1] = { prefix = prefix, text = text, channel = channel }
			world.inbox[#world.inbox + 1] = {
				prefix = prefix, text = text, channel = channel, sender = client.fullName, recipients = group,
			}
			return 0
		end,
	}

	-- cartes
	api.C_Map = {
		GetBestMapForUnit = function(unit)
			if unit ~= "player" then
				return nil
			end
			return client.mapID
		end,
		GetPlayerMapPosition = function(mapID, unit)
			if unit ~= "player" or client.inInstance or mapID ~= client.mapID then
				return nil
			end
			return NewVector(client.x, client.y)
		end,
		GetMapInfo = function(mapID)
			local map = MAPS[mapID]
			return map and { mapID = mapID, name = map.name } or nil
		end,
		GetMapWorldSize = function(mapID)
			local map = MAPS[mapID]
			if not map then
				return 0, 0
			end
			return map.width, map.height
		end,
		GetWorldPosFromMapPos = function(mapID, position)
			local map = MAPS[mapID]
			if not map then
				return nil
			end
			return map.continent, NewVector(map.originX + position.x * map.width, map.originY - position.y * map.height)
		end,
		GetMapPosFromWorldPos = function(continentID, position, mapID)
			local map = MAPS[mapID]
			if not map or map.continent ~= continentID then
				return nil
			end
			return mapID, NewVector((position.x - map.originX) / map.width, (map.originY - position.y) / map.height)
		end,
	}

	-- minicarte
	api.Minimap = api.CreateFrame("Minimap", "Minimap")
	api.Minimap:SetSize(140, 140)
	api.Minimap.GetZoom = function() return 0 end
	api.Minimap.GetLeft = function() return 1000 end
	api.Minimap.GetBottom = function() return 600 end
	api.Minimap.GetCenter = function() return 1070, 670 end
	api.Minimap.SetUsingSoftCursor = function(_, value) client.softCursor = value end
	api.Minimap.UpdateMouseoverAtPoint = function(_, x, y)
		assert(client.softCursor, "UpdateMouseoverAtPoint appelé sans curseur logiciel")
		client.mouseover = { x - 1070, y - 670 }
	end
	api.C_TooltipInfo = {
		GetMinimapMouseover = function()
			local point = client.mouseover
			if not point then
				return nil
			end
			local lines = {}
			for _, blip in ipairs(client.blips) do
				if (point[1] - blip.dx) ^ 2 + (point[2] - blip.dy) ^ 2 <= 7 ^ 2 then
					lines[#lines + 1] = { leftText = blip.name }
				end
			end
			return { lines = lines }
		end,
	}
	api.C_Minimap = {
		GetViewRadius = function() return 233.333 end,
		GetNumTrackingTypes = function() return #client.tracking end,
		GetTrackingInfo = function(index) return client.tracking[index] end,
	}

	env.__api = api
	setmetatable(env, {
		__index = api,
		__newindex = function(t, key, value)
			client.globalsWritten[key] = true
			rawset(t, key, value)
		end,
	})
	return env
end

--- Unité "partyN"/"raidN" vue par ce client.
function Client:UnitClient(unit)
	local group = self.world:GroupOf(self)
	if not group then
		return nil
	end
	local kind, index = unit:match("^(%a+)(%d+)$")
	index = tonumber(index)
	if not kind or not index then
		return nil
	end
	if kind == "raid" then
		return group[index]
	end
	if kind == "party" then
		local others = {}
		for _, member in ipairs(group) do
			if member ~= self then
				others[#others + 1] = member
			end
		end
		return others[index]
	end
	return nil
end

--- Charge l'addon (fichiers du TOC dans l'ordre) puis simule ADDON_LOADED, PLAYER_LOGIN et PLAYER_ENTERING_WORLD.
function Client:Login(isReload)
	self.prefixes = {}
	self.globalsWritten = {}
	self.env = BuildEnvironment(self)
	if self.savedVariables then
		self.env.PartyGatherRadarDB = self.savedVariables
		self.globalsWritten.PartyGatherRadarDB = nil
	end
	self.loaded = true
	if not self.hasAddon then
		return
	end
	self.ns = {}
	for _, file in ipairs(self.world.tocFiles) do
		local chunk = assert(loadfile(self.world.root .. "/" .. file))
		setfenv(chunk, self.env)
		chunk("PartyGatherRadar", self.ns)
	end
	self:FireEvent("ADDON_LOADED", "PartyGatherRadar")
	self:FireEvent("PLAYER_LOGIN")
	self:FireEvent("PLAYER_ENTERING_WORLD", not isReload, isReload and true or false)
	self.world:Flush()
end

--- Simule /reload : nouvel environnement Lua, SavedVariables conservées.
function Client:Reload()
	self.savedVariables = self.env.PartyGatherRadarDB
	self:Login(true)
end

--- Exécute une commande /pgr.
function Client:Slash(text)
	self.env.SlashCmdList.PARTYGATHERRADAR(text or "")
end

function Client:UnexpectedGlobals()
	local list = {}
	for name in pairs(self.globalsWritten) do
		if not ALLOWED_GLOBALS[name] then
			list[#list + 1] = name
		end
	end
	table.sort(list)
	return list
end

H.ALLOWED_GLOBALS = ALLOWED_GLOBALS

--- Types de pistage simulés.
H.HERB_TRACKING = { name = "Découverte d'herbes", active = true, spellID = 2383, type = "spell" }
H.ORE_TRACKING = { name = "Découverte de gisements", active = false, spellID = 2580, type = "spell" }

return H
