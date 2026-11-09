-- PartyGatherRadar - Detection/AutoDetect.lua
-- Détection automatique des herbes et minerais affichés sur la minicarte, et partage au groupe.
--
-- Principe (API officielle propre à Forever, vérifiée en jeu le 2026-10-15) : toutes les 2 secondes, si le
-- pistage des herbes ou des minerais est actif, la minicarte est sondée point par point
-- (Minimap:SetUsingSoftCursor + Minimap:UpdateMouseoverAtPoint + C_TooltipInfo.GetMinimapMouseover), par lots
-- de 40 points par image. Chaque lot convertit ses points avec la position du joueur du moment : le balayage
-- reste juste pendant un déplacement. Seuls les noms reconnus comme herbe ou minerai sont gardés
-- (Detection/ResourceNames.lua).
--
-- Suivi : une ressource revue au même endroit garde son identifiant et sa position s'affine (moyenne). Elle
-- est envoyée au groupe à sa découverte, puis rafraîchie toutes les 25 s tant qu'elle reste visible. Absente
-- de 2 balayages alors qu'elle devrait être visible (pistage actif, bien à l'intérieur du rayon de la
-- minicarte) : elle est considérée récoltée ou disparue, retirée et signalée au groupe (REMOVE).
--
-- Jamais pendant un combat ou une restriction d'addons (rencontre, mode défi, JcJ, carte restreinte), jamais
-- quand la souris survole la minicarte (infobulle native du joueur), jamais sans pistage actif : aucun
-- pistage n'est activé par l'addon.
--
-- Survol : quand le joueur passe lui-même la souris sur un point de la minicarte, l'infobulle native sous le
-- VRAI curseur est lue toutes les 0,2 s ; une herbe ou un minerai reconnu est suivi et partagé comme par le
-- balayage. Cette lecture marche sans le curseur logiciel. La souris qui parcourt le point affine la position
-- à chaque lecture : ce renvoi part au plus toutes les 2 s, et la dernière position part même après le survol.
--
-- Adaptation au client : une mise à jour de WoW Forever de novembre 2026 a restreint la sonde. Elle ne nomme
-- plus un point que sous le vrai curseur (constat publié par NaowhForever_Professions 1.2.17), donc le
-- balayage ne renvoie plus rien, sans erreur. Signe retenu : une ressource vue au survol est absente du
-- balayage suivant, et ce balayage n'a lu aucune ressource (les autres noms, comme les zones de quête, ne
-- comptent pas). Une preuve par ressource physique, valable 10 min ; un balayage qui lit une ressource les
-- efface toutes. Après 2 preuves, le balayage est déclaré aveugle. Effets : avertissement unique, détection
-- au survol seule, un essai de balayage toutes les 30 s, et retour automatique dès qu'un essai relit une
-- ressource sur au plus la moitié de ses points (sinon : infobulle figée). L'état est mémorisé pour le
-- build du client (PartyGatherRadarDB.probe) et réévalué à chaque nouveau build. Une ressource vue
-- seulement au survol n'est jamais déclarée disparue par un balayage qui n'a lu aucune ressource.
--
-- Récolte : une herbe récoltée par le joueur (sort réussi) est retirée tout de suite, chez lui et dans le
-- groupe. Un filon n'est pas retiré, car il peut souvent être miné plusieurs fois.
--
-- Sans souris (0.5.0) : une ressource vue de près par la cible d'interaction douce du jeu (Detection/Proximity.lua)
-- est suivie et partagée comme une ressource survolée, à la position du joueur. Chaque ressource suivie, et
-- chaque récolte, alimente aussi les emplacements connus (Map/KnownSpots.lua).

local addonName, ns = ...

local AutoDetect = ns.NewModule("AutoDetect")
ns.AutoDetect = AutoDetect

local pairs, ipairs, type, tostring, pcall = pairs, ipairs, type, tostring, pcall
local sqrt, floor, max, min = math.sqrt, math.floor, math.max, math.min
local format = string.format

AutoDetect.PASS_INTERVAL = 2       -- secondes entre deux balayages
AutoDetect.GRID_SPACING = 10       -- unités du cadre Minimap (≈ 33 m au zoom minimal)
AutoDetect.POINTS_PER_FRAME = 40
AutoDetect.LINK_UNITS = 15         -- points d'un même nom voisins sur la grille (10 ; diagonale 14,1) : reliés
AutoDetect.CLUSTER_UNITS = 15      -- rayon de rapprochement avec une ressource suivie, en unités du cadre
AutoDetect.MATCH_MIN_YARDS = 25    -- rapprochement minimal avec une ressource déjà suivie
AutoDetect.MAX_WEIGHT = 20         -- poids maximal de l'historique dans la moyenne des positions
AutoDetect.RESEND_INTERVAL = 25    -- secondes : garde les marqueurs des autres « récents » (liveTTL 60 s)
AutoDetect.RESEND_MOVE_YARDS = 8   -- position affinée de plus de 8 m : renvoyée tout de suite
AutoDetect.MISS_LIMIT = 2          -- balayages consécutifs sans la ressource avant de la déclarer disparue
AutoDetect.INSIDE_FACTOR = 0.75    -- part du rayon de la minicarte où une absence est fiable
AutoDetect.MAX_NODES = 150         -- même borne que MarkerManager.MAX_REAL_PER_SENDER
AutoDetect.UNKNOWN_LOG_LIMIT = 30  -- noms inconnus journalisés (une fois chacun)
AutoDetect.HOVER_INTERVAL = 0.2    -- secondes entre deux lectures de l'infobulle sous le vrai curseur
AutoDetect.HOVER_RESEND_INTERVAL = 2 -- survol : position affinée renvoyée au plus toutes les 2 s
AutoDetect.BLIND_EVIDENCE = 2      -- ressources survolées absentes d'un balayage vide : balayage aveugle
AutoDetect.BLIND_RETRY_INTERVAL = 30 -- balayage aveugle : un essai toutes les 30 s pour repérer son retour
AutoDetect.FAILURE_WARN_LIMIT = 5  -- balayages d'affilée interrompus par une erreur de sonde : alerte
AutoDetect.GATHER_RADIUS = 20      -- mètres : herbe du même nom retirée autour du joueur après la récolte
AutoDetect.GATHER_ACCURACY = 5     -- mètres : emplacement d'une ressource récoltée (le joueur est à portée)
-- secondes : une herbe cueillie que la cible douce désigne encore n'est pas signalée de nouveau
AutoDetect.GATHERED_IGNORE_SECONDS = 60
AutoDetect.EVIDENCE_WINDOW = 600   -- secondes : une preuve de balayage aveugle plus ancienne ne compte plus
AutoDetect.EVIDENCE_DELAY = 10     -- secondes : un survol plus ancien n'est plus comparé au balayage suivant
AutoDetect.EVIDENCE_SAME_YARDS = 50 -- deux preuves du même nom à moins de 50 m : une seule ressource
AutoDetect.RESTORE_MAX_SHARE = 0.5 -- retour au balayage : ressource lue sur au plus la moitié des points

