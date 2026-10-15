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
			if frame.frameType == "Button" and frame.shown and frame.point then
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
		H.eq(peersA[1].peer.addonVersion, "0.1.0")
		H.eq(#peersB, 1)
		H.eq(peersB[1].name, "Aekiss-Realm")
		H.ok(a:ChatContains("Aedot utilise PartyGatherRadar 0.1.0"), "annonce de découverte")
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
		H.eq(#VisiblePins(b), 0)
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
			"minimap off", "minimap on", "inconnue", "off", "on" }) do
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
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "2;H;0.3.0;1;5", "PARTY", "Aedot-Realm")
		a:FireEvent("CHAT_MSG_ADDON", "PGRadar", "2;N;a;L;H;D;1429;1;1;0;0;0;x", "PARTY", "Aedot-Realm")
		local warnings = 0
		for _, line in ipairs(a.chat) do
			if line:find("version de protocole non prise en charge", 1, true) then
				warnings = warnings + 1
			end
		end
		H.eq(warnings, 1)
		H.eq(a:ChatContains("Aedot utilise PartyGatherRadar 0.3.0"), nil)
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
end
