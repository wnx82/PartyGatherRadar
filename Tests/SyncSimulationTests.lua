-- PartyGatherRadar - Tests/SyncSimulationTests.lua
-- Simulation hors jeu de plusieurs clients PartyGatherRadar reliés par un faux réseau de messages
-- d'addon (voir Harness.lua). Reprend les scénarios de Tests/TestPlan.md réalisables sans client WoW.
-- RAPPEL : ces tests valident la logique de l'addon contre des bouchons, pas le comportement du jeu.

return function(H, root)
	local function NewPair(optsA, optsB)
		local world = H.NewWorld(root)
		local a = world:NewClient(optsA or { name = "Aekiss", tracking = { H.HERB_TRACKING, H.ORE_TRACKING } })
		local b = world:NewClient(optsB or { name = "Aedot" })
		a:Login(false)
		b:Login(false)
		return world, a, b
	end

	local function Grouped(optsA, optsB)
		local world, a, b = NewPair(optsA, optsB)
		world:SetGroup({ a, b })
		world:Advance(3)
		return world, a, b
	end

	local function VisiblePins(client)
		local pins = {}
		for _, frame in ipairs(client.frames) do
			-- icônes de marqueurs : boutons anonymes de la minicarte (le bouton de l'addon est nommé)
			if frame.frameType == "Button" and frame.parent == client.env.Minimap and not frame.name
				and frame.shown and frame.point then
				pins[#pins + 1] = frame
			end
		end
		return pins
	end

	local function Status(client, sender, id, isTest)
		local marker = client.ns.MarkerManager.Get(sender, id, isTest)
		return marker and client.ns.MarkerManager.GetStatus(marker, client.world.time) or nil
	end

	local function SendLive(client, id, x, y, extra)
		local node = { id = id, source = "LIVE", kind = "HERB", state = "DETECTED", uiMapID = 1429, x = x, y = y,
			accuracy = 5, age = 0, resourceID = 0, name = "Pacifique" }
		for k, v in pairs(extra or {}) do
			node[k] = v
		end
		return client.ns.Sender.SendNode(node)
	end

	local function NoErrors(client)
		local lastError = client.ns.Diagnostics.lastError
		H.eq(lastError and (lastError.source .. " : " .. lastError.message) or nil, nil, client.name .. " : erreur Lua")
	end

	---------------------------------------------------------------------------
	H.suite("Scénario 1 : HELLO et découverte mutuelle")
	---------------------------------------------------------------------------

	H.test("deux clients groupés se découvrent, versions compatibles", function()
		local world, a, b = Grouped()
		local peersA, peersB = a.ns.GroupSync.GetPeers(), b.ns.GroupSync.GetPeers()
		H.eq(#peersA, 1)
		H.eq(peersA[1].name, "Aedot-Realm")
		H.eq(peersA[1].peer.compatible, true)
		H.eq(peersA[1].peer.addonVersion, "0.5.0")
		H.eq(#peersB, 1)
		H.eq(peersB[1].name, "Aekiss-Realm")
		H.ok(a:ChatContains("Aedot utilise PartyGatherRadar 0.5.0"), "annonce de découverte")
		H.eq(peersA[1].peer.messages, #b.sent, "un message compté une seule fois")
		H.ok(#a.sent <= 2 and #b.sent <= 2, "au plus un HELLO et une réponse par client")
		local before = #a.sent + #b.sent
		world:Advance(120)
		H.eq(#a.sent + #b.sent, before, "aucun message périodique inutile")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("tous les messages restent sous 255 octets et sur un canal de groupe", function()
		local _, a = Grouped()
		for _, message in ipairs(a.sent) do
			H.ok(#message.text <= 255, "taille")
			H.eq(message.channel, "PARTY")
			H.eq(message.prefix, "PGRadar")
		end
	end)

	---------------------------------------------------------------------------
	H.suite("Scénario 2 : capacités annoncées")
	---------------------------------------------------------------------------

	H.test("Aekiss annonce Herboristerie, Aedot non", function()
		local _, a, b = Grouped()
		local aekissSeenByB = b.ns.GroupSync.DecodeCaps(b.ns.GroupSync.GetPeers()[1].peer.caps)
		local aedotSeenByA = a.ns.GroupSync.DecodeCaps(a.ns.GroupSync.GetPeers()[1].peer.caps)
		H.eq(aekissSeenByB.HERB_TRACKING, true)
		H.eq(aekissSeenByB.ORE_TRACKING, true)
		H.eq(aedotSeenByA.HERB_TRACKING, false)
		H.eq(aedotSeenByA.SHARE, true)
		H.eq(aedotSeenByA.RECEIVE, true)
	end)

	---------------------------------------------------------------------------
	H.suite("Scénario 3 : transmission et affichage chez l'autre joueur")
	---------------------------------------------------------------------------

	H.test("/pgr test : marqueur TEST local, PING/PONG, marqueur TEST reçu", function()
		local world, a, b = Grouped()
		a:Slash("test")
		world:Advance(0.5)
		local realA, testA = a.ns.MarkerManager.Count()
		local realB, testB = b.ns.MarkerManager.Count()
		H.eq(realA, 0, "aucune donnée réelle chez Aekiss")
		H.eq(testA, 1)
		H.eq(realB, 0, "aucune donnée réelle chez Aedot")
		H.eq(testB, 1, "marqueur TEST reçu")
		-- 15 m est / 15 m nord, rayon 233,333 m pour 70 unités : 4,5 unités
		local pinsB = VisiblePins(b)
		H.eq(#pinsB, 1, "une icône chez Aedot")
		H.near(pinsB[1].point.x, 4.5, 0.01, "x de l'icône")
		H.near(pinsB[1].point.y, 4.5, 0.01, "y de l'icône")
		world:Advance(5)
		H.ok(a:ChatContains("PONG reçu de Aedot"), "PONG reçu")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("une détection LIVE envoyée par Aekiss s'affiche chez Aedot à la bonne position", function()
		local world, a, b = Grouped()
		H.ok(SendLive(a, "n1", 0.51, 0.5), "envoi accepté")
		world:Advance(0.5)
		H.eq(Status(b, "Aekiss-Realm", "n1"), "ACTIVE")
		local pins = VisiblePins(b)
		H.eq(#pins, 1)
		H.near(pins[1].point.x, 0.01 * 3470 * 70 / 233.333, 0.01, "34,7 m à l'est")
		H.near(pins[1].point.y, 0, 0.01)
		H.eq(VisiblePins(a)[1], nil, "l'émetteur ne s'affiche pas son propre envoi réseau")
	end)

	H.test("un marqueur hors du rayon de la minicarte n'est pas affiché", function()
		local world, a, b = Grouped()
		SendLive(a, "far", 0.6, 0.5) -- 347 m
		world:Advance(0.5)
		H.eq(Status(b, "Aekiss-Realm", "far"), "ACTIVE")
		H.eq(#VisiblePins(b), 0)
	end)

	H.test("une ressource d'un autre continent n'est jamais affichée", function()
		local world, a, b = Grouped(nil, { name = "Aedot", mapID = 1411 })
		SendLive(a, "n1", 0.5, 0.5)
		world:Advance(0.5)
		H.eq(Status(b, "Aekiss-Realm", "n1"), "ACTIVE", "marqueur conservé")
		H.eq(#VisiblePins(b), 0, "mais pas affiché sur Durotar")
	end)

	H.test("réception désactivée : rien n'est affiché", function()
		local world, a, b = Grouped()
		b:Slash("receive off")
		SendLive(a, "n1", 0.51, 0.5)
		world:Advance(0.5)
		H.eq(b.ns.MarkerManager.Count(), 0)
	end)

	---------------------------------------------------------------------------
	H.suite("Scénario 4 : vieillissement des détections")
	---------------------------------------------------------------------------

	H.test("récente, puis incertaine, puis supprimée", function()
		local world, a, b = Grouped()
		SendLive(a, "n1", 0.51, 0.5)
		world:Advance(1)
		H.eq(Status(b, "Aekiss-Realm", "n1"), "ACTIVE")
		world:Advance(61)
		H.eq(Status(b, "Aekiss-Realm", "n1"), "UNCERTAIN")
		H.eq(#VisiblePins(b), 1, "un point incertain reste affiché (en gris)")
		world:Advance(240)
		H.eq(b.ns.MarkerManager.Count(), 0, "supprimé après la durée d'incertitude")
		-- 0.5.0 : l'endroit reste un emplacement connu, affiché en discret (présence non confirmée)
		local pins = VisiblePins(b)
		H.eq(#pins, 1, "emplacement connu affiché à la place de la détection")
		H.ok(pins[1].spot ~= nil and pins[1].status == "HISTORY", "marqueur d'emplacement connu")
		b.ns.Config.Set("showHistory", false)
		world:Advance(1.1)
		H.eq(#VisiblePins(b), 0, "emplacements connus masqués par leur réglage")
	end)

	H.test("une mise à jour renouvelle la détection", function()
		local world, a, b = Grouped()
		SendLive(a, "n1", 0.51, 0.5)
		world:Advance(50)
		SendLive(a, "n1", 0.51, 0.5, { state = "UPDATED" })
		world:Advance(20)
		H.eq(Status(b, "Aekiss-Realm", "n1"), "ACTIVE")
	end)

	---------------------------------------------------------------------------
	H.suite("Scénario 5 : disparition confirmée")
	---------------------------------------------------------------------------

	H.test("REMOVE (récoltée) retire le marqueur chez les autres", function()
		local world, a, b = Grouped()
		SendLive(a, "n1", 0.51, 0.5)
		world:Advance(0.5)
		a.ns.Sender.SendRemove("n1", "GATHERED")
		world:Advance(0.5)
		H.eq(b.ns.MarkerManager.Count(), 0)
	end)

	---------------------------------------------------------------------------
	H.suite("Scénario 6 : départ du groupe")
	---------------------------------------------------------------------------

	H.test("le départ nettoie pairs et marqueurs des deux côtés", function()
		local world, a, b = Grouped()
		SendLive(a, "n1", 0.51, 0.5)
		SendLive(b, "m1", 0.49, 0.5)
		world:Advance(1)
		H.eq(a.ns.MarkerManager.Count(), 1)
		H.eq(b.ns.MarkerManager.Count(), 1)
		world:SetGroup({ a })
		world:Advance(1)
		H.eq(#a.ns.GroupSync.GetPeers(), 0)
		H.eq(#b.ns.GroupSync.GetPeers(), 0)
		H.eq(a.ns.MarkerManager.Count(), 0, "marqueurs d'Aedot retirés chez Aekiss")
		H.eq(b.ns.MarkerManager.Count(), 0, "marqueurs d'Aekiss retirés chez Aedot")
		local ok, reason = SendLive(a, "n2", 0.5, 0.5)
		H.eq(ok, false)
		H.eq(reason, "nogroup")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("un membre qui quitte un groupe de trois est seul oublié", function()
		local world = H.NewWorld(root)
		local a = world:NewClient({ name = "Aekiss" })
		local b = world:NewClient({ name = "Aedot" })
		local c = world:NewClient({ name = "Aelin" })
		a:Login(false)
		b:Login(false)
		c:Login(false)
		world:SetGroup({ a, b, c })
		world:Advance(3)
		H.eq(#a.ns.GroupSync.GetPeers(), 2)
		SendLive(c, "c1", 0.51, 0.5)
		SendLive(b, "b1", 0.49, 0.5)
		world:Advance(1)
		world:SetGroup({ a, b })
		world:Advance(1)
		H.eq(#a.ns.GroupSync.GetPeers(), 1)
		H.eq(a.ns.MarkerManager.Get("Aelin-Realm", "c1"), nil)
		H.ok(a.ns.MarkerManager.Get("Aedot-Realm", "b1"), "marqueur d'Aedot conservé")
	end)

	H.test("arrêt du partage : BYE et retrait des marqueurs chez les autres", function()
		local world, a, b = Grouped()
		SendLive(a, "n1", 0.51, 0.5)
		world:Advance(0.5)
		a:Slash("share off")
		world:Advance(0.5)
		H.eq(b.ns.MarkerManager.Count(), 0)
		H.eq(b.ns.GroupSync.GetPeers()[1].peer.sharing, false)
		local ok, reason = SendLive(a, "n2", 0.5, 0.5)
		H.eq(ok, false)
		H.eq(reason, "sharing_disabled")
	end)

	---------------------------------------------------------------------------
	H.suite("Scénario 7 : /reload")
	---------------------------------------------------------------------------

	H.test("réglages conservés, nouvelle découverte, aucune erreur", function()
		local world, a, b = Grouped()
		b.ns.Config.Set("iconSize", 20)
		b.ns.Config.Set("debug", true)
		b:Reload()
		world:Advance(8) -- réponse HELLO éventuellement différée (au plus une toutes les 5 s)
		H.eq(b.ns.Config.Get("iconSize"), 20)
		H.eq(b.ns.Config.Get("debug"), true)
		H.eq(#b.ns.GroupSync.GetPeers(), 1, "Aekiss redécouvert après le rechargement")
		H.ok(#b.env.PartyGatherRadarDB.diagnostics.log > 0, "journal sauvegardé en mode diagnostic")
		H.eq(#b:UnexpectedGlobals(), 0)
		NoErrors(a)
		NoErrors(b)
	end)

	---------------------------------------------------------------------------
	H.suite("Scénario 8 : membre sans l'addon")
	---------------------------------------------------------------------------

	H.test("aucune erreur, aucun faux pair, PING sans réponse", function()
		local world, a, bob = NewPair(nil, { name = "Bob", hasAddon = false })
		world:SetGroup({ a, bob })
		world:Advance(3)
		H.eq(#a.ns.GroupSync.GetPeers(), 0)
		a:Slash("peers")
		H.ok(a:ChatContains("membres sans addon détecté : Bob"), "Bob listé sans addon")
		a:Slash("test")
		world:Advance(6)
		H.ok(a:ChatContains("aucun PONG reçu"), "absence de réponse signalée")
		NoErrors(a)
	end)

	---------------------------------------------------------------------------
	H.suite("Sécurité : vérification stricte des messages reçus")
	---------------------------------------------------------------------------

	H.test("émetteur hors groupe, canal non autorisé, valeur secrète, écho", function()
		local _, a = Grouped()
		local D = a.ns.Diagnostics
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;B", "PARTY", "Intrus-Realm")
		H.eq(D.rejectReasons.not_in_group, 1)
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;B", "WHISPER", "Aedot-Realm")
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;B", "GUILD", "Aedot-Realm")
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;B", "CHANNEL", "Aedot-Realm")
		H.eq(D.rejectReasons.channel, 3)
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", H.SECRET, "PARTY", "Aedot-Realm")
		H.eq(D.rejectReasons.secret, 1)
		local echoes = D.counters.echoes
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;B", "PARTY", "Aekiss-Realm")
		H.eq(D.counters.echoes, echoes + 1)
		a:FireEvent("CHAT_MSG_ADDON", "AutrePrefixe", "n'importe quoi", "PARTY", "Aedot-Realm")
		a:FireEvent("CHAT_MSG_ADDON", H.SECRET, "x", "PARTY", "Aedot-Realm")
		H.eq(a.ns.GroupSync.GetPeers()[1].peer.sharing, true, "aucun BYE accepté")
		NoErrors(a)
	end)

	H.test("messages malformés d'un membre : rejetés sans erreur ni marqueur", function()
		local _, a = Grouped()
		local D = a.ns.Diagnostics
		for _, text in ipairs({ "1;N;garbage", "", "1;N;a;L;H;D;1429;999999;1;0;0;0;x", "1;Z", ";;;;", "1;H" }) do
			a:FireEvent("CHAT_MSG_ADDON", "PGRadar", text, "PARTY", "Aedot-Realm")
		end
		H.eq(a.ns.MarkerManager.Count(), 0)
		H.ok(D.counters.rejected >= 6, "rejets comptés")
		NoErrors(a)
	end)

	H.test("nom de membre secret : identité invérifiable, message rejeté", function()
		local world, a, b = NewPair()
		b.secretName = true
		world:SetGroup({ a, b })
		world:Advance(3)
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;B", "PARTY", "Aedot-Realm")
		H.ok((a.ns.Diagnostics.rejectReasons.not_in_group or 0) >= 1, "rejet")
		NoErrors(a)
	end)

	H.test("version de protocole plus récente : pair signalé incompatible", function()
		local _, a = Grouped()
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "2;N;a;L;H;D;1429;1;1;0;0;0;x", "PARTY", "Aedot-Realm")
		H.eq(a.ns.GroupSync.GetPeers()[1].peer.compatible, false)
		H.ok(a:ChatContains("version de protocole non prise en charge"), "avertissement affiché")
		H.eq(a.ns.MarkerManager.Count(), 0)
	end)

	---------------------------------------------------------------------------
	H.suite("Envoi : canal, limitation, verrouillage")
	---------------------------------------------------------------------------

	H.test("canal RAID en raid, PARTY (sous-groupe) si l'option raid est désactivée", function()
		local world = H.NewWorld(root)
		local a = world:NewClient({ name = "Aekiss" })
		local b = world:NewClient({ name = "Aedot" })
		a:Login(false)
		b:Login(false)
		world:SetGroup({ a, b }, true)
		world:Advance(3)
		H.eq(a.sent[#a.sent].channel, "RAID")
		H.eq(a.ns.Sender.GetChannel(), "RAID")
		a.ns.Config.Set("allowRaid", false)
		H.eq(a.ns.Sender.GetChannel(), "PARTY")
	end)

	H.test("limitation du serveur : message conservé puis renvoyé", function()
		local world, a = Grouped()
		local D = a.ns.Diagnostics
		a.sendResult = 3
		a.ns.Sender.SendPing("abc", false)
		H.eq(a.ns.Sender.GetQueueLength(), 1)
		H.eq(D.counters.throttled, 1)
		a.sendResult = nil
		world:Advance(3)
		H.eq(a.ns.Sender.GetQueueLength(), 0)
		H.ok(a.sent[#a.sent].text:find(";P;abc", 1, true), "PING finalement envoyé")
	end)

	H.test("verrouillage de la messagerie : pause puis reprise à la levée de la restriction", function()
		local world, a = Grouped()
		a.sendResult = 11
		a.ns.Sender.SendPing("abc", false)
		H.eq(a.ns.Diagnostics.counters.lockdown, 1)
		H.eq(a.ns.Sender.IsPaused(), true)
		a.sendResult = nil
		a:FireEvent("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
		world:Advance(0.5)
		H.eq(a.ns.Sender.GetQueueLength(), 0)
	end)

	H.test("file bornée et regroupement des mises à jour", function()
		local world, a = Grouped()
		a.sendResult = 3 -- bloque l'envoi pour remplir la file
		for i = 1, 40 do
			SendLive(a, "n" .. i, 0.5, 0.5)
		end
		H.ok(a.ns.Sender.GetQueueLength() <= 30, "file bornée à 30")
		H.ok(a.ns.Diagnostics.counters.dropped >= 10, "abandons comptés")
		local length = a.ns.Sender.GetQueueLength()
		SendLive(a, "n40", 0.6, 0.5, { state = "UPDATED" })
		H.eq(a.ns.Sender.GetQueueLength(), length, "mise à jour regroupée avec la version en attente")
		a.sendResult = nil
		world:Advance(60)
		H.eq(a.ns.Sender.GetQueueLength(), 0)
	end)

	---------------------------------------------------------------------------
	H.suite("Robustesse")
	---------------------------------------------------------------------------

	H.test("un module en erreur est désactivé, les autres continuent", function()
		local world, a, b = Grouped()
		a.env.Minimap.GetWidth = function() error("panne simulée") end
		SendLive(b, "b1", 0.51, 0.5)
		world:Advance(2)
		H.eq(a.ns.modules.MinimapOverlay.enabled, false, "affichage désactivé")
		H.ok(a:ChatContains("MinimapOverlay"), "désactivation signalée")
		SendLive(b, "b2", 0.52, 0.5)
		world:Advance(0.5)
		H.ok(a.ns.MarkerManager.Get("Aedot-Realm", "b2"), "la réception fonctionne toujours")
	end)

	H.test("toutes les commandes /pgr s'exécutent sans erreur", function()
		local world, a = Grouped()
		for _, command in ipairs({ "", "help", "status", "version", "diag", "peers", "debug", "debug", "log 5",
			"clear", "clear log", "probe", "probe tracking", "probe vignettes", "probe minimap", "probe minimap",
			"minimap off", "minimap on", "spots", "spots clear", "near on", "near off", "quiet off", "quiet on", "inconnue", "off", "on" }) do
			a:Slash(command)
			world:Advance(0.1)
		end
		NoErrors(a)
		H.ok(a:ChatContains("commande inconnue"), "commande inconnue signalée")
		H.eq(#a:UnexpectedGlobals(), 0)
	end)

	H.test("client anglais : textes anglais, aucune clé brute affichée", function()
		local world = H.NewWorld(root)
		local a = world:NewClient({ name = "Aekiss", locale = "enUS" })
		a:Login(false)
		a:Slash("status")
		H.ok(a:ChatContains("sharing:"), "texte anglais")
		for _, line in ipairs(a.chat) do
			H.ok(not line:find("[%u][%u_]+[%u]_[%u]"), "clé non traduite : " .. line)
		end
	end)


	---------------------------------------------------------------------------
	H.suite("Messages hostiles ou répétés (revue de code)")
	---------------------------------------------------------------------------

	H.test("carte inconnue et sources non prises en charge rejetées", function()
		local _, a = Grouped()
		local D = a.ns.Diagnostics
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;N;a;L;H;D;9999999;50000;50000;0;0;0;x", "PARTY", "Aedot-Realm")
		H.eq(D.rejectReasons.unknown_map, 1)
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;N;b;H;H;D;1429;50000;50000;0;0;0;x", "PARTY", "Aedot-Realm")
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;N;c;M;H;D;1429;50000;50000;0;0;0;x", "PARTY", "Aedot-Realm")
		H.eq(D.rejectReasons.source_not_supported, 2)
		H.eq(a.ns.MarkerManager.Count(), 0)
		NoErrors(a)
	end)

	H.test("flot de PING : au plus un PONG par pair toutes les 2 s", function()
		local world, a = Grouped()
		local before = #a.sent
		for i = 1, 10 do
			a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;P;n" .. i, "PARTY", "Aedot-Realm")
		end
		world:Advance(1)
		local pongs = 0
		for i = before + 1, #a.sent do
			if a.sent[i].text:find(";p;", 1, true) then
				pongs = pongs + 1
			end
		end
		H.eq(pongs, 1)
	end)

	H.test("flot de HELLO : au plus une réponse toutes les 5 s, mais toujours une réponse", function()
		local world, a = Grouped()
		world:Advance(10)
		local before = #a.sent
		for _ = 1, 10 do
			a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;H;0.1.0;1;3", "PARTY", "Aedot-Realm")
			world:Advance(0.5)
		end
		local replies = #a.sent - before
		H.ok(replies >= 1 and replies <= 2, "réponses en 5 s : " .. replies)
		world:Advance(6)
		H.ok(#a.sent - before <= 3, "réponse différée unique")
		H.ok(a.sent[#a.sent].text:find(";h;", 1, true), "la dernière demande a reçu sa réponse")
	end)

	H.test("BYE : les NODE encore en file ne partent pas après lui", function()
		local world, a, b = Grouped()
		a.sendResult = 3
		SendLive(a, "n1", 0.51, 0.5)
		SendLive(a, "n2", 0.52, 0.5)
		a.sendResult = nil
		a:Slash("share off")
		world:Advance(5)
		H.eq(b.ns.MarkerManager.Count(), 0, "aucun marqueur reçu après le BYE")
		H.eq(b.ns.GroupSync.GetPeers()[1].peer.sharing, false)
	end)

	H.test("NODE d'un pair qui a arrêté le partage : ignoré", function()
		local _, a = Grouped()
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;B", "PARTY", "Aedot-Realm")
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;N;a;L;H;D;1429;50000;50000;0;0;0;x", "PARTY", "Aedot-Realm")
		H.eq(a.ns.MarkerManager.Count(), 0)
		-- reprise du partage : nouveau HELLO
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;H;0.1.0;1;3", "PARTY", "Aedot-Realm")
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;N;a;L;H;D;1429;50000;50000;0;0;0;x", "PARTY", "Aedot-Realm")
		H.eq(a.ns.MarkerManager.Count(), 1)
	end)

	H.test("réception désactivée : les marqueurs déjà reçus sont masqués", function()
		local world, a, b = Grouped()
		SendLive(a, "n1", 0.51, 0.5)
		world:Advance(0.5)
		H.eq(#VisiblePins(b), 1)
		b:Slash("receive off")
		world:Advance(1.5)
		H.eq(#VisiblePins(b), 0)
		b:Slash("receive on")
		world:Advance(1.5)
		H.eq(#VisiblePins(b), 1)
	end)

	H.test("version incompatible : un seul avertissement, pas d'annonce de découverte", function()
		local _, a = Grouped()
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "2;N;a;L;H;D;1429;1;1;0;0;0;x", "PARTY", "Aedot-Realm")
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "2;H;9.0.0;1;5", "PARTY", "Aedot-Realm")
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "2;N;a;L;H;D;1429;1;1;0;0;0;x", "PARTY", "Aedot-Realm")
		local warnings = 0
		for _, line in ipairs(a.chat) do
			if line:find("version de protocole non prise en charge", 1, true) then
				warnings = warnings + 1
			end
		end
		H.eq(warnings, 1)
		H.eq(a:ChatContains("Aedot utilise PartyGatherRadar 9.0.0"), nil, "version future : pas d'annonce")
		H.eq(a.ns.GroupSync.GetPeers()[1].peer.compatible, false)
	end)

	H.test("journal de diagnostic : rejets en série seulement comptés au-delà de 20", function()
		local _, a = Grouped()
		a:Slash("debug")
		local lines = #a.chat
		for _ = 1, 40 do
			a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;B", "WHISPER", "Inconnu-Realm")
		end
		H.eq(a.ns.Diagnostics.rejectReasons.channel, 40)
		H.ok(#a.chat - lines <= 20, "lignes affichées : " .. (#a.chat - lines))
	end)

	H.test("sonde : balayage abandonné si le personnage bouge", function()
		local world, a = NewPair()
		a.ns.Config.Set("autoDetect", false) -- sonde manuelle seule : pas de marqueurs LIVE automatiques
		a.blips = { { name = "Pacifique", dx = 21, dy = 0 } }
		a:Slash("probe scan")
		a.x = a.x + 0.01 -- 35 m
		world:Advance(0.5)
		H.ok(a:ChatContains("balayage interrompu"), "abandon signalé")
		local _, test = a.ns.MarkerManager.Count()
		H.eq(test, 0, "aucun marqueur faux")
		H.eq(a.softCursor, nil, "curseur logiciel jamais activé")
	end)

	---------------------------------------------------------------------------
	H.suite("Sonde de détection : balayage simulé de la minicarte")
	---------------------------------------------------------------------------

	H.test("les points simulés sont retrouvés et convertis en positions de carte", function()
		local world, a = NewPair()
		a.ns.Config.Set("autoDetect", false) -- sonde manuelle seule : pas de marqueurs LIVE automatiques
		a.blips = {
			{ name = "Pacifique", dx = 21, dy = 0 },
			{ name = "Feuillargent", dx = -30, dy = 24 },
		}
		a:Slash("probe scan")
		world:Advance(0.5)
		H.ok(a:ChatContains("balayage terminé"), "balayage terminé")
		H.eq(a.softCursor, false, "curseur logiciel rendu")
		local found = {}
		a.ns.MarkerManager.ForEach(function(marker)
			found[marker.name] = marker
		end, world.time, "test")
		local yardsPerUnit = 233.333 / 70
		local herb = H.contains({ found["[Sonde] Pacifique"] }, function(m) return m end, "Pacifique trouvé")
		H.near(herb.x, 0.5 + 21 * yardsPerUnit / 3470, 4 * yardsPerUnit / 3470, "x Pacifique")
		H.near(herb.y, 0.5, 4 * yardsPerUnit / 2315, "y Pacifique")
		local leaf = H.contains({ found["[Sonde] Feuillargent"] }, function(m) return m end, "Feuillargent trouvé")
		H.near(leaf.x, 0.5 - 30 * yardsPerUnit / 3470, 4 * yardsPerUnit / 3470, "x Feuillargent")
		H.near(leaf.y, 0.5 - 24 * yardsPerUnit / 2315, 4 * yardsPerUnit / 2315, "y Feuillargent")
		local real = a.ns.MarkerManager.Count()
		H.eq(real, 0, "la sonde ne crée aucune donnée réelle")
		H.eq(#a.sent, 0, "la sonde n'envoie rien au groupe")
		NoErrors(a)
	end)

	H.test("rotation de la minicarte : la conversion inverse reste cohérente", function()
		local world, a = NewPair()
		a.ns.Config.Set("autoDetect", false) -- sonde manuelle seule : pas de marqueurs LIVE automatiques
		a.cvars.rotateMinimap = "1"
		a.facing = math.pi / 2 -- face à l'ouest : un point en haut de la minicarte est à l'ouest
		a.blips = { { name = "Pacifique", dx = 0, dy = 30 } }
		a:Slash("probe scan")
		world:Advance(0.5)
		local herb
		a.ns.MarkerManager.ForEach(function(marker) herb = marker end, world.time, "test")
		H.ok(herb, "point trouvé")
		local yards = 30 * 233.333 / 70
		H.near(herb.x, 0.5 - yards / 3470, 0.0005, "à l'ouest")
		H.near(herb.y, 0.5, 0.0005, "même latitude")
	end)

	---------------------------------------------------------------------------
	H.suite("WoW Forever : noms régionaux (prénom et nom de famille)")
	---------------------------------------------------------------------------
	-- Constaté en jeu le 2026-10-15 : l'émetteur reçu était "Aedot Wnx-ClassicBetaPvE2" ; la version 0.1.0
	-- rejetait l'autre membre (not_in_group) et ne reconnaissait pas son propre écho.

	local REALM = "ClassicBetaPvE2"

	local function RegionalGrouped(joinedNames)
		local world = H.NewWorld(root)
		world.regionalNames = true
		world.joinedNames = joinedNames
		local a = world:NewClient({ name = "Aekiss", surname = "Desbisous", realm = REALM,
			tracking = { H.HERB_TRACKING, H.ORE_TRACKING } })
		local b = world:NewClient({ name = "Aedot", surname = "Wnx", realm = REALM })
		a:Login(false)
		b:Login(false)
		world:SetGroup({ a, b })
		world:Advance(3)
		return world, a, b
	end

	H.test("émetteurs « Prénom Nom-Royaume » reconnus : découverte mutuelle, échos ignorés", function()
		local _, a, b = RegionalGrouped()
		H.eq(a.ns.GetPlayerFullName(), "Aekiss Desbisous")
		local peersA, peersB = a.ns.GroupSync.GetPeers(), b.ns.GroupSync.GetPeers()
		H.eq(#peersA, 1, "Aedot connu d'Aekiss")
		H.eq(peersA[1].name, "Aedot Wnx")
		H.eq(#peersB, 1, "Aekiss connu d'Aedot")
		H.eq(peersB[1].name, "Aekiss Desbisous")
		H.eq(a.ns.Diagnostics.rejectReasons.not_in_group, nil, "aucun rejet chez Aekiss")
		H.eq(b.ns.Diagnostics.rejectReasons.not_in_group, nil, "aucun rejet chez Aedot")
		H.ok(a.ns.Diagnostics.counters.echoes >= 1, "écho reconnu")
		H.ok(a:ChatContains("Aedot Wnx utilise PartyGatherRadar"), "annonce avec le nom complet")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("UnitName renvoie « Prénom Nom » en un seul résultat : même identité", function()
		local _, a, b = RegionalGrouped(true)
		H.eq(a.ns.GetPlayerFullName(), "Aekiss Desbisous")
		H.eq(#a.ns.GroupSync.GetPeers(), 1)
		H.eq(#b.ns.GroupSync.GetPeers(), 1)
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("/pgr test : PONG et marqueur TEST attribués au nom complet", function()
		local world, a, b = RegionalGrouped()
		a:Slash("test")
		world:Advance(5.5)
		H.ok(a:ChatContains("PONG reçu de Aedot Wnx"), "PONG reçu")
		local realB, testB = b.ns.MarkerManager.Count()
		H.eq(realB, 0, "aucune donnée réelle")
		H.eq(testB, 1, "marqueur TEST reçu")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("même prénom, autre nom de famille : joueur hors groupe rejeté, membre accepté", function()
		local _, a = RegionalGrouped()
		local D = a.ns.Diagnostics
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;B", "PARTY", "Aedot Zorn-" .. REALM)
		H.eq(D.rejectReasons.not_in_group, 1, "homonyme de prénom rejeté")
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;B", "PARTY", "Aedot-" .. REALM)
		H.eq(D.rejectReasons.not_in_group, 2, "prénom seul rejeté")
		H.eq(a.ns.GroupSync.GetPeers()[1].peer.sharing, true, "aucun BYE accepté jusque-là")
		local log = table.concat(D.GetRecentLog(), "\n")
		H.ok(log:find("Aedot Zorn <- Aedot Zorn-" .. REALM, 1, true), "émetteur brut journalisé")
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "1;B", "PARTY", "Aedot Wnx-" .. REALM)
		H.eq(a.ns.GroupSync.GetPeers()[1].peer.sharing, false, "BYE du vrai membre accepté")
		NoErrors(a)
	end)

	H.test("départ du groupe : le pair au nom complet est oublié", function()
		local world, a, b = RegionalGrouped()
		world:SetGroup({ a })
		world:Advance(1)
		H.eq(#a.ns.GroupSync.GetPeers(), 0)
		H.eq(#b.ns.GroupSync.GetPeers(), 0)
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("normalisation : royaume retiré au dernier tiret, nom de famille gardé entier", function()
		local _, a = RegionalGrouped()
		local ns = a.ns
		H.eq(ns.NormalizeName("Aedot Wnx-" .. REALM), "Aedot Wnx")
		H.eq(ns.NormalizeName("Aedot Wnx-Foo-" .. REALM), "Aedot Wnx-Foo", "nom de famille avec tiret")
		H.eq(ns.NormalizeName("Aedot Wnx"), "Aedot Wnx", "sans royaume")
		H.eq(ns.NormalizeName(H.SECRET), nil, "valeur secrète")
		H.eq(ns.ShortName("Aedot Wnx"), "Aedot Wnx", "affichage du nom complet")
	end)

	H.test("/pgr diag : rapport et identité sauvegardés sans le mode journal", function()
		local world, a = RegionalGrouped()
		H.eq(a.ns.Config.Get("debug"), false)
		a:Slash("diag")
		world:Advance(0.1)
		local report = a.ns.db.diagnostics.lastReport
		H.ok(type(report) == "table" and #report > 10, "rapport sauvegardé")
		local text = table.concat(report, "\n")
		H.ok(text:find("identity.player : INFO — identité « Aekiss Desbisous », noms régionaux : true", 1, true),
			"sonde d'identité")
		H.ok(text:find("UnitNameUnmodified : Aekiss / Desbisous", 1, true), "valeurs brutes du client")
		H.ok(text:find("capacité sync : OUI", 1, true), "capacités")
		H.ok(text:find("compteurs : ", 1, true), "compteurs")
		H.ok(text:find("dernière erreur : aucune", 1, true), "dernière erreur")
		NoErrors(a)
	end)

	H.test("RegionalUniqueNamesEnabled() faux : identités classiques « Nom-Royaume »", function()
		local world = H.NewWorld(root)
		world.regionalNames = false
		local a = world:NewClient({ name = "Aekiss", surname = "Desbisous" })
		local b = world:NewClient({ name = "Aedot", surname = "Wnx" })
		a:Login(false)
		b:Login(false)
		world:SetGroup({ a, b })
		world:Advance(3)
		H.eq(a.ns.GetPlayerFullName(), "Aekiss-Realm")
		H.eq(#a.ns.GroupSync.GetPeers(), 1)
		H.eq(a.ns.GroupSync.GetPeers()[1].name, "Aedot-Realm")
		NoErrors(a)
		NoErrors(b)
	end)

	---------------------------------------------------------------------------
	H.suite("Interface : bouton de minicarte et fenêtre de réglages")
	---------------------------------------------------------------------------

	local function Contains(texts, needle)
		for _, text in ipairs(texts) do
			if text and text:find(needle, 1, true) then
				return true
			end
		end
		return false
	end

	H.test("bouton créé au chargement, nommé, sur le bord de la minicarte", function()
		local _, a = NewPair()
		local button = a.ns.MinimapButton.GetFrame()
		H.ok(button, "bouton créé")
		H.eq(button.name, "PartyGatherRadarMinimapButton")
		H.eq(button.parent, a.env.Minimap)
		H.eq(button.shown, true)
		-- 225° (défaut) sur une minicarte de 140 unités : rayon 75
		H.near(button.point.x, -75 * math.sqrt(0.5), 0.01, "x")
		H.near(button.point.y, -75 * math.sqrt(0.5), 0.01, "y")
		H.eq(#a:UnexpectedGlobals(), 0)
		NoErrors(a)
	end)

	H.test("position sur le bord : minicarte ronde ou carrée", function()
		local _, a = NewPair()
		local Offset = a.ns.MinimapButton.OffsetForAngle
		local x, y = Offset(0, 140, "ROUND")
		H.near(x, 75, 1e-9)
		H.near(y, 0, 1e-9)
		x, y = Offset(90, 140, "ROUND")
		H.near(x, 0, 1e-9)
		H.near(y, 75, 1e-9)
		x, y = Offset(45, 140, "SQUARE")
		H.near(x, 75, 1e-9, "coin du carré")
		H.near(y, 75, 1e-9, "coin du carré")
	end)

	H.test("glisser le bouton : angle sauvegardé, le relâchement n'ouvre pas la fenêtre", function()
		local world, a = NewPair()
		local button = a.ns.MinimapButton.GetFrame()
		local centerX, centerY = a.env.Minimap:GetCenter()
		button.scripts.OnDragStart(button)
		a.cursorX, a.cursorY = centerX, centerY + 100 -- au nord du centre
		button.scripts.OnUpdate(button, 0.02)
		button.scripts.OnDragStop(button)
		H.near(a.ns.Config.Get("minimapButtonAngle"), 90, 1e-6, "angle sauvegardé")
		H.near(button.point.x, 0, 1e-6)
		H.near(button.point.y, 75, 1e-6)
		button:Click()
		H.eq(a.ns.SettingsPanel.IsOpen(), false, "clic de fin de déplacement ignoré")
		world:Advance(0.5)
		button:Click()
		H.eq(a.ns.SettingsPanel.IsOpen(), true, "clic suivant : fenêtre ouverte")
		button:Click()
		H.eq(a.ns.SettingsPanel.IsOpen(), false, "second clic : fenêtre fermée")
		NoErrors(a)
	end)

	H.test("/pgr button off|on : bouton masqué puis affiché, réglage conservé", function()
		local _, a = NewPair()
		local button = a.ns.MinimapButton.GetFrame()
		a:Slash("button off")
		H.eq(button.shown, false)
		H.eq(a.ns.Config.Get("showMinimapButton"), false)
		a:Reload()
		H.eq(a.ns.MinimapButton.GetFrame().shown, false, "masqué après /reload")
		a:Slash("button on")
		H.eq(a.ns.MinimapButton.GetFrame().shown, true)
		NoErrors(a)
	end)

	H.test("infobulle du bouton : version et membres utilisant l'addon", function()
		local _, a = Grouped()
		local button = a.ns.MinimapButton.GetFrame()
		button.scripts.OnEnter(button)
		H.eq(a.tooltipLines[1], "PartyGatherRadar 0.5.0")
		H.eq(a.tooltipLines[2], "groupe : 1 autre(s) membre(s), 1 avec PartyGatherRadar")
		NoErrors(a)
	end)

	H.test("/pgr ouvre la fenêtre : version, membres avec et sans l'addon", function()
		local world = H.NewWorld(root)
		world.regionalNames = true
		local a = world:NewClient({ name = "Aekiss", surname = "Desbisous", realm = REALM })
		local b = world:NewClient({ name = "Aedot", surname = "Wnx", realm = REALM })
		local c = world:NewClient({ name = "Carl", surname = "Zed", realm = REALM, hasAddon = false })
		a:Login(false)
		b:Login(false)
		c:Login(false)
		world:SetGroup({ a, b, c })
		world:Advance(3)
		a:Slash("")
		H.eq(a.ns.SettingsPanel.IsOpen(), true, "fenêtre ouverte")
		local version, summary = a.ns.SettingsPanel.GetHeaderTexts()
		H.eq(version, "version 0.5.0, protocole 1 — client 1.60.1 (build 70374)")
		H.eq(summary, "2 autre(s) membre(s), 1 avec PartyGatherRadar")
		local texts = a.ns.SettingsPanel.GetMemberTexts()
		H.ok(Contains(texts, "Aedot Wnx — |cff40ff40PartyGatherRadar 0.5.0|r"), "membre avec l'addon")
		H.ok(Contains(texts, "Carl Zed — |cff9d9d9dsans addon détecté|r"), "membre sans l'addon")
		world:SetGroup({ a })
		world:Advance(1)
		texts = a.ns.SettingsPanel.GetMemberTexts()
		H.ok(Contains(texts, "pas de groupe"), "fenêtre mise à jour au départ du groupe")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("case « informations des autres joueurs » : marqueurs reçus masqués puis réaffichés", function()
		local world, a, b = Grouped()
		b:Slash("test")
		world:Advance(0.5)
		H.eq(#VisiblePins(a), 1, "marqueur TEST d'Aedot affiché chez Aekiss")
		a:Slash("config")
		local check = a.ns.SettingsPanel.GetCheckbox("receiveEnabled")
		H.eq(check:GetChecked(), true)
		check:Click()
		world:Advance(0.5)
		H.eq(a.ns.Config.Get("receiveEnabled"), false)
		H.eq(#VisiblePins(a), 0, "marqueurs des autres masqués")
		check:Click()
		world:Advance(0.5)
		H.eq(a.ns.Config.Get("receiveEnabled"), true)
		H.eq(#VisiblePins(a), 1, "marqueurs des autres réaffichés")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("toutes les cases reflètent et modifient leur réglage", function()
		local world, a = Grouped()
		a:Slash("")
		for _, key in ipairs({ "enabled", "receiveEnabled", "shareEnabled", "showMinimap", "showHerbs", "showOres",
			"showMinimapButton", "debug", "autoDetect", "proximityDetect", "showHistory", "showOwnDetections",
			"hideNotFound" }) do
			local check = a.ns.SettingsPanel.GetCheckbox(key)
			H.ok(check, "case " .. key)
			local before = a.ns.Config.Get(key)
			H.eq(check:GetChecked(), before, "état initial " .. key)
			check:Click()
			H.eq(a.ns.Config.Get(key), not before, "réglage modifié " .. key)
			check:Click()
			H.eq(a.ns.Config.Get(key), before, "réglage rétabli " .. key)
		end
		world:Advance(1)
		NoErrors(a)
	end)

	H.test("client anglais : fenêtre et infobulle en anglais", function()
		local world = H.NewWorld(root)
		local a = world:NewClient({ name = "Aekiss", locale = "enUS" })
		a:Login(false)
		a:Slash("")
		local _, summary = a.ns.SettingsPanel.GetHeaderTexts()
		H.eq(summary, "")
		H.ok(Contains(a.ns.SettingsPanel.GetMemberTexts(), "not in a group"))
		local button = a.ns.MinimapButton.GetFrame()
		button.scripts.OnEnter(button)
		H.eq(a.tooltipLines[2], "not in a group")
		NoErrors(a)
	end)

	---------------------------------------------------------------------------
	H.suite("Détection automatique et partage (phases 2 et 3)")
	---------------------------------------------------------------------------
	-- Aekiss : pistage des herbes actif ; Aedot : aucun pistage. Ressources ancrées dans le monde
	-- (worldBlips), zone de survol de 12 unités comme en jeu.

	local ELWYNN = 1429
	local MAP = H.MAPS[ELWYNN]

	--- Position de carte à `east`, `north` mètres de (0,5 ; 0,5).
	local function At(east, north)
		return 0.5 + east / MAP.width, 0.5 - north / MAP.height
	end

	local function Herb(name, east, north)
		local x, y = At(east, north)
		return { name = name, mapID = ELWYNN, x = x, y = y }
	end

	local function Received(client, name)
		local list = {}
		client.ns.MarkerManager.ForEach(function(marker, status)
			if marker.name == name and not marker.isLocal then
				list[#list + 1] = { marker = marker, status = status }
			end
		end, client.world.time, "real")
		return list
	end

	local function CountSent(client, messageType)
		local count = 0
		for _, message in ipairs(client.sent) do
			if message.text:match("^%d+;" .. messageType .. ";") then
				count = count + 1
			end
		end
		return count
	end

	local function LogContains(client, text)
		return table.concat(client.ns.Diagnostics.GetRecentLog(), "\n"):find(text, 1, true) ~= nil
	end

	H.test("tri des noms : herbes, minerais, et le bruit vu en jeu ignoré", function()
		local _, a = NewPair()
		local Classify = a.ns.ResourceNames.Classify
		for _, name in ipairs({ "Pacifique", "Eglantine", "Églantine", "PACIFIQUE", "Feuillargent", "Peacebloom",
			"Sauge-argent des montagnes", "Khadgar's Whisker" }) do
			H.eq(Classify(name), "HERB", name)
		end
		for _, name in ipairs({ "Filon de cuivre", "Gisement de fer", "Riche filon de thorium", "Copper Vein",
			"Rich Thorium Vein", "Filon de quelque chose de nouveau", "Some New Deposit" }) do
			H.eq(Classify(name), "ORE", name)
		end
		for _, name in ipairs({ "Les échantillons de racines", "- Echantillon de racines : 0/8", "Aedot Wnx",
			"Aekiss Desbisous", "", "   " }) do
			H.eq(Classify(name), nil, name)
		end
		H.eq(Classify(H.SECRET), nil, "valeur secrète")
		H.eq(Classify(nil), nil)
	end)

	H.test("infobulle chez Aedot : le nom de la plante en titre, à la place de PartyGatherRadar", function()
		local world, a, b = Grouped()
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		world:Advance(5)
		local pin = VisiblePins(b)[1]
		pin.scripts.OnEnter(pin)
		H.eq(b.tooltipLines[1], "Pacifique", "titre")
		for _, line in ipairs(b.tooltipLines) do
			H.ok(line ~= "PartyGatherRadar", "plus de titre PartyGatherRadar")
			H.ok(not line:find("Nom :", 1, true), "nom pas répété sur une ligne « Nom »")
		end
		H.ok(Contains(b.tooltipLines, "Détecté par : Aekiss"), "auteur de la détection")
		H.ok(Contains(b.tooltipLines, "Type : Herboristerie"), "type")
		-- nom masqué par le réglage : retour au titre de l'addon
		b.ns.Config.Set("showTooltipName", false)
		pin.scripts.OnEnter(pin)
		H.eq(b.tooltipLines[1], "PartyGatherRadar")
		NoErrors(b)
	end)

	H.test("une herbe de la minicarte d'Aekiss apparaît chez Aedot au bon endroit", function()
		local world, a, b = Grouped()
		local herb = Herb("Pacifique", 40, 30)
		a.worldBlips = { herb }
		world:Advance(5)
		local list = Received(b, "Pacifique")
		H.eq(#list, 1, "un seul marqueur reçu")
		local marker = list[1].marker
		H.eq(marker.kind, "HERB")
		H.eq(marker.source, "LIVE")
		H.eq(list[1].status, "ACTIVE")
		local distance = b.ns.MarkerManager.DistanceYards(ELWYNN, marker.x, marker.y, herb.x, herb.y)
		H.ok(distance <= 15, string.format("position à %.1f m de la plante", distance))
		H.eq(#VisiblePins(b), 1, "icône sur la minicarte d'Aedot")
		H.eq(#VisiblePins(a), 0, "aucun doublon sur la minicarte d'Aekiss (point natif déjà visible)")
		H.eq(CountSent(a, "N"), 1, "une seule annonce")
		H.ok(LogContains(a, "herbe : Pacifique"), "découverte journalisée")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("deux plantes du même nom à 100 m : deux marqueurs ; une plante touchée sur plusieurs points : un seul", function()
		local world, a, b = Grouped()
		a.worldBlips = { Herb("Pacifique", -50, 0), Herb("Pacifique", 50, 0), Herb("Feuillargent", 0, 60) }
		world:Advance(5)
		H.eq(#Received(b, "Pacifique"), 2)
		H.eq(#Received(b, "Feuillargent"), 1)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 3)
		H.eq(CountSent(a, "N"), 3, "une annonce par plante")
	end)

	H.test("zones de quête et joueurs ignorés : aucun marqueur, journal sans flot", function()
		local world, a, b = Grouped()
		a.questArea = "Les échantillons de racines"
		a.blips = { { name = "Aedot", dx = 3, dy = 2 } }
		a.worldBlips = { Herb("Pacifique", -60, 10) }
		world:Advance(10)
		H.eq(#Received(b, "Pacifique"), 1, "la plante passe malgré le bruit")
		H.eq(b.ns.MarkerManager.Count(), 1, "rien d'autre n'est partagé")
		H.eq(a.ns.AutoDetect.GetNodeCount(), 1)
		local ignored = 0
		for _, line in ipairs(a.ns.Diagnostics.GetRecentLog()) do
			if line:find("nom ignoré", 1, true) then
				ignored = ignored + 1
			end
		end
		H.eq(ignored, 3, "titre de quête, objectif et joueur journalisés une seule fois chacun")
		NoErrors(a)
	end)

	H.test("aucun sondage sans pistage actif, en combat, souris sur la minicarte ou option désactivée", function()
		local world, a = Grouped()
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		local function NoProbe(label)
			local before = a.mouseoverCalls
			world:Advance(5)
			H.eq(a.mouseoverCalls, before, label)
		end
		a.tracking = { { name = "Découverte d'herbes", active = false, spellID = 2383, type = "spell" } }
		NoProbe("pistage inactif")
		a.tracking = { H.HERB_TRACKING }
		a.inCombat = true
		NoProbe("combat")
		a.inCombat = false
		a.mouseOverMinimap = true
		NoProbe("souris sur la minicarte")
		a.mouseOverMinimap = false
		a:Slash("auto off")
		NoProbe("option désactivée")
		a:Slash("auto on")
		world:Advance(5)
		H.ok(a.mouseoverCalls > 0, "reprise")
		H.eq(a.softCursor, false, "curseur logiciel toujours rendu")
		NoErrors(a)
	end)

	H.test("plante récoltée ou disparue : retirée chez Aedot", function()
		local world, a, b = Grouped()
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		world:Advance(5)
		H.eq(#Received(b, "Pacifique"), 1)
		a.worldBlips = {}
		world:Advance(6)
		H.eq(#Received(b, "Pacifique"), 0, "marqueur retiré")
		H.eq(CountSent(a, "X"), 1, "un REMOVE envoyé")
		H.eq(a.ns.AutoDetect.GetNodeCount(), 0)
		H.ok(LogContains(a, "disparu : Pacifique"), "disparition journalisée")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("plante au bord de la minicarte : son absence n'est pas une disparition", function()
		local world, a, b = Grouped()
		a.worldBlips = { Herb("Pacifique", 200, 0) }
		world:Advance(5)
		H.eq(#Received(b, "Pacifique"), 1, "détectée à 200 m")
		a.worldBlips = {}
		world:Advance(6)
		H.eq(#Received(b, "Pacifique"), 1, "toujours là : absence hors de la zone fiable")
		H.eq(CountSent(a, "X"), 0)
	end)

	H.test("en déplacement : une seule ressource, position juste", function()
		local world, a, b = Grouped()
		local herb = Herb("Pacifique", 80, 20)
		a.worldBlips = { herb }
		for _ = 1, 200 do -- 10 s à 7 m/s vers l'est : la plante passe à côté puis derrière
			a.x = a.x + 7 * 0.05 / MAP.width
			world:Advance(0.05)
		end
		local list = Received(b, "Pacifique")
		H.eq(#list, 1, "pas de doublon")
		local distance = b.ns.MarkerManager.DistanceYards(ELWYNN, list[1].marker.x, list[1].marker.y, herb.x, herb.y)
		H.ok(distance <= 12, string.format("position moyenne à %.1f m de la plante", distance))
		H.eq(a.ns.AutoDetect.GetNodeCount(), 1)
		NoErrors(a)
	end)

	H.test("rafraîchissement : le marqueur reste récent chez Aedot, sans flot de messages", function()
		local world, a, b = Grouped()
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		world:Advance(90)
		local list = Received(b, "Pacifique")
		H.eq(#list, 1)
		H.eq(list[1].status, "ACTIVE", "toujours récent après 90 s")
		local nodes = CountSent(a, "N")
		H.ok(nodes >= 3 and nodes <= 5, "annonces espacées de 25 s : " .. nodes)
	end)

	H.test("réception réactivée chez Aedot : le marqueur revient au rafraîchissement suivant", function()
		local world, a, b = Grouped()
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		world:Advance(5)
		b:Slash("receive off")
		world:Advance(70)
		H.eq(#VisiblePins(b), 0, "masqué pendant la désactivation")
		b:Slash("receive on")
		world:Advance(30)
		local list = Received(b, "Pacifique")
		H.eq(list[1] and list[1].status, "ACTIVE", "de nouveau récent")
		H.eq(#VisiblePins(b), 1)
	end)

	H.test("nouveau membre : les ressources visibles lui sont envoyées", function()
		local world, a, b = NewPair()
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		world:Advance(5)
		H.eq(CountSent(a, "N"), 0, "seul : rien n'est envoyé")
		H.eq(a.ns.AutoDetect.GetNodeCount(), 1, "mais la plante est suivie")
		world:SetGroup({ a, b })
		world:Advance(6)
		H.eq(#Received(b, "Pacifique"), 1, "reçue après la formation du groupe")
	end)

	H.test("partage désactivé : rien n'est envoyé, détection locale conservée", function()
		local world, a, b = Grouped()
		a:Slash("share off")
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		world:Advance(5)
		H.eq(CountSent(a, "N"), 0)
		H.eq(#Received(b, "Pacifique"), 0)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 1)
	end)

	H.test("nom appris à la récolte : reconnu ensuite et conservé", function()
		local world, a, b = Grouped()
		a.worldBlips = { Herb("Herbe de Forever", 40, 30) }
		world:Advance(5)
		H.eq(#Received(b, "Herbe de Forever"), 0, "nom inconnu : ignoré")
		a:FireEvent("UNIT_SPELLCAST_SENT", "player", "Herbe de Forever", "Cast-1", 2366)
		H.ok(LogContains(a, "nom appris à la récolte : Herbe de Forever"), "apprentissage journalisé")
		world:Advance(5)
		H.eq(#Received(b, "Herbe de Forever"), 1, "reconnu au balayage suivant")
		H.eq(a.env.PartyGatherRadarDB.learnedNames.HERB["herbe de forever"], "Herbe de Forever", "sauvegardé")
		a:FireEvent("UNIT_SPELLCAST_SENT", "player", H.SECRET, "Cast-2", 2366)
		a:FireEvent("UNIT_SPELLCAST_SENT", "party1", "Autre plante", "Cast-3", 2366)
		a:FireEvent("UNIT_SPELLCAST_SENT", "player", "Ennemi", "Cast-4", 133)
		H.eq(a.ns.ResourceNames.Classify("Autre plante"), nil, "autre joueur : rien appris")
		H.eq(a.ns.ResourceNames.Classify("Ennemi"), nil, "autre sort : rien appris")
		NoErrors(a)
	end)

	H.test("option « mes propres détections » : la plante s'affiche aussi chez Aekiss", function()
		local world, a = Grouped()
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		a.ns.Config.Set("showOwnDetections", true)
		world:Advance(5)
		H.eq(#VisiblePins(a), 1)
	end)

	H.test("balayage manuel pendant la détection automatique : aucun conflit", function()
		local world, a = Grouped()
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		world:Advance(2.02) -- un balayage automatique vient de démarrer
		a:Slash("probe scan")
		world:Advance(1)
		H.ok(a:ChatContains("balayage terminé"), "sonde manuelle terminée")
		world:Advance(5)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 1, "détection automatique reprise")
		H.eq(a.softCursor, false)
		NoErrors(a)
	end)

	H.test("/pgr status et /pgr diag décrivent la détection automatique", function()
		local world, a = Grouped()
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		world:Advance(5)
		a:Slash("status")
		H.ok(a:ChatContains("détection automatique : oui"), "ligne de statut")
		a:Slash("diag")
		local report = table.concat(a.ns.db.diagnostics.lastReport, "\n")
		H.ok(report:find("detection.auto : INFO — active", 1, true), "sonde detection.auto")
		H.ok(report:find("1 ressource(s) suivie(s)", 1, true), "ressources suivies")
		NoErrors(a)
	end)

	---------------------------------------------------------------------------
	H.suite("Adaptation au client : sonde restreinte (mise à jour Forever de novembre 2026)")
	---------------------------------------------------------------------------
	-- Depuis cette mise à jour, la sonde ne nomme un point que sous le vrai curseur : le balayage par
	-- curseur logiciel ne lit plus rien, sans erreur (client.probeRestricted). Le survol reste possible.

	local UNITS_PER_YARD = 70 / 233.333

	--- Place le vrai curseur sur le point de minicarte d'une ressource du monde.
	local function HoverOver(client, blip)
		client.cursorX = 1070 + (blip.x - client.x) * MAP.width * UNITS_PER_YARD
		client.cursorY = 670 + (client.y - blip.y) * MAP.height * UNITS_PER_YARD
		client.mouseOverMinimap = true
	end

	--- Survole la ressource un instant, puis laisse un balayage passer souris hors de la minicarte.
	local function HoverThenLeave(world, client, blip)
		HoverOver(client, blip)
		world:Advance(0.5)
		client.mouseOverMinimap = false
		world:Advance(3)
	end

	local function CountChat(client, text)
		local count = 0
		for _, line in ipairs(client.chat) do
			if line:find(text, 1, true) then
				count = count + 1
			end
		end
		return count
	end

	local BLIND_TEXT = "Détection au survol activée"

	--- Client restreint, deux herbes survolées : le balayage est déclaré aveugle.
	local function BlindPair()
		local world, a, b = Grouped()
		a.probeRestricted = true
		local h1, h2 = Herb("Pacifique", 40, 30), Herb("Feuillargent", -50, 20)
		a.worldBlips = { h1, h2 }
		world:Advance(3)
		HoverThenLeave(world, a, h1)
		HoverThenLeave(world, a, h2)
		return world, a, b, h1, h2
	end

	H.test("sonde restreinte : le balayage ne voit rien, une herbe survolée est partagée au bon endroit", function()
		local world, a, b = Grouped()
		a.probeRestricted = true
		local herb = Herb("Pacifique", 40, 30)
		a.worldBlips = { herb }
		world:Advance(5)
		H.eq(#Received(b, "Pacifique"), 0, "balayage aveugle : rien de partagé")
		H.eq(a.ns.AutoDetect.GetNodeCount(), 0)
		HoverOver(a, herb)
		world:Advance(0.5)
		local list = Received(b, "Pacifique")
		H.eq(#list, 1, "partagée au survol")
		H.eq(list[1] and list[1].status, "ACTIVE")
		local marker = list[1].marker
		local distance = b.ns.MarkerManager.DistanceYards(ELWYNN, marker.x, marker.y, herb.x, herb.y)
		H.ok(distance <= 15, string.format("position à %.1f m de la plante", distance))
		H.eq(CountSent(a, "N"), 1, "une seule annonce malgré les lectures répétées")
		H.eq(a.ns.AutoDetect.stats.hovered, 1)
		H.ok(LogContains(a, "herbe : Pacifique") and LogContains(a, "(survol)"), "découverte au survol journalisée")
		H.eq(#VisiblePins(a), 0, "aucun doublon sur la minicarte d'Aekiss")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("deux herbes survolées absentes du balayage : mode survol, un avertissement, marqueurs gardés", function()
		local world, a, b = Grouped()
		a.probeRestricted = true
		local h1, h2 = Herb("Pacifique", 40, 30), Herb("Feuillargent", -50, 20)
		a.worldBlips = { h1, h2 }
		world:Advance(3)
		HoverThenLeave(world, a, h1)
		H.eq(a.ns.AutoDetect.IsProbeBlind(), false, "une seule preuve : pas encore aveugle")
		H.eq(#Received(b, "Pacifique"), 1, "herbe survolée gardée malgré le balayage vide")
		HoverThenLeave(world, a, h2)
		H.eq(a.ns.AutoDetect.IsProbeBlind(), true, "balayage déclaré aveugle")
		H.eq(CountChat(a, BLIND_TEXT), 1, "avertissement affiché")
		H.ok(LogContains(a, "balayage aveugle"), "journalisé")
		-- balayage espacé : au plus un essai en 20 s
		local perPass = #a.ns.Tracking.BuildGrid(70, 70, 10)
		local before = a.mouseoverCalls
		world:Advance(20)
		H.ok(a.mouseoverCalls - before <= perPass, "au plus un balayage en 20 s : " .. (a.mouseoverCalls - before))
		H.eq(CountSent(a, "X"), 0, "aucune herbe déclarée disparue à tort")
		H.eq(#Received(b, "Pacifique"), 1)
		H.eq(#Received(b, "Feuillargent"), 1)
		H.eq(CountChat(a, BLIND_TEXT), 1, "avertissement unique")
		-- capacités et rapports
		local caps = a.ns.GroupSync.DecodeCaps(a.ns.GroupSync.GetLocalCaps())
		H.eq(caps.MINIMAP_PROBE, false, "sondage plus annoncé")
		local seen = b.ns.GroupSync.DecodeCaps(b.ns.GroupSync.GetPeers()[1].peer.caps)
		H.eq(seen.MINIMAP_PROBE, false, "nouvelle annonce : le groupe sait que le sondage manque")
		a:Slash("status")
		H.ok(a:ChatContains("mode survol %(balayage aveugle%)"), "statut")
		a:Slash("diag")
		local report = table.concat(a.ns.db.diagnostics.lastReport, "\n")
		H.ok(report:find("restreinte par le client", 1, true), "sonde detection.minimapProbeApi")
		H.ok(report:find("capacité localDetection : PARTIEL — au survol seulement", 1, true), "capacité")
		a:Slash("probe scan")
		world:Advance(1)
		H.ok(a:ChatContains("ne nomme plus un point"), "balayage manuel expliqué")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("sonde de nouveau libre : retour au balayage automatique, sans doublon", function()
		local world, a, b = BlindPair()
		a.probeRestricted = false
		world:Advance(35)
		H.eq(a.ns.AutoDetect.IsProbeBlind(), false, "balayage rétabli")
		H.eq(CountChat(a, "fonctionne de nouveau"), 1, "message de retour")
		H.eq(a.ns.AutoDetect.GetNodeCount(), 2, "les herbes survolées sont reprises, pas dupliquées")
		H.eq(#Received(b, "Pacifique"), 1)
		local caps = a.ns.GroupSync.DecodeCaps(a.ns.GroupSync.GetLocalCaps())
		H.eq(caps.MINIMAP_PROBE, true, "sondage de nouveau annoncé")
		-- de nouveau toutes les 2 s : une herbe cueillie par un autre disparaît
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		world:Advance(6)
		H.eq(#Received(b, "Feuillargent"), 0, "absence de nouveau détectée par le balayage")
		local seen = b.ns.GroupSync.DecodeCaps(b.ns.GroupSync.GetPeers()[1].peer.caps)
		H.eq(seen.MINIMAP_PROBE, true, "nouvelle annonce : le groupe sait que le sondage est revenu")
		NoErrors(a)
	end)

	H.test("client non restreint : survoler une herbe que le balayage voit ne change rien", function()
		local world, a, b = Grouped()
		local h1, h2 = Herb("Pacifique", 40, 30), Herb("Feuillargent", -50, 20)
		a.worldBlips = { h1, h2 }
		world:Advance(3)
		HoverThenLeave(world, a, h1)
		HoverThenLeave(world, a, h2)
		HoverThenLeave(world, a, h1)
		H.eq(a.ns.AutoDetect.IsProbeBlind(), false)
		H.eq(CountChat(a, BLIND_TEXT), 0)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 2, "survol et balayage suivent la même herbe")
		H.eq(#Received(b, "Pacifique"), 1)
		NoErrors(a)
	end)

	H.test("mode survol mémorisé pour ce build du client, réévalué sur un nouveau build", function()
		local world, a = BlindPair()
		H.eq(a.env.PartyGatherRadarDB.probe.blindBuild, "70374", "build mémorisé")
		a:Reload()
		world:Advance(3)
		H.eq(a.ns.AutoDetect.IsProbeBlind(), true, "aveugle dès le chargement")
		H.eq(CountChat(a, "rappel : ce client bloque"), 1, "rappel une fois par session")
		world:Advance(10)
		H.eq(CountChat(a, "rappel : ce client bloque"), 1, "pas de répétition")
		a.build = "70999"
		a:Reload()
		world:Advance(3)
		H.eq(a.ns.AutoDetect.IsProbeBlind(), false, "nouveau build : balayage réévalué")
		H.eq(a.env.PartyGatherRadarDB.probe.blindBuild, nil)
		NoErrors(a)
	end)

	H.test("herbe récoltée : retirée tout de suite chez les autres ; filon, cast raté : gardés", function()
		local oreTracking = { name = "Découverte de gisements", active = true, spellID = 2580, type = "spell" }
		local world, a, b = Grouped({ name = "Aekiss", tracking = { H.HERB_TRACKING, oreTracking } })
		a.probeRestricted = true
		local herb, vein = Herb("Pacifique", 10, 5), Herb("Filon de cuivre", -40, -20)
		a.worldBlips = { herb, vein }
		HoverThenLeave(world, a, herb)
		HoverThenLeave(world, a, vein)
		H.eq(#Received(b, "Pacifique"), 1)
		H.eq(#Received(b, "Filon de cuivre"), 1)
		-- cast interrompu : rien n'est retiré
		a:FireEvent("UNIT_SPELLCAST_SENT", "player", "Pacifique", "Cast-1", 2366)
		world:Advance(0.1)
		H.eq(#Received(b, "Pacifique"), 1, "cast sans réussite : herbe gardée")
		-- réussite d'un autre sort : rien n'est retiré
		a:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 133)
		world:Advance(0.1)
		H.eq(#Received(b, "Pacifique"), 1)
		-- cueillette réussie
		a:FireEvent("UNIT_SPELLCAST_SENT", "player", "Pacifique", "Cast-3", 2366)
		a:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 2366)
		world:Advance(0.1)
		H.eq(#Received(b, "Pacifique"), 0, "herbe retirée")
		H.eq(CountSent(a, "X"), 1, "un REMOVE envoyé")
		H.ok(LogContains(a, "récoltée : Pacifique"), "récolte journalisée")
		-- filon miné : il peut rester, il n'est pas retiré
		a:FireEvent("UNIT_SPELLCAST_SENT", "player", "Filon de cuivre", "Cast-4", 2575)
		a:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-4", 2575)
		world:Advance(0.1)
		H.eq(#Received(b, "Filon de cuivre"), 1, "filon gardé")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("herbe récoltée loin du joueur : rien n'est retiré", function()
		local world, a, b = Grouped()
		a.probeRestricted = true
		local herb = Herb("Pacifique", 60, 0)
		a.worldBlips = { herb }
		HoverThenLeave(world, a, herb)
		a:FireEvent("UNIT_SPELLCAST_SENT", "player", "Pacifique", "Cast-1", 2366)
		a:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2366)
		world:Advance(0.1)
		H.eq(#Received(b, "Pacifique"), 1, "une autre plante du même nom, à 60 m, reste")
		H.eq(CountSent(a, "X"), 0)
	end)

	H.test("échecs de sonde répétés (valeur secrète) : un seul avertissement, jamais silencieux", function()
		local world, a = Grouped()
		a.mouseoverSecret = true
		a.worldBlips = { Herb("Pacifique", 40, 30) }
		world:Advance(30)
		H.eq(CountChat(a, "balayages d'affilée en échec"), 1, "avertissement unique")
		H.ok(a.ns.AutoDetect.stats.aborted >= 5)
		a:Slash("status")
		H.ok(a:ChatContains("dernier : secret"), "raison visible dans /pgr status")
		NoErrors(a)
	end)

	H.test("restriction d'addons (rencontre) : ni balayage, ni survol, ni alerte ; reprise ensuite", function()
		local world, a, b = Grouped()
		local herb = Herb("Pacifique", 40, 30)
		a.worldBlips = { herb }
		a.restrictions[a.env.Enum.AddOnRestrictionType.Encounter] = true
		local before = a.mouseoverCalls
		world:Advance(5)
		H.eq(a.mouseoverCalls, before, "aucun balayage")
		HoverOver(a, herb)
		world:Advance(0.5)
		a.mouseOverMinimap = false
		H.eq(#Received(b, "Pacifique"), 0, "aucune lecture au survol")
		H.eq(CountChat(a, "en échec"), 0, "aucune alerte")
		a.restrictions = {}
		world:Advance(5)
		H.eq(#Received(b, "Pacifique"), 1, "reprise après la restriction")
		NoErrors(a)
	end)

	H.test("fonctions de sondage retirées du client : avertissement unique, survol toujours actif", function()
		local world, a, b = Grouped()
		a.env.__api.Minimap.UpdateMouseoverAtPoint = nil
		local herb = Herb("Pacifique", 40, 30)
		a.worldBlips = { herb }
		world:Advance(10)
		H.eq(CountChat(a, "fonctions de sondage de la minicarte absentes"), 1, "avertissement unique")
		HoverOver(a, herb)
		world:Advance(0.5)
		H.eq(#Received(b, "Pacifique"), 1, "partagée au survol")
		NoErrors(a)
	end)

	-- revue de code de la 0.4.0 : preuves datées, une par ressource, effacées par une vraie lecture

	H.test("preuve de plus de 10 min oubliée : une herbe survolée plus tard ne rend pas aveugle", function()
		local world, a = Grouped()
		a.probeRestricted = true
		local h1, h2 = Herb("Pacifique", 40, 30), Herb("Feuillargent", -50, 20)
		a.worldBlips = { h1, h2 }
		world:Advance(3)
		HoverThenLeave(world, a, h1)
		world:Advance(610)
		HoverThenLeave(world, a, h2)
		H.eq(a.ns.AutoDetect.IsProbeBlind(), false, "la première preuve a expiré")
		H.eq(CountChat(a, BLIND_TEXT), 0)
		NoErrors(a)
	end)

	H.test("même herbe survolée deux fois à 5 min d'écart : une seule preuve", function()
		local world, a = Grouped()
		a.probeRestricted = true
		local herb = Herb("Pacifique", 40, 30)
		a.worldBlips = { herb }
		world:Advance(3)
		HoverThenLeave(world, a, herb)
		world:Advance(320)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 0, "repère expiré entre les deux survols")
		HoverThenLeave(world, a, herb)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 1)
		H.eq(a.ns.AutoDetect.IsProbeBlind(), false, "même plante, même endroit : pas deux preuves")
		NoErrors(a)
	end)

	H.test("balayage qui lit une ressource : preuves effacées (herbes cueillies par d'autres après le survol)", function()
		local world, a = Grouped()
		local h1, h2, h3 = Herb("Pacifique", 40, 30), Herb("Feuillargent", -50, 20), Herb("Terrestrine", 30, -35)
		-- h1 survolée, cueillie par un autre avant le balayage suivant : absence dans un balayage vide
		a.worldBlips = { h1 }
		HoverOver(a, h1)
		world:Advance(0.5)
		a.worldBlips = {}
		a.mouseOverMinimap = false
		world:Advance(3)
		H.eq(a.ns.AutoDetect.IsProbeBlind(), false, "une seule preuve")
		-- le balayage lit h2 : la sonde fonctionne
		a.worldBlips = { h2 }
		world:Advance(3)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 2)
		-- même cas avec h3, h2 cueillie entre-temps
		a.worldBlips = { h3 }
		HoverOver(a, h3)
		world:Advance(0.5)
		a.worldBlips = {}
		a.mouseOverMinimap = false
		world:Advance(3)
		H.eq(a.ns.AutoDetect.IsProbeBlind(), false, "la première preuve a été effacée par la lecture de h2")
		H.eq(CountChat(a, BLIND_TEXT), 0)
		NoErrors(a)
	end)

	H.test("infobulle figée pendant un essai de balayage aveugle : le mode survol reste", function()
		local world, a = BlindPair()
		a.staleTooltip = "Pacifique"
		world:Advance(35)
		H.eq(a.ns.AutoDetect.IsProbeBlind(), true, "même nom sur tous les points : pas une vraie lecture")
		H.eq(CountChat(a, "fonctionne de nouveau"), 0)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 2, "aucun repère fantôme")
		NoErrors(a)
	end)

	H.test("en combat : aucune lecture au survol, reprise ensuite", function()
		local world, a, b = Grouped()
		a.probeRestricted = true
		local herb = Herb("Pacifique", 40, 30)
		a.worldBlips = { herb }
		world:Advance(3)
		a.inCombat = true
		HoverOver(a, herb)
		world:Advance(1)
		H.eq(#Received(b, "Pacifique"), 0, "rien lu en combat")
		a.inCombat = false
		world:Advance(0.5)
		H.eq(#Received(b, "Pacifique"), 1, "lue après le combat")
		NoErrors(a)
		NoErrors(b)
	end)

	-- vu en jeu (0.4.1) : une herbe survolée a donné 4 messages en 0,6 s, car la souris qui parcourt le point
	-- déplace la position estimée de plus de 8 m à chaque lecture
	local JITTER = { { 8, 0 }, { -8, 0 }, { 0, 8 }, { 0, -8 }, { 6, 6 }, { -6, -6 } }

	--- Survole la ressource pendant `seconds` en bougeant la souris sur son point (une position par 0,1 s).
	local function HoverJittering(world, client, blip, seconds)
		HoverOver(client, blip)
		local baseX, baseY = client.cursorX, client.cursorY
		for i = 1, math.floor(seconds * 10 + 0.5) do
			local offset = JITTER[(i - 1) % #JITTER + 1]
			client.cursorX, client.cursorY = baseX + offset[1], baseY + offset[2]
			world:Advance(0.1)
		end
	end

	--- Marqueur local (position suivie par le détecteur) de la ressource `name`.
	local function LocalMarker(client, name)
		local found
		client.ns.MarkerManager.ForEach(function(marker)
			if marker.name == name and marker.isLocal then
				found = marker
			end
		end, client.world.time)
		return found
	end

	H.test("souris qui bouge sur une herbe survolée : un renvoi de position au plus toutes les 2 s", function()
		local world, a, b = Grouped()
		a.probeRestricted = true
		local herb = Herb("Pacifique", 40, 30)
		a.worldBlips = { herb }
		world:Advance(3)
		HoverJittering(world, a, herb, 1)
		H.eq(CountSent(a, "N"), 1, "première seconde : l'annonce seule")
		HoverJittering(world, a, herb, 1.5)
		H.eq(CountSent(a, "N"), 2, "un renvoi après 2 s")
		HoverJittering(world, a, herb, 3.5)
		H.ok(CountSent(a, "N") <= 4, "au plus un renvoi par 2 s : " .. CountSent(a, "N") .. " envois en 6 s")
		local list = Received(b, "Pacifique")
		H.eq(#list, 1, "une seule herbe chez Aedot")
		local distance = b.ns.MarkerManager.DistanceYards(ELWYNN, list[1].marker.x, list[1].marker.y, herb.x, herb.y)
		H.ok(distance <= 15, string.format("position à %.1f m de la plante", distance))
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("position affinée en attente : envoyée après le survol", function()
		local world, a, b = Grouped()
		a.probeRestricted = true
		local herb = Herb("Pacifique", 40, 30)
		a.worldBlips = { herb }
		world:Advance(3)
		HoverJittering(world, a, herb, 0.6)
		a.mouseOverMinimap = false
		H.eq(CountSent(a, "N"), 1, "renvoi encore en attente")
		world:Advance(2.5)
		H.eq(CountSent(a, "N"), 2, "dernière position envoyée une fois le délai écoulé")
		local tracked, list = LocalMarker(a, "Pacifique"), Received(b, "Pacifique")
		H.ok(tracked ~= nil and #list == 1, "herbe suivie et reçue")
		local gap = b.ns.MarkerManager.DistanceYards(ELWYNN, list[1].marker.x, list[1].marker.y, tracked.x, tracked.y)
		H.ok(gap < 0.5, string.format("Aedot a la position affinée (écart %.2f m)", gap))
		world:Advance(10)
		H.eq(CountSent(a, "N"), 2, "rien de plus sans nouveau survol")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("mode survol, nouveau membre : pas de renvoi à chaque lecture au survol", function()
		local world, a, b, h1 = BlindPair()
		-- un membre arrive : les ressources visibles lui sont renvoyées au prochain balayage
		a.ns.Fire("PGR_PEERS_CHANGED")
		local before = CountSent(a, "N")
		HoverOver(a, h1)
		world:Advance(3)
		local sent = CountSent(a, "N") - before
		H.ok(sent <= 2, "au plus un envoi par 2 s juste après l'arrivée : " .. sent)
		a.mouseOverMinimap = false
		world:Advance(35)
		before = CountSent(a, "N")
		HoverOver(a, h1)
		world:Advance(3)
		H.eq(CountSent(a, "N") - before, 1, "après un balayage aveugle : un seul rafraîchissement")
		NoErrors(a)
		NoErrors(b)
	end)

	---------------------------------------------------------------------------
	H.suite("Sans souris (0.5.0) : détection de proximité et emplacements connus")
	---------------------------------------------------------------------------
	-- Proximité : la cible d'interaction douce du jeu (client.softTarget) nomme l'objet le plus proche du joueur ;
	-- elle n'existe que si le ciblage doux est actif au clavier. Emplacements connus : endroits déjà vus, gardés.

	local objectCounter = 0

	--- Objet ciblé par le ciblage doux du jeu. `guidType` : "GameObject" (défaut) ou "Creature" (PNJ).
	local function SoftObject(name, inReach, guidType)
		objectCounter = objectCounter + 1
		return { name = name, inReach = inReach or false,
			guid = string.format("%s-0-1-0-1429-1618-%08X", guidType or "GameObject", objectCounter) }
	end

	local function TooltipHas(client, text)
		for _, line in ipairs(client.tooltipLines) do
			if tostring(line):find(text, 1, true) then
				return true
			end
		end
		return false
	end

	H.test("proximité, sans souris : une herbe ciblée par le jeu à 8 m d'Aekiss apparaît chez Aedot", function()
		local world, a, b = Grouped()
		a.probeRestricted = true
		a:Slash("near on")
		H.eq(a.cvars.SoftTargetInteract, "3", "ciblage doux toujours actif")
		H.eq(a.cvars.SoftTargetInteractArc, "2", "tout autour du joueur")
		H.eq(a.cvars.SoftTargetInteractOnlyInRange, "0", "au-delà de la portée d'interaction")
		H.eq(a.cvars.SoftTargetInteractRange, "15", "portée demandée")
		H.ok(a:ChatContains("détection de proximité activée"), "message d'activation")
		local herb = Herb("Pacifique", 8, 0)
		a:SetSoftTarget(SoftObject("Pacifique"))
		world:Advance(0.1)
		local list = Received(b, "Pacifique")
		H.eq(#list, 1, "partagée sans survol")
		H.eq(list[1].status, "ACTIVE")
		local marker = list[1].marker
		local distance = b.ns.MarkerManager.DistanceYards(ELWYNN, marker.x, marker.y, herb.x, herb.y)
		H.ok(distance <= 15, string.format("position à %.1f m de la plante", distance))
		H.eq(marker.accuracy, 15, "précision annoncée : portée de la cible douce")
		H.eq(CountSent(a, "N"), 1, "une annonce")
		H.ok(LogContains(a, "herbe : Pacifique") and LogContains(a, "(proximité)"), "découverte journalisée")
		world:Advance(10)
		H.eq(CountSent(a, "N"), 1, "même cible : pas de flot")
		-- à portée d'interaction : position plus précise
		a.softTarget.inReach = true
		world:Advance(0.6)
		H.eq(LocalMarker(a, "Pacifique").accuracy, 5, "à portée : ±5 m")
		world:Advance(20)
		H.eq(CountSent(a, "N"), 2, "cible gardée : un rafraîchissement après 25 s (file d'envoi comprise)")
		H.eq(Received(b, "Pacifique")[1].status, "ACTIVE")
		a:Slash("status")
		H.ok(a:ChatContains("réglage oui, ciblage doux du jeu actif, 1 ressource%(s%) vue%(s%) de près"), "statut")
		H.eq(#VisiblePins(a), 0, "aucun doublon sur la minicarte d'Aekiss")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("proximité : une vue lointaine ne dégrade pas une position précise", function()
		local world, a = Grouped()
		a:Slash("near on")
		local herb = SoftObject("Pacifique", true)
		a:SetSoftTarget(herb)
		world:Advance(0.1)
		local tracked = LocalMarker(a, "Pacifique")
		H.eq(tracked.accuracy, 5, "vue à portée d'interaction")
		local x0, y0 = tracked.x, tracked.y
		-- le joueur s'éloigne de 12 m, cible autre chose, puis de nouveau la plante, hors de portée
		a.x = a.x + 12 / MAP.width
		a:SetSoftTarget(SoftObject("Coffre solide"))
		world:Advance(0.6)
		herb.inReach = false
		a:SetSoftTarget(herb)
		world:Advance(0.6)
		tracked = LocalMarker(a, "Pacifique")
		H.eq(a.ns.AutoDetect.GetNodeCount(), 1, "même plante")
		H.near(a.ns.MarkerManager.DistanceYards(ELWYNN, x0, y0, tracked.x, tracked.y), 0, 0.01, "position gardée")
		H.eq(tracked.accuracy, 5)
		NoErrors(a)
	end)

	H.test("proximité sans pistage : Aedot partage un filon vu de près", function()
		local world, a, b = Grouped()
		b:Slash("near on")
		b:SetSoftTarget(SoftObject("Filon de cuivre", true))
		world:Advance(0.1)
		local list = Received(a, "Filon de cuivre")
		H.eq(#list, 1, "filon reçu par Aekiss")
		H.eq(list[1].marker.kind, "ORE")
		H.eq(list[1].marker.accuracy, 5)
		H.eq(b.ns.AutoDetect.stats.near, 1)
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("ciblage doux du jeu inactif : rien n'est lu ; /pgr near off rétablit les réglages d'origine", function()
		local world, a, b = Grouped()
		a:SetSoftTarget(SoftObject("Pacifique"))
		world:Advance(1)
		H.eq(#Received(b, "Pacifique"), 0, "ciblage doux inactif dans le jeu : aucune cible")
		a:Slash("near on")
		world:Advance(0.6)
		H.eq(#Received(b, "Pacifique"), 1, "cible lue dès l'activation")
		H.eq(a.env.PartyGatherRadarDB.proximityCVars.SoftTargetInteract, "1", "valeur d'origine gardée")
		a.cvars.SoftTargetInteractArc = "1" -- changé par le joueur entre-temps
		a:Slash("near off")
		H.eq(a.cvars.SoftTargetInteract, "1", "rétabli")
		H.eq(a.cvars.SoftTargetInteractOnlyInRange, "1", "rétabli")
		H.eq(a.cvars.SoftTargetInteractRange, "10", "rétabli")
		H.eq(a.cvars.SoftTargetInteractArc, "1", "réglage changé par le joueur : laissé")
		H.eq(a.env.PartyGatherRadarDB.proximityCVars, nil)
		H.ok(a:ChatContains("détection de proximité arrêtée"), "message d'arrêt")
		NoErrors(a)
	end)

	H.test("en combat : réglages posés après le combat ; portée plus grande gardée ; /reload sans réécriture", function()
		local world, a = Grouped()
		a.cvars.SoftTargetInteractRange = "60"
		a.inCombat = true
		a:Slash("near on")
		H.eq(a.cvars.SoftTargetInteract, "1", "rien n'est changé en combat")
		H.ok(a:ChatContains("en combat : les réglages du jeu seront changés à la fin du combat"), "message")
		world:Advance(1)
		H.eq(a.cvars.SoftTargetInteract, "1", "toujours en combat")
		a.inCombat = false
		world:Advance(0.6)
		H.eq(a.cvars.SoftTargetInteract, "3", "posés après le combat")
		H.eq(a.cvars.SoftTargetInteractRange, "60", "portée jamais réduite")
		local writes = a.cvarWrites
		a:Reload()
		world:Advance(1)
		H.eq(a.cvarWrites, writes, "/reload : rien à réécrire")
		H.eq(a.ns.Config.Get("proximityDetect"), true, "réglage conservé")
		a:Slash("near off")
		H.eq(a.cvars.SoftTargetInteract, "1", "rétabli après /reload")
		H.eq(a.cvars.SoftTargetInteractRange, "60", "portée d'origine intacte")
		NoErrors(a)
	end)

	H.test("cible douce sans ressource (PNJ, coffre, nom secret) ou en combat : rien n'est partagé", function()
		local world, a, b = Grouped()
		a:Slash("near on")
		a:SetSoftTarget(SoftObject("Pacifique", false, "Creature"))
		world:Advance(0.6)
		a:SetSoftTarget(SoftObject("Coffre solide"))
		world:Advance(0.6)
		local secret = SoftObject("Pacifique")
		secret.secret = true
		a:SetSoftTarget(secret)
		world:Advance(0.6)
		H.ok(LogContains(a, "objet ciblé sans nom lisible"), "nom illisible journalisé")
		a.inCombat = true
		a:SetSoftTarget(SoftObject("Feuillargent"))
		world:Advance(0.6)
		H.eq(CountSent(a, "N"), 0, "rien partagé")
		a.inCombat = false
		world:Advance(0.6)
		H.eq(#Received(b, "Feuillargent"), 1, "lue après le combat")
		H.eq(#Received(b, "Pacifique"), 0)
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("emplacements connus : herbe reçue mémorisée chez Aedot, affichée après expiration et après /reload", function()
		local world, a, b = Grouped()
		a.probeRestricted = true
		local herb = Herb("Pacifique", 40, 30)
		a.worldBlips = { herb }
		HoverThenLeave(world, a, herb)
		H.eq(b.ns.KnownSpots.Count(ELWYNN), 1, "emplacement mémorisé chez Aedot")
		local pins = VisiblePins(b)
		H.eq(#pins, 1, "la détection seule est affichée")
		H.ok(pins[1].marker ~= nil, "pas d'emplacement superposé à la détection")
		world:Advance(310)
		H.eq(#Received(b, "Pacifique"), 0, "détection expirée")
		pins = VisiblePins(b)
		H.eq(#pins, 1, "emplacement connu affiché sans nouveau survol")
		H.ok(pins[1].spot ~= nil and pins[1].status == "HISTORY", "marqueur discret")
		local spot = pins[1].spot
		local distance = b.ns.MarkerManager.DistanceYards(ELWYNN, spot.x, spot.y, herb.x, herb.y)
		H.ok(distance <= 15, string.format("emplacement à %.1f m de la plante", distance))
		pins[1].scripts.OnEnter(pins[1])
		H.ok(TooltipHas(b, "Pacifique") and TooltipHas(b, "Emplacement connu"), "infobulle : nom et état")
		H.ok(TooltipHas(b, "Présence actuelle non confirmée"), "présence jamais affirmée")
		b:Reload()
		world:Advance(3)
		H.eq(#VisiblePins(b), 1, "gardé d'une session à l'autre")
		-- Aekiss piste les herbes : ses points natifs suffisent, l'emplacement n'est pas dessiné par-dessus
		H.eq(a.ns.KnownSpots.Count(ELWYNN), 1)
		H.eq(#VisiblePins(a), 0, "aucune icône sur la minicarte de qui piste ce type")
		-- nouvelle détection : elle remplace l'emplacement à l'affichage
		HoverThenLeave(world, a, herb)
		pins = VisiblePins(b)
		H.eq(#pins, 1)
		H.ok(pins[1].marker ~= nil and pins[1].status == "ACTIVE", "détection récente affichée à la place")
		H.eq(b.ns.KnownSpots.Count(ELWYNN), 1, "même emplacement")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("récolte : emplacement mémorisé à la position du joueur, même sans pistage ; réception coupée", function()
		local world, a, b = Grouped()
		local x, y = At(60, 0)
		SendLive(a, "n1", x, y)
		world:Advance(310)
		H.eq(#VisiblePins(b), 1, "emplacement reçu affiché")
		b:Slash("receive off")
		world:Advance(1.1)
		H.eq(#VisiblePins(b), 0, "réception coupée : emplacement seulement reçu masqué")
		b:FireEvent("UNIT_SPELLCAST_SENT", "player", "Feuillargent", "Cast-1", 2366)
		b:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2366)
		world:Advance(1.1)
		H.eq(b.ns.KnownSpots.Count(ELWYNN), 2, "cueillette mémorisée")
		H.eq(#VisiblePins(b), 0, "la plante vient d'être cueillie : pas d'icône à sa place")
		H.ok(LogContains(b, "emplacement de récolte : Feuillargent"), "journalisé")
		world:Advance(300)
		local pins = VisiblePins(b)
		H.eq(#pins, 1, "5 min plus tard : son propre emplacement est affiché")
		H.eq(pins[1].spot.n, "Feuillargent")
		H.eq(pins[1].spot.a, 5, "à portée de la plante : ±5 m")
		NoErrors(b)
	end)

	H.test("emplacement d'une herbe cueillie par un autre membre : masqué 5 min, puis affiché ; revue : affiché", function()
		local world, a, b = Grouped()
		local x, y = At(40, 0)
		SendLive(a, "n1", x, y)
		world:Advance(1)
		H.eq(#Received(b, "Pacifique"), 1, "détection reçue")
		a.ns.Sender.SendRemove("n1", "GATHERED")
		world:Advance(1.1)
		H.eq(#Received(b, "Pacifique"), 0, "retirée")
		H.eq(b.ns.KnownSpots.Count(ELWYNN), 1, "emplacement gardé")
		H.eq(#VisiblePins(b), 0, "pas d'icône juste après la cueillette")
		b:Reload()
		world:Advance(3)
		H.eq(#VisiblePins(b), 0, "toujours masqué après /reload")
		world:Advance(300)
		H.eq(#VisiblePins(b), 1, "affiché 5 min plus tard")
		-- revue avant la fin du délai : la marque est levée
		local spot
		b.ns.KnownSpots.ForEachOnMap(ELWYNN, function(s) spot = s end)
		b.ns.KnownSpots.MarkGathered("HERB", ELWYNN, x, y, 5)
		world:Advance(1.1)
		H.eq(#VisiblePins(b), 0, "de nouveau cueillie")
		H.eq(select(2, b.ns.KnownSpots.Record("ORE", "Filon de cuivre", ELWYNN, x, y, 5, false)), "created",
			"un filon au même endroit n'est pas concerné")
		b.ns.KnownSpots.Record("HERB", "Pacifique", ELWYNN, x, y, 5, false)
		H.eq(spot.g, nil, "revue : marque levée")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("emplacements : fusion, position la plus précise, bornes, /pgr spots, /pgr clear les garde", function()
		local world, a = Grouped()
		local KS = a.ns.KnownSpots
		local x1, y1 = At(0, 0)
		local x2, y2 = At(8, 0)
		local x3, y3 = At(3, 0)
		local x4, y4 = At(30, 0)
		KS.Record("HERB", "Pacifique", ELWYNN, x1, y1, 12, true)
		local spot, action = KS.Record("HERB", "Feuillargent", ELWYNN, x2, y2, 5, false)
		H.eq(action, "updated", "même type à 8 m : même emplacement")
		H.eq(KS.Count(ELWYNN), 1)
		H.eq(spot.c, 2, "vu deux fois")
		H.eq(spot.n, "Feuillargent", "dernier nom vu")
		H.eq(spot.a, 5, "position la plus précise gardée")
		H.near(spot.x, x2, 1e-9)
		KS.Record("HERB", "Pacifique", ELWYNN, x3, y3, 15, false)
		H.near(spot.x, x2, 1e-9, "moins précis : position inchangée")
		H.eq(select(2, KS.Record("ORE", "Filon de cuivre", ELWYNN, x2, y2, 5, true)), "created", "autre type")
		H.eq(select(2, KS.Record("HERB", "Pacifique", ELWYNN, x4, y4, 12, true)), "created", "à 30 m : autre emplacement")
		H.eq(KS.Count(ELWYNN), 3)
		H.eq(KS.Record("TEST", "x", ELWYNN, 0.5, 0.5), nil, "type TEST refusé")
		H.eq(KS.Record("HERB", "x", ELWYNN, 2, 0.5), nil, "coordonnée hors carte refusée")
		H.eq(KS.Record("HERB", "x", 999999, 0.5, 0.5), nil, "carte sans dimensions refusée")
		-- borne par carte : le moins récemment vu part
		KS.MAX_PER_MAP = 5
		for i = 1, 10 do
			local x, y = At(100 + i * 40, 0)
			KS.Record("HERB", "Pacifique", ELWYNN, x, y, 12, true, 1900000000 + i)
		end
		H.eq(KS.Count(ELWYNN), 5, "borne par carte")
		local oldest
		KS.ForEachOnMap(ELWYNN, function(s)
			oldest = math.min(oldest or s.t, s.t)
		end)
		H.eq(oldest, 1900000006, "les plus récents gardés")
		KS.MAX_PER_MAP = 300
		a:Slash("spots")
		H.ok(a:ChatContains("emplacements connus : 5 sur cette carte, 5 en tout"), "/pgr spots")
		a:Slash("clear")
		H.eq(KS.Count(), 5, "/pgr clear garde les emplacements connus")
		a:Slash("spots clear")
		H.eq(KS.Count(), 0)
		H.ok(a:ChatContains("5 emplacement%(s%) connu%(s%) effacé%(s%)"), "/pgr spots clear")
		NoErrors(a)
	end)

	H.test("emplacements : deux vues imprécises d'un même objet fusionnées jusqu'à 30 m, précises jamais", function()
		local world, a = Grouped()
		local KS = a.ns.KnownSpots
		-- deux vues imprécises d'un même objet, de deux côtés opposés : même emplacement ; précises : deux
		local west, westY = At(-200, 0)
		local east, eastY = At(-172, 0)
		KS.Record("HERB", "Pacifique", ELWYNN, west, westY, 15, false)
		H.eq(select(2, KS.Record("HERB", "Pacifique", ELWYNN, east, eastY, 15, false)), "updated", "±15 m à 28 m : fusion")
		local far, farY = At(-140, 0)
		H.eq(select(2, KS.Record("HERB", "Pacifique", ELWYNN, far, farY, 15, false)), "created", "au-delà de 30 m : jamais")
		local vague, vagueY = At(-104, 0)
		H.eq(select(2, KS.Record("HERB", "Pacifique", ELWYNN, vague, vagueY, 40, false)), "created",
			"très imprécise à 36 m : jamais fusionnée (30 m au plus)")
		local near1, near1Y = At(-300, 0)
		local near2, near2Y = At(-280, 0)
		KS.Record("HERB", "Pacifique", ELWYNN, near1, near1Y, 5, false)
		H.eq(select(2, KS.Record("HERB", "Pacifique", ELWYNN, near2, near2Y, 5, false)), "created", "±5 m à 20 m : deux")
		H.eq(KS.Count(ELWYNN), 5)
		NoErrors(a)
	end)

	H.test("emplacements modifiés à la main dans les SavedVariables : invalides retirés, sans erreur", function()
		local world = H.NewWorld(root)
		local c = world:NewClient({ name = "Aedot" })
		c.savedVariables = { knownSpots = {
			[ELWYNN] = {
				{ x = 0.5, y = 0.5, k = "HERB", n = "Pacifique", a = 12, t = 1800000000, c = 2, m = true },
				{ x = 2, y = 0.5, k = "HERB", t = 1 },
				{ x = 0.4, y = 0.4, k = "TEST", t = 1 },
				"texte",
				{ x = 0.6, y = 0.6, k = "ORE", t = 1800000000, a = -3, c = "beaucoup", n = 42, m = "oui", g = "hier" },
			},
			[-5] = { { x = 0.5, y = 0.5, k = "HERB", t = 1 } },
			Elwynn = {},
			[1436] = "pas une liste",
		} }
		c:Login(false)
		local KS = c.ns.KnownSpots
		H.eq(KS.Count(), 2, "deux emplacements valides")
		local ore
		KS.ForEachOnMap(ELWYNN, function(spot)
			if spot.k == "ORE" then
				ore = spot
			end
		end)
		H.eq(ore.a, 15, "précision invalide remplacée")
		H.eq(ore.c, 1, "nombre de vues invalide remplacé")
		H.eq(ore.n, nil, "nom invalide retiré")
		H.eq(ore.m, nil, "drapeau invalide retiré")
		H.eq(ore.g, nil, "date de récolte invalide retirée")
		local stored = c.env.PartyGatherRadarDB.knownSpots
		H.eq(stored[-5], nil)
		H.eq(stored.Elwynn, nil)
		H.eq(stored[1436], nil)
		world:Advance(1.1)
		NoErrors(c)
	end)

	H.test("/pgr near off en combat puis /reload avant la fin du combat : réglages rétablis ensuite", function()
		local world, a = Grouped()
		a:Slash("near on")
		H.eq(a.cvars.SoftTargetInteract, "3")
		a.inCombat = true
		a:Slash("near off")
		H.eq(a.cvars.SoftTargetInteract, "3", "rien n'est changé en combat")
		a:Reload()
		world:Advance(1)
		H.eq(a.cvars.SoftTargetInteract, "3", "toujours en combat après /reload")
		a.inCombat = false
		world:Advance(0.6)
		H.eq(a.cvars.SoftTargetInteract, "1", "rétabli après le combat, malgré le /reload")
		H.eq(a.cvars.SoftTargetInteractArc, "0")
		H.eq(a.cvars.SoftTargetInteractOnlyInRange, "1")
		H.eq(a.cvars.SoftTargetInteractRange, "10")
		H.eq(a.env.PartyGatherRadarDB.proximityCVars, nil, "valeurs d'origine oubliées une fois rétablies")
		-- réglage coupé : la cible douce n'est pas lue, même activée par le joueur dans le jeu
		a.cvars.SoftTargetInteract = "3"
		a:SetSoftTarget(SoftObject("Pacifique"))
		world:Advance(1)
		H.eq(CountSent(a, "N"), 0, "réglage coupé : rien n'est lu")
		NoErrors(a)
	end)

	H.test("proximité : même objet vu de deux côtés opposés : une ressource, un marqueur, un emplacement", function()
		local world, a, b = Grouped()
		a:Slash("near on")
		local x0, y0 = a.x, a.y
		local object = SoftObject("Pacifique")
		a:SetSoftTarget(object)
		world:Advance(0.1)
		-- l'objet est à 14 m à l'est du départ : le joueur passe à 14 m de l'autre côté
		a.x = x0 + 28 / MAP.width
		world:Advance(6)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 1, "même GUID : une seule ressource")
		local tracked = LocalMarker(a, "Pacifique")
		local middleX = x0 + 14 / MAP.width
		H.near(a.ns.MarkerManager.DistanceYards(ELWYNN, tracked.x, tracked.y, middleX, y0), 0, 0.5,
			"position entre les deux vues")
		world:Advance(25)
		H.eq(#Received(b, "Pacifique"), 1, "un seul marqueur chez Aedot")
		H.eq(a.ns.KnownSpots.Count(ELWYNN), 1, "un seul emplacement chez Aekiss")
		H.eq(b.ns.KnownSpots.Count(ELWYNN), 1, "un seul emplacement chez Aedot")
		-- un autre objet du même nom, tout près : jamais fusionné avec le premier
		a:SetSoftTarget(SoftObject("Pacifique"))
		world:Advance(0.6)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 2, "autre GUID : autre ressource")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("proximité : vue à portée après une vue lointaine : position remplacée, précision exacte", function()
		local world, a, b = Grouped()
		a:Slash("near on")
		local x0 = a.x
		local object = SoftObject("Pacifique")
		a:SetSoftTarget(object)
		world:Advance(0.1)
		H.eq(LocalMarker(a, "Pacifique").accuracy, 15)
		-- le joueur marche 13 m jusqu'à la plante
		a.x = x0 + 13 / MAP.width
		object.inReach = true
		world:Advance(0.6)
		local tracked = LocalMarker(a, "Pacifique")
		H.eq(tracked.accuracy, 5, "à portée : ±5 m")
		H.near(a.ns.MarkerManager.DistanceYards(ELWYNN, tracked.x, tracked.y, a.x, a.y), 0, 0.01,
			"position du joueur à portée, pas une moyenne avec la vue lointaine")
		H.ok(LogContains(a, "proximité : Pacifique ciblé à environ 13 m"), "distance de ciblage journalisée")
		world:Advance(3)
		local list = Received(b, "Pacifique")
		H.eq(#list, 1)
		H.eq(list[1].marker.accuracy, 5, "précision reçue")
		H.ok(b.ns.MarkerManager.DistanceYards(ELWYNN, list[1].marker.x, list[1].marker.y, a.x, a.y) < 0.5,
			"position affinée reçue")
		local spot
		a.ns.KnownSpots.ForEachOnMap(ELWYNN, function(s) spot = s end)
		H.eq(spot.a, 5, "emplacement : ±5 m")
		H.near(a.ns.MarkerManager.DistanceYards(ELWYNN, spot.x, spot.y, a.x, a.y), 0, 0.01)
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("proximité : herbe cueillie encore ciblée le temps de disparaître : pas renvoyée, reste masquée", function()
		local world, a, b = Grouped()
		a:Slash("near on")
		local object = SoftObject("Pacifique", true)
		a:SetSoftTarget(object)
		world:Advance(3)
		H.eq(#Received(b, "Pacifique"), 1, "vue de près, partagée")
		local sent = CountSent(a, "N")
		-- cueillette réussie ; la cible douce désigne encore la plante (en jeu : 0,3 s après)
		a:FireEvent("UNIT_SPELLCAST_SENT", "player", "Pacifique", "Cast-1", 2366)
		a:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2366)
		world:Advance(6)
		H.eq(CountSent(a, "N"), sent, "plante cueillie : pas de nouvelle annonce")
		H.eq(a.ns.AutoDetect.GetNodeCount(), 0, "plus suivie")
		H.eq(#Received(b, "Pacifique"), 0, "retirée chez Aedot")
		H.ok(LogContains(a, "proximité : Pacifique ignorée, cueillie à l'instant"), "journalisé")
		local spot
		a.ns.KnownSpots.ForEachOnMap(ELWYNN, function(s) spot = s end)
		H.ok(spot and spot.g ~= nil, "emplacement toujours marqué cueilli")
		H.eq(#VisiblePins(b), 0, "rien chez Aedot : ni marqueur ni emplacement")
		-- autre objet du même nom, tout près : une autre plante, signalée
		a:SetSoftTarget(SoftObject("Pacifique", true))
		world:Advance(0.6)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 1, "autre GUID : signalée")
		-- la plante cueillie reste là (butin laissé) : signalée de nouveau après 60 s
		a:SetSoftTarget(object)
		world:Advance(50)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 1, "avant 60 s : toujours ignorée")
		world:Advance(10)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 2, "après 60 s : signalée")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("proximité : herbe trouvée au survol puis cueillie : même nom à portée ignoré, autre nom signalé", function()
		local world, a, b = Grouped()
		a.probeRestricted = true
		a:Slash("near on")
		local herb = Herb("Pacifique", 3, 0)
		a.worldBlips = { herb }
		HoverThenLeave(world, a, herb)
		H.eq(#Received(b, "Pacifique"), 1, "trouvée au survol, sans GUID")
		a.worldBlips = {}
		a:FireEvent("UNIT_SPELLCAST_SENT", "player", "Pacifique", "Cast-1", 2366)
		a:FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2366)
		world:Advance(0.3)
		H.eq(#Received(b, "Pacifique"), 0, "retirée chez Aedot")
		-- la cible douce désigne la plante cueillie : même nom, à l'endroit de la cueillette
		a:SetSoftTarget(SoftObject("Pacifique", true))
		world:Advance(3)
		H.eq(a.ns.AutoDetect.GetNodeCount(), 0, "même nom à portée : ignorée")
		H.eq(#Received(b, "Pacifique"), 0)
		-- une autre plante à portée : signalée
		a:SetSoftTarget(SoftObject("Feuillargent", true))
		world:Advance(3)
		H.eq(#Received(b, "Feuillargent"), 1, "autre nom : signalée")
		NoErrors(a)
		NoErrors(b)
	end)

	H.test("détection reçue masquée par un réglage : l'emplacement connu voisin reste affiché", function()
		local world, a, b = Grouped()
		local x, y = At(40, 0)
		SendLive(a, "n1", x, y)
		world:Advance(1.1)
		local pins = VisiblePins(b)
		H.eq(#pins, 1)
		H.ok(pins[1].marker ~= nil, "détection affichée, pas l'emplacement")
		b.ns.Config.Set("showLive", false)
		world:Advance(1.1)
		pins = VisiblePins(b)
		H.eq(#pins, 1, "détections masquées : l'emplacement connu est affiché")
		H.ok(pins[1].spot ~= nil and pins[1].status == "HISTORY")
		NoErrors(b)
	end)

	H.test("emplacements : bornes sur toutes les cartes ; ceux reçus du groupe partent avant les siens", function()
		local world, a = Grouped()
		local KS = a.ns.KnownSpots
		local WESTFALL = 1436
		KS.MAX_TOTAL = 6
		for i = 1, 3 do
			local x, y = At(i * 40, 0)
			KS.Record("HERB", "Pacifique", ELWYNN, x, y, 5, true, 1900000000 + i)
		end
		for i = 1, 6 do
			KS.Record("HERB", "Pacifique", WESTFALL, 0.1 + i * 0.05, 0.5, 5, false, 1900000100 + i)
		end
		H.eq(KS.Count(), 6, "borne totale")
		H.eq(KS.Count(ELWYNN), 3, "ses propres emplacements gardés, même plus anciens")
		H.eq(KS.Count(WESTFALL), 3, "les plus anciens reçus retirés")
		-- borne par carte : le plus ancien reçu part, pas le sien plus ancien
		KS.MAX_TOTAL, KS.MAX_PER_MAP = 3000, 4
		local x, y = At(400, 0)
		KS.Record("HERB", "Pacifique", ELWYNN, x, y, 5, false, 1900000200)
		x, y = At(440, 0)
		KS.Record("HERB", "Pacifique", ELWYNN, x, y, 5, false, 1900000300)
		H.eq(KS.Count(ELWYNN), 4)
		local own, oldestReceived = 0, nil
		KS.ForEachOnMap(ELWYNN, function(s)
			if s.m then
				own = own + 1
			else
				oldestReceived = math.min(oldestReceived or s.t, s.t)
			end
		end)
		H.eq(own, 3, "aucun des siens retiré")
		H.eq(oldestReceived, 1900000300, "le reçu le plus ancien est parti")
		-- carte vidée par la borne totale puis de nouveau remplie
		KS.MAX_PER_MAP = 300
		KS.Clear()
		KS.MAX_TOTAL = 1
		KS.Record("HERB", "Pacifique", WESTFALL, 0.2, 0.5, 5, true, 1900000400)
		KS.Record("HERB", "Pacifique", WESTFALL, 0.6, 0.5, 5, true, 1900000500)
		H.eq(KS.Count(WESTFALL), 1, "liste retirée puis recréée")
		H.eq(KS.Count(), 1)
		KS.MAX_TOTAL = 3000
		NoErrors(a)
	end)

	H.test("boucle d'affichage : arrêtée sans rien d'affichable sur la carte, relancée par le pistage", function()
		local world, a = Grouped()
		local KS = a.ns.KnownSpots
		local x, y = At(40, 0)
		KS.Record("HERB", "Pacifique", ELWYNN, x, y, 5, true)
		world:Advance(1.1)
		H.eq(a.ns.MinimapOverlay.IsUpdating(), false, "pistage des herbes actif : rien à suivre")
		a.tracking = { H.ORE_TRACKING }
		a:FireEvent("MINIMAP_UPDATE_TRACKING")
		world:Advance(1.1)
		H.eq(a.ns.MinimapOverlay.IsUpdating(), true, "pistage des herbes coupé : emplacement suivi")
		H.eq(#VisiblePins(a), 1, "emplacement affiché")
		KS.Clear()
		KS.Record("HERB", "Pacifique", 1436, 0.5, 0.5, 5, true)
		world:Advance(1.1)
		H.eq(a.ns.MinimapOverlay.IsUpdating(), false, "emplacements d'une autre carte seulement : boucle arrêtée")
		H.eq(#VisiblePins(a), 0)
		NoErrors(a)
	end)

	---------------------------------------------------------------------------
	H.suite("Discussion : « Aucun joueur nommé » causé par un autre addon")
	---------------------------------------------------------------------------
	-- Un autre addon (ForeverGuide 1.39.5 en jeu) chuchote un membre du groupe sous la forme « Prénom-Nom » : le
	-- serveur répond qu'il n'existe pas. PartyGatherRadar masque ce message faux, et lui seul.

	local function NotFound(client, name)
		return string.format(client.env.ERR_CHAT_PLAYER_NOT_FOUND_S, name)
	end

	H.test("masqué quand il vise un membre du groupe connecté ; gardé sinon ; /pgr quiet off", function()
		local world, a, b = RegionalGrouped()
		H.eq(a:SystemMessage(NotFound(a, "Aedot-Wnx")), false, "« Prénom-Nom » d'un membre connecté : masqué")
		H.eq(a:SystemMessage(NotFound(a, "Aedot")), false, "prénom seul : masqué")
		H.eq(a:SystemMessage(NotFound(a, "aedot-wnx")), false, "casse différente : masqué")
		H.eq(a:SystemMessage(NotFound(a, "Inconnu-Ailleurs")), true, "joueur hors du groupe : affiché")
		H.eq(a:SystemMessage("Aedot-Wnx est absent."), true, "autre message système : affiché")
		H.ok(a:ChatContains("Inconnu%-Ailleurs"), "message gardé dans la discussion")
		H.eq(a.ns.Diagnostics.counters.hiddenNotFound, 3, "masquages comptés")
		H.ok(LogContains(a, "masqué : Aedot-Wnx est dans le groupe et connecté"), "journalisé")
		b.offline = true
		H.eq(a:SystemMessage(NotFound(a, "Aedot-Wnx")), true, "membre déconnecté : affiché")
		b.offline = false
		a:Slash("quiet off")
		H.eq(a.ns.Config.Get("hideNotFound"), false)
		H.eq(a:SystemMessage(NotFound(a, "Aedot-Wnx")), true, "réglage coupé : affiché")
		a:Slash("quiet on")
		H.eq(a:SystemMessage(NotFound(a, "Aedot-Wnx")), false, "réglage rétabli")
		a:Slash("off")
		H.eq(a:SystemMessage(NotFound(a, "Aedot-Wnx")), true, "addon désactivé : affiché")
		a:Slash("on")
		a:Reload()
		world:Advance(3)
		H.eq(a:SystemMessage(NotFound(a, "Aedot-Wnx")), false, "après /reload : un seul filtre, toujours actif")
		NoErrors(a)
	end)

	H.test("client anglais et royaumes classiques : « Nom-Royaume » d'un membre masqué ; hors groupe affiché", function()
		local world, a, b = NewPair(nil, { name = "Aedot", locale = "enUS" })
		world:SetGroup({ a, b })
		world:Advance(3)
		H.eq(b:SystemMessage(NotFound(b, "Aekiss-Autre")), false, "membre connecté : masqué")
		H.eq(b:SystemMessage("No player named 'Aekiss' is currently playing."), false, "format anglais reconnu")
		world:SetGroup({})
		world:Advance(3)
		H.eq(b:SystemMessage(NotFound(b, "Aekiss")), true, "plus dans le groupe : affiché")
		NoErrors(b)
	end)

	H.test("motif du message : caractères spéciaux, %1$s, format absent ou secret", function()
		local _, a = NewPair()
		local Build = a.ns.ChatFilter.BuildPattern
		local plain = Build("No player named '%s' is currently playing.")
		H.eq(("No player named 'Aedot-Wnx' is currently playing."):match(plain), "Aedot-Wnx")
		H.eq(("No player named 'Aedot' is currently playingX"):match(plain), nil, "le point n'est pas un joker")
		local numbered = Build("[%1$s] (introuvable) 100% ?")
		H.eq(("[Aedot] (introuvable) 100% ?"):match(numbered), "Aedot", "%1$s et caractères magiques")
		H.eq(Build("aucun nom"), nil, "sans %s : rien")
		H.eq(Build(nil), nil)
		H.eq(Build(H.SECRET), nil, "format secret : rien")
		NoErrors(a)
	end)
end