-- Restrictions d'addons (API de Midnight, présentes sur Forever) pendant lesquelles les valeurs lues
-- deviennent secrètes ; le combat est déjà couvert par InCombatLockdown
local RESTRICTIONS = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }

-- Sorts de récolte : le nom ciblé est une ressource (apprentissage des noms)
local GATHER_SPELLS = {
	[2366] = "HERB", [2368] = "HERB", [3570] = "HERB", [11993] = "HERB",
	[2575] = "ORE", [2576] = "ORE", [3564] = "ORE", [10248] = "ORE",
}
local HERB_GATHERING_SPELL, MINING_SPELL = 2366, 2575

local frame
local pass                 -- balayage en cours
local nodes = {}           -- [id] = ressource suivie
local nodeCount = 0
local nextId = 0
local sessionTag
local forceResend = false
local unknownNames = {}
local unknownCount = 0
local blind = false          -- balayage aveugle (client restreint) : détection au survol seule
-- preuves de balayage aveugle : ressources survolées absentes d'un balayage sans aucune ressource,
-- { name, mapID, x, y, at } ; une par ressource physique (nom et position), pas par identifiant
local blindEvidence = {}
local blindNoticeShown = false
local restoredNoticeShown = false
local probeStorage           -- PartyGatherRadarDB.probe : { blindBuild = build du client }
local lastPassStartedAt
local lastSoftCursorAt       -- dernier usage du curseur logiciel : l'infobulle peut encore refléter son point
local consecutiveFailures = 0
local failureWarned = false
local lastGather             -- dernier sort de récolte envoyé : { castGUID, kind, name }
-- herbes cueillies depuis moins de GATHERED_IGNORE_SECONDS : { name (normalisé), mapID, x, y, at, key, logged }
local recentGathers = {}

AutoDetect.stats = { passes = 0, aborted = 0, lastAbort = nil, found = 0, gone = 0, hovered = 0, near = 0,
	gathered = 0 }

---------------------------------------------------------------------------
-- Conditions
---------------------------------------------------------------------------

--- Types de ressources dont le pistage est actif : { HERB = bool, ORE = bool } ou nil si aucun.
local function ActiveKinds()
	local state = ns.Tracking.GetTrackingState()
	if not state.available then
		return nil
	end
	local herbs = state.herbs ~= nil and state.herbs.active
	local ores = state.ores ~= nil and state.ores.active
	if not (herbs or ores) then
		return nil
	end
	return { HERB = herbs and true or false, ORE = ores and true or false }
end

--- Vrai si une restriction d'addons est active (valeur secrète ou API absente : pas de restriction connue).
function AutoDetect.IsAddOnRestricted()
	local isActive = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
	local types = Enum and Enum.AddOnRestrictionType
	if not (isActive and types) then
		return false
	end
	for _, name in ipairs(RESTRICTIONS) do
		local restrictionType = types[name]
		if restrictionType ~= nil then
			local ok, active = pcall(isActive, restrictionType)
			if ok and not ns.IsSecret(active) and active == true then
				return true
			end
		end
	end
	return false
end

--- Vrai si un balayage peut avoir lieu maintenant ; sinon false, raison.
function AutoDetect.CanScan()
	if not ns.Config.Get("enabled") or not ns.Config.Get("autoDetect") then
		return false, "disabled"
	end
	if not ns.Tracking.ProbeApisAvailable() then
		return false, "api"
	end
	if ns.Tracking.IsScanRunning() then
		return false, "probe"
	end
	if InCombatLockdown and InCombatLockdown() then
		return false, "combat"
	end
	if AutoDetect.IsAddOnRestricted() then
		return false, "restricted"
	end
	if not Minimap:IsVisible() then
		return false, "hidden"
	end
	if Minimap:IsMouseOver() then
		return false, "mouse"
	end
	return true
end

---------------------------------------------------------------------------
-- Ressources suivies
---------------------------------------------------------------------------

local function NewId()
	nextId = nextId + 1
	return format("%s%x", sessionTag, nextId)
end

local function Yards(width, height, x1, y1, x2, y2)
	local dx, dy = (x2 - x1) * width, (y2 - y1) * height
	return sqrt(dx * dx + dy * dy)
end

local function RemoveNode(node)
	nodes[node.id] = nil
	nodeCount = nodeCount - 1
end

