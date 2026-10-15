-- PartyGatherRadar - Core/Events.lua
-- Répartiteur unique d'événements du jeu, messages internes entre modules et minuteurs.
-- Chaque appel est protégé : un module qui provoque des erreurs répétées est désactivé
-- proprement sans interrompre les autres modules.

local addonName, ns = ...

local pcall, type, tostring = pcall, type, tostring

local MAX_MODULE_ERRORS = 3 -- erreurs tolérées...
local ERROR_WINDOW = 60     -- ...sur cette durée (secondes) avant la désactivation du module

local eventFrame = CreateFrame("Frame")
local eventListeners = {}   -- [event] = { { module = nom, fn = fonction }, ... }
local messageListeners = {} -- [message interne] = { { module = nom, fn = fonction }, ... }

---------------------------------------------------------------------------
-- Gestion des erreurs de modules
---------------------------------------------------------------------------

function ns.OnModuleError(moduleName, err)
	local module = ns.modules[moduleName]
	if ns.Diagnostics then
		ns.Diagnostics.RecordError(moduleName, err)
	end
	if not module then
		return
	end
	module.errors = (module.errors or 0) + 1
	-- seules les erreurs récentes comptent : quelques erreurs isolées dans une longue session
	-- ne désactivent pas un module, une rafale (OnUpdate, messages malformés en série) si
	local now = ns.Now()
	local recent = module.recentErrors or {}
	module.recentErrors = recent
	recent[#recent + 1] = now
	while recent[1] and now - recent[1] > ERROR_WINDOW do
		table.remove(recent, 1)
	end
	if module.enabled and #recent >= MAX_MODULE_ERRORS then
		module.enabled = false
		module.disabledReason = tostring(err)
		ns.Print(ns.T("MODULE_DISABLED", moduleName, tostring(err)))
		if module.OnDisabled then
			pcall(module.OnDisabled, module)
		end
	end
end

--- Appelle `fn(...)` sous protection au nom d'un module. Renvoie false si le module est désactivé ou a échoué.
function ns.SafeCall(moduleName, fn, ...)
	if not ns.IsModuleEnabled(moduleName) then
		return false
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		ns.OnModuleError(moduleName, err)
	end
	return ok, err
end

---------------------------------------------------------------------------
-- Événements du jeu
---------------------------------------------------------------------------

local function AddListener(registry, key, moduleName, fn)
	local list = registry[key]
	if not list then
		list = {}
		registry[key] = list
	end
	for i = 1, #list do
		if list[i].module == moduleName then
			list[i].fn = fn
			return list, false
		end
	end
	list[#list + 1] = { module = moduleName, fn = fn }
	return list, #list == 1
end

local function RemoveListener(registry, key, moduleName)
	local list = registry[key]
	if not list then
		return true
	end
	-- copie sur écriture : une répartition en cours garde l'ancienne liste intacte et ignore
	-- seulement l'écouteur marqué retiré (aucun autre écouteur n'est sauté)
	local kept = {}
	for i = 1, #list do
		local listener = list[i]
		if listener.module == moduleName then
			listener.removed = true
		else
			kept[#kept + 1] = listener
		end
	end
	if #kept == 0 then
		registry[key] = nil
		return true
	end
	registry[key] = kept
	return false
end

local function Dispatch(list, ...)
	if not list then
		return
	end
	for i = 1, #list do
		local listener = list[i]
		if not listener.removed then
			ns.SafeCall(listener.module, listener.fn, ...)
		end
	end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	Dispatch(eventListeners[event], event, ...)
end)

--- Inscrit `fn(event, ...)` pour un événement du jeu. Renvoie false si le client ne connaît pas l'événement.
function ns.RegisterEvent(event, moduleName, fn)
	local _, isFirst = AddListener(eventListeners, event, moduleName, fn)
	if isFirst then
		local ok, err = true, nil
		-- C_EventUtils.IsEventValid (client moderne) évite l'erreur "Attempt to register unknown event"
		if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
			ok, err = false, "IsEventValid = false"
		else
			ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
		end
		if not ok then
			RemoveListener(eventListeners, event, moduleName)
			if ns.Diagnostics then
				ns.Diagnostics.Log("EVENT", "événement inconnu du client : %s (%s)", event, tostring(err))
			end
			return false
		end
	end
	return true
end

function ns.UnregisterEvent(event, moduleName)
	if RemoveListener(eventListeners, event, moduleName) then
		pcall(eventFrame.UnregisterEvent, eventFrame, event)
	end
end

---------------------------------------------------------------------------
-- Messages internes (noms préfixés "PGR_")
---------------------------------------------------------------------------

function ns.On(message, moduleName, fn)
	AddListener(messageListeners, message, moduleName, fn)
end

function ns.Off(message, moduleName)
	RemoveListener(messageListeners, message, moduleName)
end

function ns.Fire(message, ...)
	Dispatch(messageListeners[message], message, ...)
end

---------------------------------------------------------------------------
-- Minuteurs (C_Timer) protégés
---------------------------------------------------------------------------

function ns.After(delay, moduleName, fn)
	C_Timer.After(delay, function()
		ns.SafeCall(moduleName, fn)
	end)
end

--- Minuteur répétitif. Renvoie un objet possédant :Cancel().
function ns.NewTicker(interval, moduleName, fn)
	return C_Timer.NewTicker(interval, function()
		ns.SafeCall(moduleName, fn)
	end)
end