--- Regroupe les points touchés par nom, dans l'espace de la carte (mètres). Deux points du même nom sont
--- reliés s'ils sont voisins sur la grille (diagonale comprise) : une ressource touchée sur plusieurs points
--- donne un seul groupe, quelle que soit sa forme. Un regroupement autour d'un centre mobile découpait un
--- même point en plusieurs repères (constaté en jeu le 2026-10-15). Renvoie une liste de
--- { name, kind, x, y, hits, spread, yardsPerUnit }.
function AutoDetect.ClusterHits(hits, width, height)
	-- union-find sur les points
	local parent = {}
	local function Root(i)
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end
	for i = 1, #hits do
		parent[i] = i
	end
	for i = 1, #hits do
		local a = hits[i]
		local link = AutoDetect.LINK_UNITS * a.yardsPerUnit
		for j = i + 1, #hits do
			local b = hits[j]
			if a.name == b.name and Yards(width, height, a.x, a.y, b.x, b.y) <= link then
				local ra, rb = Root(i), Root(j)
				if ra ~= rb then
					parent[rb] = ra
				end
			end
		end
	end
	local byRoot, clusters = {}, {}
	for i, hit in ipairs(hits) do
		local root = Root(i)
		local cluster = byRoot[root]
		if not cluster then
			cluster = { name = hit.name, kind = hit.kind, sumX = 0, sumY = 0, hits = 0, points = {},
				yardsPerUnit = hit.yardsPerUnit }
			byRoot[root] = cluster
			clusters[#clusters + 1] = cluster
		end
		cluster.sumX = cluster.sumX + hit.x
		cluster.sumY = cluster.sumY + hit.y
		cluster.hits = cluster.hits + 1
		cluster.points[#cluster.points + 1] = hit
	end
	for _, cluster in ipairs(clusters) do
		cluster.x, cluster.y = cluster.sumX / cluster.hits, cluster.sumY / cluster.hits
		local spread = 0
		for _, point in ipairs(cluster.points) do
			spread = max(spread, Yards(width, height, cluster.x, cluster.y, point.x, point.y))
		end
		cluster.spread = spread
		cluster.points = nil
	end
	return clusters
end

local function FindNode(cluster, mapID, width, height)
	local limit = max(AutoDetect.MATCH_MIN_YARDS, AutoDetect.CLUSTER_UNITS * cluster.yardsPerUnit)
	local best, bestDistance
	for _, node in pairs(nodes) do
		if node.mapID == mapID and node.name == cluster.name then
			local distance = Yards(width, height, node.x, node.y, cluster.x, cluster.y)
			if distance <= limit and (not bestDistance or distance < bestDistance) then
				best, bestDistance = node, distance
			end
		end
	end
	return best
end

local function Accuracy(cluster)
	return cluster.spread + AutoDetect.GRID_SPACING * cluster.yardsPerUnit / 2
end

local function OldestNode()
	local oldest
	for _, node in pairs(nodes) do
		if not oldest or node.lastSeen < oldest.lastSeen then
			oldest = node
		end
	end
	return oldest
end

local HOW_LABELS = { hover = " (survol)", near = " (proximité)" }

--- Nouvelle ressource suivie. `how` : nil (balayage), "hover" (survol) ou "near" (proximité).
local function CreateNode(cluster, mapID, now, how)
	if nodeCount >= AutoDetect.MAX_NODES then
		local oldest = OldestNode()
		if oldest then
			RemoveNode(oldest)
		end
	end
	local node = {
		id = NewId(), name = cluster.name, kind = cluster.kind, mapID = mapID, x = cluster.x, y = cluster.y,
		weight = cluster.hits, accuracy = Accuracy(cluster), firstSeen = now, lastSeen = now, misses = 0,
	}
	nodes[node.id] = node
	nodeCount = nodeCount + 1
	AutoDetect.stats.found = AutoDetect.stats.found + 1
	if how == "hover" then
		AutoDetect.stats.hovered = AutoDetect.stats.hovered + 1
	elseif how == "near" then
		AutoDetect.stats.near = AutoDetect.stats.near + 1
	end
	ns.Diagnostics.Log("DETECT", "%s : %s, carte %d (%.2f, %.2f) ±%.0f m%s", node.kind == "HERB" and "herbe" or "minerai",
		node.name, mapID, node.x * 100, node.y * 100, node.accuracy, how and HOW_LABELS[how] or "")
	return node
end

--- Vrai si la ressource n'a été vue qu'au survol ou de près depuis le dernier balayage qui l'a trouvée.
local function IsHoverOnly(node)
	local seenAt = node.hoverAt
	if node.nearAt and (seenAt == nil or node.nearAt > seenAt) then
		seenAt = node.nearAt
	end
	return seenAt ~= nil and (node.scanAt == nil or node.scanAt < seenAt)
end

local function UpdateNode(node, cluster, now)
	local weight = min(node.weight, AutoDetect.MAX_WEIGHT)
	local total = weight + cluster.hits
	node.x = (node.x * weight + cluster.x * cluster.hits) / total
	node.y = (node.y * weight + cluster.y * cluster.hits) / total
	node.weight = total
	node.accuracy = min(node.accuracy, Accuracy(cluster))
	node.lastSeen = now
	node.misses = 0
end

--- Envoi au groupe quand il est dû : première annonce, rafraîchissement (RESEND_INTERVAL), nouvel arrivant
--- (forceResend) ou position affinée de plus de RESEND_MOVE_YARDS. `minInterval` (survol) espace les renvois de
--- position : la souris qui parcourt un point déplace la moyenne à chaque lecture. Un renvoi trop proche du
--- précédent attend (resendPending) et part avec AutoDetect.FlushPendingResends.
local function SendIfDue(node, now, width, height, minInterval)
	local moved = node.lastSent ~= nil
		and Yards(width, height, node.sentX, node.sentY, node.x, node.y) >= AutoDetect.RESEND_MOVE_YARDS
	-- survol : l'espacement prime, même sur un renvoi demandé pour un nouveau membre
	if minInterval and node.lastSent and now - node.lastSent < minInterval then
		node.resendPending = moved or nil
		return
	end
	node.resendPending = nil
	if node.lastSent and not (forceResend or moved or now - node.lastSent >= AutoDetect.RESEND_INTERVAL) then
		return
	end
	-- un échec d'envoi n'est pas réessayé ici : la prochaine lecture de la ressource le refait
	local ok = ns.Sender.SendNode({
		id = node.id, source = "LIVE", kind = node.kind, state = node.sentOnce and "UPDATED" or "DETECTED",
		uiMapID = node.mapID, x = node.x, y = node.y, accuracy = node.accuracy, age = 0, resourceID = 0,
		name = node.name,
	})
	if ok then
		node.lastSent, node.sentX, node.sentY, node.sentOnce = now, node.x, node.y, true
	end
end

--- Marqueur local (jamais affiché sur sa propre minicarte, sauf réglage showOwnDetections), emplacement connu et
--- envoi au groupe.
local function Publish(node, sender, now, width, height, minInterval)
	ns.MarkerManager.Upsert({
		sender = sender, id = node.id, source = "LIVE", kind = node.kind,
		state = node.sentOnce and "UPDATED" or "DETECTED", uiMapID = node.mapID, x = node.x, y = node.y,
		accuracy = node.accuracy, name = node.name, isLocal = true,
	}, now)
	ns.KnownSpots.Record(node.kind, node.name, node.mapID, node.x, node.y, node.accuracy, true)
	SendIfDue(node, now, width, height, minInterval)
end

local function Gone(node, sender, label)
	ns.MarkerManager.Remove(sender, node.id, false)
	if node.sentOnce then
		ns.Sender.SendRemove(node.id, "GATHERED")
	end
	RemoveNode(node)
	AutoDetect.stats.gone = AutoDetect.stats.gone + 1
	ns.Diagnostics.Log("DETECT", "%s : %s, carte %d (%.2f, %.2f)", label or "disparu", node.name, node.mapID,
		node.x * 100, node.y * 100)
end

--- Vrai si la ressource se trouve dans la zone où son absence d'un balayage est fiable.
local function IsInsideReliableZone(node, context)
	return node.mapID == context.mapID and Yards(context.mapWidth, context.mapHeight, context.playerX,
		context.playerY, node.x, node.y) <= context.radius * AutoDetect.INSIDE_FACTOR
end

--- Ressources absentes de ce balayage alors qu'elles auraient dû y figurer. Un balayage qui n'a lu aucune
--- ressource ne retire pas une ressource vue seulement au survol : sur un client restreint, il ne voit plus rien.
local function CheckMisses(current, context, matched, sender)
	local missing = {}
	for id, node in pairs(nodes) do
		if not matched[id] and current.kinds[node.kind] and IsInsideReliableZone(node, context)
			and not (#current.hits == 0 and IsHoverOnly(node)) then
			node.misses = node.misses + 1
			if node.misses >= AutoDetect.MISS_LIMIT then
				missing[#missing + 1] = node
			end
		end
	end
	for _, node in ipairs(missing) do
		Gone(node, sender)
	end
	return #missing
end

---------------------------------------------------------------------------
-- Adaptation au client : balayage aveugle
---------------------------------------------------------------------------

local function CurrentBuild()
	return tostring(ns.Diagnostics.GetBuild().build)
end

local function SetBlind(value, reason)
	if blind == value then
		return
	end
	blind = value
	ns.Wipe(blindEvidence)
	if probeStorage then
		probeStorage.blindBuild = value and CurrentBuild() or nil
	end
	if value then
		ns.Diagnostics.Log("DETECT", "balayage aveugle (%s) : détection au survol seule, essai toutes les %d s",
			tostring(reason), AutoDetect.BLIND_RETRY_INTERVAL)
		if not blindNoticeShown then
			blindNoticeShown = true
			ns.Print(ns.T("AUTO_BLIND"))
		end
	else
		ns.Diagnostics.Log("DETECT", "balayage rétabli (%s)", tostring(reason))
		if not restoredNoticeShown then
			restoredNoticeShown = true
			ns.Print(ns.T("AUTO_RESTORED"))
		end
	end
	ns.Fire("PGR_DETECTION_MODE_CHANGED", value)
end

--- Vrai si une preuve existe déjà pour cette ressource (même nom, même endroit).
local function HasEvidence(node, width, height)
	for _, evidence in ipairs(blindEvidence) do
		if evidence.name == node.name and evidence.mapID == node.mapID
			and Yards(width, height, evidence.x, evidence.y, node.x, node.y) <= AutoDetect.EVIDENCE_SAME_YARDS then
			return true
		end
	end
	return false
end

--- Ressources survolées juste avant ce balayage, absentes de ce balayage qui n'a lu aucune ressource : le
--- balayage ne voit plus ce que le vrai curseur voit. Chaque survol est évalué une seule fois, par le premier
--- balayage complet qui suit, et seulement s'il date de moins de EVIDENCE_DELAY secondes. Un balayage qui
--- lit une ressource prouve que la sonde marche : les preuves sont alors effacées (voir Finish).
local function CheckHoverEvidence(current, context, matched, now)
	for i = #blindEvidence, 1, -1 do
		if now - blindEvidence[i].at > AutoDetect.EVIDENCE_WINDOW then
			table.remove(blindEvidence, i)
		end
	end
	for id, node in pairs(nodes) do
		if node.hoverPending then
			node.hoverPending = nil
			if #current.hits == 0 and not matched[id] and current.kinds[node.kind]
				and now - node.hoverAt <= AutoDetect.EVIDENCE_DELAY and IsInsideReliableZone(node, context)
				and not HasEvidence(node, context.mapWidth, context.mapHeight) then
				blindEvidence[#blindEvidence + 1] = { name = node.name, mapID = node.mapID, x = node.x, y = node.y,
					at = now }
				ns.Diagnostics.Log("DETECT", "balayage sans %s, pourtant vue au survol (%d/%d)", node.name,
					#blindEvidence, AutoDetect.BLIND_EVIDENCE)
			end
		end
	end
	if #blindEvidence >= AutoDetect.BLIND_EVIDENCE then
		SetBlind(true, format("%d ressource(s) survolée(s) absentes du balayage", #blindEvidence))
	end
end

--- Oublie les ressources dont le marqueur a expiré (plus revues depuis liveTTL + uncertainTTL).
local function PruneExpired(now)
	local limit = ns.Config.Get("liveTTL") + ns.Config.Get("uncertainTTL")
	local expired = {}
	for _, node in pairs(nodes) do
		if now - node.lastSeen > limit then
			expired[#expired + 1] = node
		end
	end
	for _, node in ipairs(expired) do
		RemoveNode(node)
	end
end

---------------------------------------------------------------------------
-- Balayage
---------------------------------------------------------------------------

local function NoteUnknown(name)
	if unknownNames[name] or unknownCount >= AutoDetect.UNKNOWN_LOG_LIMIT then
		return
	end
	unknownNames[name] = true
	unknownCount = unknownCount + 1
	ns.Diagnostics.Log("DETECT", "nom ignoré (ni herbe ni minerai connus) : %s", name)
end

local function StopFrame()
	if frame then
		frame:SetScript("OnUpdate", nil)
	end
end

--- Interrompt le balayage en cours (résultats partiels abandonnés). `probeFailure` : la sonde elle-même a
--- échoué (erreur, valeur secrète, API absente). Ces échecs répétés sont signalés une fois dans la discussion ;
--- les interruptions normales (combat, souris, minicarte masquée, changement de carte) ne le sont pas.
function AutoDetect.Abort(reason, probeFailure)
	if not pass then
		return
	end
	pass = nil
	StopFrame()
	AutoDetect.stats.aborted = AutoDetect.stats.aborted + 1
	AutoDetect.stats.lastAbort = tostring(reason)
	if not probeFailure then
		return
	end
	consecutiveFailures = consecutiveFailures + 1
	if consecutiveFailures >= AutoDetect.FAILURE_WARN_LIMIT and not failureWarned then
		failureWarned = true
		ns.Diagnostics.Log("DETECT", "%d balayages d'affilée en échec : %s", consecutiveFailures, tostring(reason))
		ns.Print(ns.T("AUTO_FAILING", consecutiveFailures, tostring(reason)))
	end
end

local function Finish()
	local current = pass
	pass = nil
	StopFrame()
	local now = ns.Now()
	local context = current.context
	local sender = ns.GetPlayerFullName()
	AutoDetect.stats.passes = AutoDetect.stats.passes + 1
	consecutiveFailures = 0
	if not context or not sender then
		return
	end
	if blind then
		-- retour seulement sur une lecture plausible : une ressource lue sur presque tous les points vient d'une
		-- infobulle restée figée, pas de la sonde
		local plausible = #current.hits > 0 and #current.hits <= #current.points * AutoDetect.RESTORE_MAX_SHARE
		if not plausible then
			-- toujours aveugle : rien à apprendre, aucune absence fiable ; aucune ressource visible à renvoyer à
			-- un nouveau membre (sans cette remise à zéro, chaque lecture au survol renverrait tout)
			for _, node in pairs(nodes) do
				node.hoverPending = nil
			end
			forceResend = false
			PruneExpired(now)
			return
		end
		SetBlind(false, format("%d point(s) de ressource lu(s) par le balayage", #current.hits))
	end
	local width, height = context.mapWidth, context.mapHeight
	local matched = {}
	for _, cluster in ipairs(AutoDetect.ClusterHits(current.hits, width, height)) do
		local node = FindNode(cluster, context.mapID, width, height)
		if node then
			UpdateNode(node, cluster, now)
		else
			node = CreateNode(cluster, context.mapID, now)
		end
		node.scanAt = now
		matched[node.id] = true
		Publish(node, sender, now, width, height)
	end
	forceResend = false
	if #current.hits > 0 then
		-- la sonde lit des ressources : les preuves passées d'un balayage aveugle ne tiennent plus
		ns.Wipe(blindEvidence)
	end
	CheckHoverEvidence(current, context, matched, now)
	local gone = CheckMisses(current, context, matched, sender)
	PruneExpired(now)
	if next(matched) or gone > 0 then
		ns.Fire("PGR_MARKERS_CHANGED")
	end
end

local function Step()
	local ok, reason = AutoDetect.CanScan()
	if not ok then
		return AutoDetect.Abort(reason)
	end
	local context, why = ns.Tracking.GetProjectionContext()
	if not context then
		return AutoDetect.Abort(why)
	end
	if context.mapID ~= pass.mapID then
		return AutoDetect.Abort("map")
	end
	local scale = Minimap:GetEffectiveScale()
	local centerX = Minimap:GetLeft() + Minimap:GetWidth() / 2
	local centerY = Minimap:GetBottom() + Minimap:GetHeight() / 2
	local points = pass.points
	local last = min(pass.index + AutoDetect.POINTS_PER_FRAME - 1, #points)
	local cursorOk, cursorErr = pcall(Minimap.SetUsingSoftCursor, Minimap, true)
	if not cursorOk then
		return AutoDetect.Abort(cursorErr, true)
	end
	local failure
	for i = pass.index, last do
		local point = points[i]
		local probeOk, names, readError = pcall(ns.Tracking.ProbePoint, point[1], point[2], scale, centerX, centerY)
		if not probeOk then
			failure = names
			break
		end
		if not names then
			failure = readError
			break
		end
		for _, name in ipairs(names) do
			local kind = ns.ResourceNames.Classify(name)
			if kind and pass.kinds[kind] then
				local _, x, y, yardsPerUnit = ns.Tracking.MinimapOffsetToMap(point[1], point[2], context)
				pass.hits[#pass.hits + 1] = { name = name, kind = kind, x = x, y = y, yardsPerUnit = yardsPerUnit }
			elseif not kind then
				NoteUnknown(name)
			end
		end
	end
	pcall(Minimap.SetUsingSoftCursor, Minimap, false)
	lastSoftCursorAt = ns.Now()
	if failure then
		return AutoDetect.Abort(failure, true)
	end
	pass.index = last + 1
	pass.context = context -- position du joueur à la fin du balayage : sert aux absences
	if pass.index > #points then
		Finish()
	end
end

local function OnUpdate()
	local ok, err = pcall(Step)
	if not ok then
		pcall(Minimap.SetUsingSoftCursor, Minimap, false)
		AutoDetect.Abort(err, true)
		ns.OnModuleError("AutoDetect", err)
	end
end

local missingApiWarned = false

--- Lance un balayage si les conditions sont réunies. Renvoie true s'il a démarré.
function AutoDetect.StartPass()
	if pass or not frame then
		return false
	end
	local canScan, why = AutoDetect.CanScan()
	if not canScan then
		-- sonde retirée du client : signalé une fois, aux personnages qui pistent quelque chose
		if why == "api" and not missingApiWarned and ActiveKinds() then
			missingApiWarned = true
			ns.Diagnostics.Log("DETECT", "fonctions de sondage absentes : détection au survol seule")
			ns.Print(ns.T("AUTO_NO_PROBE_API"))
		end
		return false
	end
	local kinds = ActiveKinds()
	if not kinds or not ns.GetPlayerFullName() then
		return false
	end
	local now = ns.Now()
	if blind then
		if not blindNoticeShown then
			-- état mémorisé pour ce build : rappel une fois par session
			blindNoticeShown = true
			ns.Print(ns.T("AUTO_BLIND_REMINDER"))
		end
		if lastPassStartedAt and now - lastPassStartedAt < AutoDetect.BLIND_RETRY_INTERVAL then
			return false
		end
	end
	local context = ns.Tracking.GetProjectionContext()
	if not context then
		return false
	end
	lastPassStartedAt = now
	pass = {
		kinds = kinds, mapID = context.mapID, index = 1, hits = {},
		points = ns.Tracking.BuildGrid(context.halfWidth, context.halfHeight, AutoDetect.GRID_SPACING),
	}
	frame:SetScript("OnUpdate", OnUpdate)
	return true
end

---------------------------------------------------------------------------
-- Survol : infobulle native sous le vrai curseur
---------------------------------------------------------------------------

local function FindNodeByKey(key, mapID)
	for _, node in pairs(nodes) do
		if node.key == key and node.mapID == mapID then
			return node
		end
	end
	return nil
end

--- Suit une ressource vue hors balayage et la partage, avec l'espacement des renvois du survol. `how` : "hover"
--- (sous le vrai curseur) ou "near" (cible d'interaction douce, à la position du joueur). `key` (facultatif) :
--- identifiant de l'objet (GUID de la cible douce). Le même objet reste une seule ressource, même vu de deux
--- côtés ; deux objets différents ne sont jamais fusionnés. Vue de près : plus précise que la position suivie,
--- elle la remplace ; moins précise, elle confirme la présence sans déplacer la ressource.
local function TrackSighting(cluster, mapID, now, how, sender, width, height, key)
	local node = key and FindNodeByKey(key, mapID)
	if not node then
		node = FindNode(cluster, mapID, width, height)
		if node and key and node.key and node.key ~= key then
			node = nil -- autre objet du même nom, tout près
		end
	end
	local accuracy = Accuracy(cluster)
	if not node then
		node = CreateNode(cluster, mapID, now, how)
	elseif how == "near" and accuracy > node.accuracy then
		node.lastSeen, node.misses = now, 0
	elseif how == "near" and accuracy < node.accuracy then
		-- le joueur est à moins de `accuracy` mètres de l'objet : la moyenne des vues plus lointaines est écartée
		node.x, node.y, node.weight, node.accuracy = cluster.x, cluster.y, cluster.hits, accuracy
		node.lastSeen, node.misses = now, 0
	else
		UpdateNode(node, cluster, now)
	end
	if key then
		node.key = key
	end
	if how == "hover" then
		node.hoverAt, node.hoverPending = now, true
	else
		node.nearAt = now
	end
	Publish(node, sender, now, width, height, AutoDetect.HOVER_RESEND_INTERVAL)
	return node
end

--- Décalage du curseur par rapport au centre de la minicarte, en unités du cadre, ou nil.
local function CursorOffset()
	if not GetCursorPosition then
		return nil
	end
	local cursorX, cursorY = GetCursorPosition()
	if ns.AnySecret(cursorX, cursorY) or type(cursorX) ~= "number" or type(cursorY) ~= "number" then
		return nil
	end
	local centerX, centerY = Minimap:GetCenter()
	if ns.AnySecret(centerX, centerY) or type(centerX) ~= "number" or type(centerY) ~= "number" then
		return nil
	end
	local scale = Minimap:GetEffectiveScale()
	return cursorX / scale - centerX, cursorY / scale - centerY
end

--- Lit l'infobulle de minicarte sous le vrai curseur et suit les herbes et minerais qu'elle nomme.
--- Renvoie le nombre de ressources lues.
function AutoDetect.ReadHover(now)
	if not ns.Config.Get("enabled") or not ns.Config.Get("autoDetect") then
		return 0
	end
	if not (Minimap and Minimap:IsVisible() and Minimap:IsMouseOver()) or ns.Tracking.IsScanRunning() then
		return 0
	end
	if InCombatLockdown and InCombatLockdown() then
		return 0
	end
	-- juste après un balayage, l'infobulle peut encore nommer le dernier point sondé, pas celui du curseur
	if pass or (lastSoftCursorAt and now - lastSoftCursorAt < 0.5) then
		return 0
	end
	if AutoDetect.IsAddOnRestricted() then
		return 0
	end
	local kinds = ActiveKinds()
	local sender = ns.GetPlayerFullName()
	if not kinds or not sender then
		return 0
	end
	local names = ns.Tracking.ReadMinimapMouseover()
	if not names or #names == 0 then
		return 0
	end
	local found = {}
	for _, name in ipairs(names) do
		local kind = ns.ResourceNames.Classify(name)
		if kind then
			if kinds[kind] then
				found[#found + 1] = { name = name, kind = kind }
			end
		else
			NoteUnknown(name)
		end
	end
	if #found == 0 then
		return 0
	end
	local context = ns.Tracking.GetProjectionContext()
	local dx, dy = CursorOffset()
	if not context or not dx then
		return 0
	end
	local limit = min(context.halfWidth, context.halfHeight)
	if dx * dx + dy * dy > limit * limit then
		return 0
	end
	local _, x, y, yardsPerUnit = ns.Tracking.MinimapOffsetToMap(dx, dy, context)
	local width, height = context.mapWidth, context.mapHeight
	for _, item in ipairs(found) do
		local cluster = { name = item.name, kind = item.kind, x = x, y = y, hits = 1, spread = 0,
			yardsPerUnit = yardsPerUnit }
		TrackSighting(cluster, context.mapID, now, "hover", sender, width, height)
	end
	ns.Fire("PGR_MARKERS_CHANGED")
	return #found
end

--- Vrai si une vue de près désigne une herbe cueillie à l'instant. La cible douce désigne encore la plante le temps
--- qu'elle disparaisse (constaté en jeu le 2026-11-09 : revue 0,3 s après la cueillette) ; la signaler la ferait
--- réapparaître chez les autres et lèverait la marque « récolté » de l'emplacement. Même objet si les deux GUID
--- sont connus ; sinon même nom, à portée de l'endroit de la cueillette.
local function JustGathered(name, mapID, x, y, accuracy, key, now, width, height)
	local normalized = ns.ResourceNames.Normalize(name)
	for _, gathered in ipairs(recentGathers) do
		if now - gathered.at < AutoDetect.GATHERED_IGNORE_SECONDS and gathered.mapID == mapID then
			local same
			if key and gathered.key then
				same = key == gathered.key
			else
				same = gathered.name == normalized
					and Yards(width, height, x, y, gathered.x, gathered.y) <= accuracy + AutoDetect.GATHER_ACCURACY
			end
			if same then
				if not gathered.logged then
					gathered.logged = true
					ns.Diagnostics.Log("DETECT", "proximité : %s ignorée, cueillie à l'instant", name)
				end
				return true
			end
		end
	end
	return false
end

--- Ressource vue sans souris par la cible d'interaction douce du jeu (Detection/Proximity.lua) : suivie et
--- partagée comme une ressource survolée. (x, y) : position du joueur ; `accuracy` : distance maximale de la
--- ressource, en mètres ; `key` : identifiant de l'objet (GUID). Le pistage n'est pas nécessaire : la cible douce
--- voit l'objet lui-même. Renvoie true si la ressource a été prise en compte.
function AutoDetect.ReportNearby(name, kind, mapID, x, y, accuracy, now, key)
	if not ns.Config.Get("enabled") or not ns.Config.Get("autoDetect") then
		return false
	end
	if (InCombatLockdown and InCombatLockdown()) or AutoDetect.IsAddOnRestricted() then
		return false
	end
	local sender = ns.GetPlayerFullName()
	local width, height = ns.Coordinates.GetMapSizeYards(mapID)
	if not sender or not width or (kind ~= "HERB" and kind ~= "ORE") then
		return false
	end
	if kind == "HERB" and JustGathered(name, mapID, x, y, accuracy, key, now, width, height) then
		return false
	end
	-- yardsPerUnit = 0 : rapprochement avec une ressource suivie à MATCH_MIN_YARDS, précision = accuracy
	local cluster = { name = name, kind = kind, x = x, y = y, hits = 1, spread = accuracy, yardsPerUnit = 0 }
	TrackSighting(cluster, mapID, now, "near", sender, width, height, key)
	ns.Fire("PGR_MARKERS_CHANGED")
	return true
end

--- Envoie les positions affinées au survol restées en attente, une fois HOVER_RESEND_INTERVAL écoulé depuis
--- le dernier envoi. La dernière position part aussi quand la souris a déjà quitté le point.
function AutoDetect.FlushPendingResends(now)
	if not ns.Config.Get("enabled") or not ns.Config.Get("autoDetect") then
		return
	end
	if (InCombatLockdown and InCombatLockdown()) or AutoDetect.IsAddOnRestricted() then
		return
	end
	for _, node in pairs(nodes) do
		if node.resendPending and now - node.lastSent >= AutoDetect.HOVER_RESEND_INTERVAL then
			local width, height = ns.Coordinates.GetMapSizeYards(node.mapID)
			if width then
				SendIfDue(node, now, width, height, AutoDetect.HOVER_RESEND_INTERVAL)
			else
				node.resendPending = nil
			end
		end
	end
end

---------------------------------------------------------------------------
-- Récolte : herbe retirée dès qu'elle est cueillie
---------------------------------------------------------------------------

--- Retire l'herbe `name` suivie la plus proche du joueur (au plus GATHER_RADIUS mètres). Renvoie la ressource
--- retirée, ou nil.
local function RemoveGathered(name)
	local mapID, playerX, playerY = ns.Coordinates.GetPlayerMapPosition()
	local sender = ns.GetPlayerFullName()
	if not mapID or not sender then
		return nil
	end
	local width, height = ns.Coordinates.GetMapSizeYards(mapID)
	if not width then
		return nil
	end
	local key = ns.ResourceNames.Normalize(name)
	local best, bestDistance
	for _, node in pairs(nodes) do
		if node.kind == "HERB" and node.mapID == mapID and ns.ResourceNames.Normalize(node.name) == key then
			local distance = Yards(width, height, playerX, playerY, node.x, node.y)
			if distance <= AutoDetect.GATHER_RADIUS and (not bestDistance or distance < bestDistance) then
				best, bestDistance = node, distance
			end
		end
	end
	if not best then
		return nil
	end
	Gone(best, sender, "récoltée")
	AutoDetect.stats.gathered = AutoDetect.stats.gathered + 1
	ns.Fire("PGR_MARKERS_CHANGED")
	return best
end

--- Herbe cueillie à la position du joueur : gardée GATHERED_IGNORE_SECONDS secondes (JustGathered). `key` : GUID
--- de la ressource retirée, s'il est connu.
local function NoteGathered(name, key, now)
	for index = #recentGathers, 1, -1 do
		if now - recentGathers[index].at >= AutoDetect.GATHERED_IGNORE_SECONDS then
			table.remove(recentGathers, index)
		end
	end
	local mapID, x, y = ns.Coordinates.GetPlayerMapPosition()
	if mapID then
		recentGathers[#recentGathers + 1] = {
			name = ns.ResourceNames.Normalize(name), mapID = mapID, x = x, y = y, at = now, key = key,
		}
	end
end

---------------------------------------------------------------------------
-- Apprentissage des noms à la récolte
---------------------------------------------------------------------------

local function GatherKind(spellID)
	local kind = GATHER_SPELLS[spellID]
	if kind then
		return kind
	end
	-- autres rangs ou identifiants propres à Forever : comparaison avec le nom localisé du sort
	if C_Spell and C_Spell.GetSpellName then
		local name = C_Spell.GetSpellName(spellID)
		if type(name) == "string" and not ns.IsSecret(name) then
			local herbName, miningName = C_Spell.GetSpellName(HERB_GATHERING_SPELL), C_Spell.GetSpellName(MINING_SPELL)
			if not ns.IsSecret(herbName) and name == herbName then
				return "HERB"
			elseif not ns.IsSecret(miningName) and name == miningName then
				return "ORE"
			end
		end
	end
	return nil
end

local function OnSpellcastSent(_, unit, target, castGUID, spellID)
	if ns.AnySecret(unit, target, castGUID, spellID) or unit ~= "player" or type(target) ~= "string"
		or target == "" then
		return
	end
	local kind = GatherKind(spellID)
	if not kind then
		return
	end
	lastGather = { castGUID = castGUID, kind = kind, name = target }
	if ns.ResourceNames.Learn(kind, target) then
		ns.Diagnostics.Log("DETECT", "nom appris à la récolte : %s (%s)", target, kind == "HERB" and "herbe" or "minerai")
	end
end

--- Récolte réussie : l'endroit devient un emplacement connu (le joueur est à portée de la ressource), même sans
--- pistage, marqué récolté (pas affiché tout de suite à la place de la ressource). L'herbe cueillie disparaît de
--- la minicarte : elle est retirée sans attendre un balayage (indispensable quand le balayage est aveugle). Un
--- filon peut rester après un minage : il n'est pas retiré, et une nouvelle vue lève la marque.
local function OnSpellcastSucceeded(_, unit, castGUID)
	if ns.AnySecret(unit, castGUID) or unit ~= "player" or not lastGather or lastGather.castGUID ~= castGUID then
		return
	end
	local gather = lastGather
	lastGather = nil
	if ns.Config.Get("enabled") then
		local mapID, x, y = ns.Coordinates.GetPlayerMapPosition()
		if mapID and ns.KnownSpots.Record(gather.kind, gather.name, mapID, x, y, AutoDetect.GATHER_ACCURACY, true) then
			ns.KnownSpots.MarkGathered(gather.kind, mapID, x, y, AutoDetect.GATHER_ACCURACY)
			ns.Diagnostics.Log("DETECT", "emplacement de récolte : %s, carte %d (%.2f, %.2f)", gather.name, mapID,
				x * 100, y * 100)
		end
	end
	if gather.kind == "HERB" then
		local removed = RemoveGathered(gather.name)
		NoteGathered(gather.name, removed and removed.key, ns.Now())
	end
end

---------------------------------------------------------------------------
-- Diagnostics et accès
---------------------------------------------------------------------------

function AutoDetect.GetNodeCount()
	return nodeCount
end

function AutoDetect.IsRunning()
	return pass ~= nil
end

--- Vrai si le balayage est déclaré aveugle (client restreint) : détection au survol seule.
function AutoDetect.IsProbeBlind()
	return blind
end

--- Résumé pour /pgr status et /pgr diag.
function AutoDetect.Describe()
	local stats = AutoDetect.stats
	return format("mode %s, %d balayage(s), %d interrompu(s)%s, %d ressource(s) suivie(s), %d trouvée(s) dont %d "
		.. "au survol et %d de près, %d disparue(s) dont %d récoltée(s), %d nom(s) ignoré(s)",
		blind and "survol (balayage aveugle)" or "balayage et survol", stats.passes, stats.aborted,
		stats.lastAbort and (" (dernier : " .. stats.lastAbort .. ")") or "", nodeCount, stats.found, stats.hovered,
		stats.near, stats.gone, stats.gathered, unknownCount)
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

ns.On("PGR_CONFIG_LOADED", "AutoDetect", function()
	if frame then
		return
	end
	frame = CreateFrame("Frame")
	-- identifiants uniques d'une session à l'autre (un /reload ne réutilise pas ceux d'avant)
	sessionTag = format("%x", floor(ns.Now() * 10) % 65536)
	-- balayage aveugle mémorisé pour ce build du client ; un nouveau build est réévalué
	if type(ns.db.probe) ~= "table" then
		ns.db.probe = {}
	end
	probeStorage = ns.db.probe
	local blindBuild = probeStorage.blindBuild
	if blindBuild ~= nil and tostring(blindBuild) == CurrentBuild() then
		blind = true
		ns.Diagnostics.Log("DETECT", "balayage aveugle sur le build %s (mémorisé) : détection au survol seule",
			tostring(blindBuild))
	elseif blindBuild ~= nil then
		probeStorage.blindBuild = nil
		ns.Diagnostics.Log("DETECT", "nouveau build %s (aveugle sur %s) : balayage réévalué", CurrentBuild(),
			tostring(blindBuild))
	end
	ns.NewTicker(AutoDetect.PASS_INTERVAL, "AutoDetect", AutoDetect.StartPass)
	ns.NewTicker(AutoDetect.HOVER_INTERVAL, "AutoDetect", function()
		local now = ns.Now()
		AutoDetect.ReadHover(now)
		AutoDetect.FlushPendingResends(now)
	end)
	ns.RegisterEvent("UNIT_SPELLCAST_SENT", "AutoDetect", OnSpellcastSent)
	ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "AutoDetect", OnSpellcastSucceeded)
end)

ns.On("PGR_SETTING_CHANGED", "AutoDetect", function(_, key, value)
	if (key == "autoDetect" or key == "enabled") and not value then
		AutoDetect.Abort("disabled")
	end
end)

-- nouveau membre ou retour d'un membre : nos ressources visibles lui sont renvoyées au prochain balayage
ns.On("PGR_PEERS_CHANGED", "AutoDetect", function()
	forceResend = true
end)
