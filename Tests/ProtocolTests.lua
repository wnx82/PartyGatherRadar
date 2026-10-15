-- PartyGatherRadar - Tests/ProtocolTests.lua
-- Tests unitaires hors jeu : protocole, validation, déduplication, expiration, séparation TEST/réel,
-- géométrie, configuration, file d'envoi, localisation et cohérence du projet.

return function(H, root)
	local world = H.NewWorld(root)
	local solo = world:NewClient({ name = "Aekiss" })
	solo:Login(false)
	local ns = solo.ns
	local P, M, C = ns.Protocol, ns.MarkerManager, ns.Coordinates

	---------------------------------------------------------------------------
	H.suite("Projet : TOC, chargement, variables globales")
	---------------------------------------------------------------------------

	H.test("le TOC cible l'interface 16001 et la version 0.1.1", function()
		H.eq(world.metadata.Interface, "16001", "## Interface")
		H.eq(world.metadata.Version, "0.1.1", "## Version")
		H.eq(world.metadata.Version, ns.VERSION, "version du TOC et de Init.lua")
		H.eq(world.metadata.SavedVariables, "PartyGatherRadarDB", "## SavedVariables")
	end)

	H.test("chaque fichier du TOC existe et compile en Lua 5.1", function()
		for _, file in ipairs(world.tocFiles) do
			local chunk, err = loadfile(root .. "/" .. file)
			H.ok(chunk, file .. " : " .. tostring(err))
		end
	end)

	H.test("aucun fichier Lua de l'addon n'est absent du TOC", function()
		local listed = {}
		for _, file in ipairs(world.tocFiles) do
			listed[file] = true
		end
		for _, folder in ipairs({ "Core", "Detection", "Communication", "Map", "UI", "Localization" }) do
			local handle = io.popen and io.popen('dir /b "' .. (root .. "/" .. folder):gsub("/", "\\") .. '\\*.lua" 2>nul')
			if handle then
				for name in handle:lines() do
					H.ok(listed[folder .. "/" .. name], folder .. "/" .. name .. " absent du TOC")
				end
				handle:close()
			end
		end
	end)

	H.test("le chargement ne crée que les variables globales prévues", function()
		local unexpected = solo:UnexpectedGlobals()
		H.eq(#unexpected, 0, "globales inattendues : " .. table.concat(unexpected, ", "))
		H.ok(solo.env.SlashCmdList.PARTYGATHERRADAR, "commande /pgr inscrite")
		H.ok(solo.env.PartyGatherRadarDB, "SavedVariables initialisées")
	end)

	H.test("un événement inconnu du client est refusé sans erreur Lua", function()
		H.eq(ns.RegisterEvent("EVENEMENT_INEXISTANT", "Tests", function() end), false)
		local api = solo.env.__api
		api.C_EventUtils = { IsEventValid = function() return false end }
		H.eq(ns.RegisterEvent("AUTRE_EVENEMENT", "Tests", function() end), false)
		api.C_EventUtils = nil
	end)

	H.test("le préfixe PGRadar est inscrit au chargement", function()
		H.ok(solo.prefixes.PGRadar, "préfixe inscrit")
		H.ok(#ns.PREFIX <= 16, "préfixe de 16 caractères au plus")
	end)

	---------------------------------------------------------------------------
	H.suite("Protocole : encodage et décodage")
	---------------------------------------------------------------------------

	H.test("HELLO : aller-retour et demande de réponse", function()
		local text = assert(P.EncodeHello({ addonVersion = "0.1.0", minProto = 1, caps = 7 }, false))
		H.eq(text, "1;H;0.1.0;1;7", "texte HELLO")
		local message = assert(P.Decode(text))
		H.eq(message.type, "H")
		H.eq(message.addonVersion, "0.1.0")
		H.eq(message.minProto, 1)
		H.eq(message.caps, 7)
		H.eq(message.wantsReply, true)
		local reply = assert(P.Decode(assert(P.EncodeHello({ addonVersion = "0.1.0", caps = 0 }, true))))
		H.eq(reply.wantsReply, false, "réponse sans nouvelle demande")
	end)

	H.test("NODE : aller-retour avec 5 décimales et nom accentué", function()
		local node = {
			id = "a1b2", source = "LIVE", kind = "HERB", state = "DETECTED", uiMapID = 1429,
			x = 0.123456, y = 0.987654, accuracy = 6, age = 3, resourceID = 2447, name = "Pacifique",
		}
		local text = assert(P.EncodeNode(node))
		H.ok(#text <= 255, "taille")
		local message = assert(P.Decode(text))
		H.eq(message.type, "N")
		H.eq(message.id, "a1b2")
		H.eq(message.source, "LIVE")
		H.eq(message.kind, "HERB")
		H.eq(message.state, "DETECTED")
		H.eq(message.uiMapID, 1429)
		H.near(message.x, 0.12346, 1e-9, "x")
		H.near(message.y, 0.98765, 1e-9, "y")
		H.eq(message.accuracy, 6)
		H.eq(message.age, 3)
		H.eq(message.resourceID, 2447)
		H.eq(message.name, "Pacifique")
		local accented = assert(P.Decode(assert(P.EncodeNode({
			id = "z", source = "HISTORY", kind = "ORE", state = "UNCERTAIN", uiMapID = 1, x = 0, y = 1,
			name = "Gisement de thorium enrichi éclaté",
		}))))
		H.eq(accented.name, "Gisement de thorium enrichi éclaté")
		H.eq(accented.x, 0)
		H.eq(accented.y, 1)
	end)

	H.test("BYE, PING, PONG et REMOVE : aller-retour", function()
		H.eq(assert(P.Decode(assert(P.EncodeBye()))).type, "B")
		local ping = assert(P.Decode(assert(P.EncodePing("abc123", false))))
		H.eq(ping.type, "P")
		H.eq(ping.nonce, "abc123")
		H.eq(assert(P.Decode(assert(P.EncodePing("abc123", true)))).type, "p")
		local remove = assert(P.Decode(assert(P.EncodeRemove("a1", "GATHERED"))))
		H.eq(remove.id, "a1")
		H.eq(remove.reason, "GATHERED")
	end)

	H.test("nom tronqué à 48 octets sans couper un caractère UTF-8", function()
		local long = string.rep("é", 40) -- 80 octets
		local sanitized = P.SanitizeName(long)
		H.ok(#sanitized <= 48, "48 octets au plus")
		H.eq(sanitized, string.rep("é", 24), "24 caractères complets")
		-- message le plus long possible : identifiant de 12 caractères, tous les champs au maximum
		local text = assert(P.EncodeNode({
			id = "abcdefghijkl", source = "LIVE", kind = "HERB", state = "DETECTED", uiMapID = 9999999, x = 1, y = 1,
			accuracy = 999, age = 99999, resourceID = 99999999, name = long,
		}))
		H.eq(#text, 112, "taille maximale documentée")
		H.ok(#text <= 255, "sous la limite Blizzard")
	end)

	H.test("nom nettoyé : séparateurs, codes | et caractères de contrôle supprimés", function()
		local sanitized = P.SanitizeName("|cffff0000Rouge|r;\n\tTige")
		H.ok(not sanitized:find("|", 1, true), "pas de |")
		H.ok(not sanitized:find(";", 1, true), "pas de ;")
		H.ok(not sanitized:find("%c"), "pas de caractère de contrôle")
	end)

	H.test("Split conserve les champs vides et borne le nombre de champs", function()
		local fields, count = P.Split("a;;b;", ";", 10)
		H.eq(count, 4)
		H.eq(fields[2], "")
		H.eq(fields[4], "")
		H.eq(P.Split("1;2;3", ";", 2), nil, "trop de champs")
	end)

	---------------------------------------------------------------------------
	H.suite("Protocole : messages invalides")
	---------------------------------------------------------------------------

	local function Rejects(text, expectedReason)
		local message, reason = P.Decode(text)
		H.eq(message, nil, "message refusé : " .. tostring(text))
		if expectedReason then
			H.eq(reason, expectedReason, "motif pour " .. tostring(text))
		end
	end

	H.test("types et tailles invalides", function()
		Rejects(nil, "not_string")
		Rejects(42, "not_string")
		Rejects("", "too_long")
		Rejects(string.rep("a", 256), "too_long")
		Rejects("1", "malformed")
	end)

	H.test("versions invalides", function()
		Rejects("x;H;0.1.0;1;0", "bad_version")
		Rejects("0;B", "bad_version")
		Rejects("-1;B", "bad_version")
		Rejects("1e0;B", "bad_version")
		Rejects("2;B", "version_newer")
		Rejects("2;N;a;L;H;D;1;1;1;0;0;0;n", "version_newer")
	end)

	H.test("type inconnu et nombre de champs incorrect", function()
		Rejects("1;Z;truc", "unknown_type")
		Rejects("1;B;extra", "field_count")
		Rejects("1;P", "field_count")
		Rejects("1;H;0.1.0;1", "field_count")
		Rejects("1;H;0.1.0;1;0;extra", "field_count")
		Rejects("1;N;a;L;H;D;1429;1;1;0;0;0", "field_count")
	end)

	H.test("champs NODE invalides", function()
		local base = { "1", "N", "abc", "L", "H", "D", "1429", "50000", "50000", "5", "0", "0", "Pacifique" }
		local function With(index, value)
			local copy = {}
			for i = 1, #base do
				copy[i] = base[i]
			end
			copy[index] = value
			return table.concat(copy, ";")
		end
		H.ok(P.Decode(table.concat(base, ";")), "message de référence valide")
		Rejects(With(3, ""), "bad_id")
		Rejects(With(3, "a-b"), "bad_id")
		Rejects(With(4, "Q"), "bad_enum")
		Rejects(With(5, "Q"), "bad_enum")
		Rejects(With(6, "Q"), "bad_enum")
		Rejects(With(7, "0"), "bad_map")
		Rejects(With(7, "-3"), "bad_map")
		Rejects(With(8, "100001"), "bad_coord")
		Rejects(With(8, "-1"), "bad_coord")
		Rejects(With(8, "0x10"), "bad_coord")
		Rejects(With(9, "1.5"), "bad_coord")
		Rejects(With(10, "abc"), "bad_number")
		Rejects(With(13, " Pacifique"), "bad_name")
		Rejects(With(13, "Paci|Tfique"), "bad_name")
		Rejects(With(4, "T"), "test_mismatch")
		Rejects(With(5, "T"), "test_mismatch")
	end)

	H.test("l'encodeur refuse les données invalides", function()
		local valid = { id = "a", source = "LIVE", kind = "HERB", state = "DETECTED", uiMapID = 1, x = 0.5, y = 0.5 }
		local function Without(key, value)
			local copy = {}
			for k, v in pairs(valid) do
				copy[k] = v
			end
			copy[key] = value
			return copy
		end
		H.ok(P.EncodeNode(valid), "référence valide")
		H.eq(P.EncodeNode(Without("id", "a;b")), nil, "id avec séparateur")
		H.eq(P.EncodeNode(Without("x", 1.01)), nil, "x > 1")
		H.eq(P.EncodeNode(Without("x", 0 / 0)), nil, "x NaN")
		H.eq(P.EncodeNode(Without("uiMapID", 0)), nil, "carte 0")
		H.eq(P.EncodeNode(Without("source", "PUBLIC")), nil, "source inconnue")
		H.eq(P.EncodeHello({ addonVersion = "0.1.0;x" }), nil, "version avec séparateur")
		H.eq(P.EncodePing("toolongnonce"), nil, "nonce trop long")
	end)

	---------------------------------------------------------------------------
	H.suite("Protocole : gestion des versions")
	---------------------------------------------------------------------------

	H.test("un HELLO d'une version future reste lisible", function()
		local message = assert(P.Decode("2;H;0.3.0;2;5;champ-futur"))
		H.eq(message.proto, 2)
		H.eq(message.minProto, 2)
		H.eq(P.IsCompatible(message.proto, message.minProto), false, "protocole minimal 2 > 1")
		-- un pair v2 sait peut-être lire v1, mais ses propres messages v2 nous sont illisibles
		local tolerant = assert(P.Decode("2;h;0.2.0;1;5;champ-futur"))
		H.eq(P.IsCompatible(tolerant.proto, tolerant.minProto), false, "messages v2 illisibles")
	end)

	H.test("compatibilité", function()
		H.eq(P.IsCompatible(1, 1), true)
		H.eq(P.IsCompatible(2, 1), false)
		H.eq(P.IsCompatible(0, 1), false)
		H.eq(P.IsCompatible(nil, 1), false)
	end)

	---------------------------------------------------------------------------
	H.suite("Marqueurs : ajout, déduplication, expiration")
	---------------------------------------------------------------------------

	local function Live(sender, id, x, y, extra)
		local data = { sender = sender, id = id, source = "LIVE", kind = "HERB", state = "DETECTED", uiMapID = 1429,
			x = x, y = y, name = "Pacifique" }
		for k, v in pairs(extra or {}) do
			data[k] = v
		end
		return data
	end

	H.test("création puis mise à jour par le même émetteur", function()
		M.Reset()
		local marker, action = M.Upsert(Live("A-R", "1", 0.5, 0.5), 100)
		H.eq(action, "created")
		local _, action2 = M.Upsert(Live("A-R", "1", 0.5001, 0.5, { state = "UPDATED" }), 105)
		H.eq(action2, "updated")
		H.eq(M.Count(), 1)
		H.eq(marker.lastSeen, 105)
		H.near(marker.x, 0.5001, 1e-12)
	end)

	H.test("deux détections proches de deux joueurs fusionnent (< 5 m)", function()
		M.Reset()
		M.Upsert(Live("A-R", "1", 0.5, 0.5), 100)
		local dx = 3 / 3470 -- 3 m à l'est sur Elwynn
		local marker, action = M.Upsert(Live("B-R", "9", 0.5 + dx, 0.5), 101)
		H.eq(action, "merged")
		H.eq(M.Count(), 1)
		H.ok(marker.reporters["A-R"] and marker.reporters["B-R"], "deux émetteurs")
		-- une mise à jour de B touche le marqueur fusionné (alias)
		local _, action2 = M.Upsert(Live("B-R", "9", 0.5 + dx, 0.5), 110)
		H.eq(action2, "updated")
		H.eq(M.Count(), 1)
	end)

	H.test("pas de fusion au-delà de 5 m, entre types ou entre sources", function()
		M.Reset()
		M.Upsert(Live("A-R", "1", 0.5, 0.5), 100)
		M.Upsert(Live("B-R", "2", 0.5 + 10 / 3470, 0.5), 100)
		H.eq(M.Count(), 2, "10 m")
		M.Upsert(Live("B-R", "3", 0.5, 0.5, { kind = "ORE" }), 100)
		H.eq(M.Count(), 3, "minerai")
		M.Upsert(Live("B-R", "4", 0.5, 0.5, { source = "HISTORY" }), 100)
		H.eq(M.Count(), 4, "historique")
	end)

	H.test("statuts et expiration des détections LIVE", function()
		M.Reset()
		local marker = M.Upsert(Live("A-R", "1", 0.5, 0.5), 1000)
		H.eq(M.GetStatus(marker, 1059), "ACTIVE", "59 s")
		H.eq(M.GetStatus(marker, 1061), "UNCERTAIN", "61 s")
		H.eq(M.GetStatus(marker, 1299), "UNCERTAIN", "299 s")
		H.eq(M.Expire(1299), 0)
		H.eq(M.GetStatus(marker, 1301), nil, "301 s")
		H.eq(M.Expire(1301), 1)
		H.eq(M.Count(), 0)
	end)

	H.test("l'âge transmis recule la date de détection ; état incertain respecté", function()
		M.Reset()
		local marker = M.Upsert(Live("A-R", "1", 0.5, 0.5, { age = 50 }), 1000)
		H.eq(marker.lastSeen, 950)
		H.eq(M.GetStatus(marker, 1011), "UNCERTAIN")
		local uncertain = M.Upsert(Live("A-R", "2", 0.6, 0.5, { state = "UNCERTAIN" }), 1000)
		H.eq(M.GetStatus(uncertain, 1000), "UNCERTAIN")
	end)

	H.test("GONE supprime ; REMOVE retire la contribution", function()
		M.Reset()
		M.Upsert(Live("A-R", "1", 0.5, 0.5), 100)
		local _, action = M.Upsert(Live("A-R", "1", 0.5, 0.5, { state = "GONE" }), 101)
		H.eq(action, "removed")
		H.eq(M.Count(), 0)
		M.Upsert(Live("A-R", "2", 0.5, 0.5), 100)
		H.eq(M.Remove("A-R", "2", false), true)
		H.eq(M.Count(), 0)
	end)

	H.test("les positions historiques n'expirent pas et ne sont jamais ACTIVE", function()
		M.Reset()
		local marker = M.Upsert(Live("A-R", "h", 0.5, 0.5, { source = "HISTORY" }), 0)
		H.eq(M.GetStatus(marker, 1e6), "HISTORY")
		H.eq(M.Expire(1e6), 0)
	end)

	H.test("départ d'un émetteur : seules ses contributions disparaissent", function()
		M.Reset()
		M.Upsert(Live("A-R", "1", 0.5, 0.5), 100)
		M.Upsert(Live("B-R", "1", 0.5 + 2 / 3470, 0.5), 100) -- fusionné
		M.Upsert(Live("B-R", "2", 0.7, 0.7), 100)
		H.eq(M.Count(), 2)
		M.RemoveBySender("B-R")
		H.eq(M.Count(), 1, "le marqueur fusionné survit grâce à A")
		local survivor = M.Get("A-R", "1")
		H.ok(survivor and survivor.reporters["A-R"] and not survivor.reporters["B-R"], "B retiré")
		M.RemoveBySender("A-R")
		H.eq(M.Count(), 0)
	end)

	H.test("validation des marqueurs", function()
		M.Reset()
		H.eq(M.Upsert(Live("A-R", "1", 1.5, 0.5)), nil, "x hors bornes")
		H.eq(M.Upsert(Live("A-R", "1", 0 / 0, 0.5)), nil, "x NaN")
		H.eq(M.Upsert(Live("A-R", "1", 0.5, 0.5, { uiMapID = 0 })), nil, "carte 0")
		H.eq(M.Upsert(Live("", "1", 0.5, 0.5)), nil, "émetteur vide")
		H.eq(M.Upsert(Live("A-R", "1", 0.5, 0.5, { state = "PRESENT" })), nil, "état inconnu")
		H.eq(M.Count(), 0)
	end)

	---------------------------------------------------------------------------
	H.suite("Séparation des données TEST et réelles")
	---------------------------------------------------------------------------

	H.test("un marqueur TEST n'apparaît jamais parmi les données réelles", function()
		M.Reset()
		M.Upsert(Live("A-R", "1", 0.5, 0.5), 100)
		M.Upsert({ sender = "A-R", id = "t1", source = "TEST", kind = "TEST", state = "DETECTED", uiMapID = 1429,
			x = 0.5, y = 0.5, name = "TEST" }, 100)
		local real, test = M.Count()
		H.eq(real, 1)
		H.eq(test, 1)
		local seenReal = 0
		M.ForEach(function(marker, status)
			H.ok(marker.source ~= "TEST" and status ~= "TEST", "aucune donnée TEST dans le magasin réel")
			seenReal = seenReal + 1
		end, 100, "real")
		H.eq(seenReal, 1)
	end)

	H.test("mélanges TEST/réel refusés", function()
		M.Reset()
		local _, reason = M.Upsert({ sender = "A-R", id = "1", source = "TEST", kind = "HERB", state = "DETECTED",
			uiMapID = 1, x = 0.5, y = 0.5 })
		H.eq(reason, "test_mismatch")
		local _, reason2 = M.Upsert({ sender = "A-R", id = "1", source = "LIVE", kind = "TEST", state = "DETECTED",
			uiMapID = 1, x = 0.5, y = 0.5 })
		H.eq(reason2, "test_mismatch")
	end)

	H.test("un marqueur TEST au même endroit ne fusionne pas avec un réel", function()
		M.Reset()
		M.Upsert(Live("A-R", "1", 0.5, 0.5), 100)
		local marker, action = M.Upsert({ sender = "B-R", id = "1", source = "TEST", kind = "TEST", state = "DETECTED",
			uiMapID = 1429, x = 0.5, y = 0.5 }, 100)
		H.eq(action, "created")
		H.eq(marker.source, "TEST")
		H.eq(M.Get("A-R", "1").reporters["B-R"], nil)
	end)

	H.test("/pgr clear : TEST et LIVE supprimés, historique conservé ; ClearTest ne touche pas au réel", function()
		M.Reset()
		M.Upsert(Live("A-R", "1", 0.5, 0.5), 100)
		M.Upsert(Live("A-R", "2", 0.6, 0.6, { source = "HISTORY" }), 100)
		M.Upsert({ sender = "A-R", id = "t", source = "TEST", kind = "TEST", state = "DETECTED", uiMapID = 1, x = 0, y = 0 })
		H.eq(M.ClearTest(), 1)
		H.eq(M.Count(), 2)
		M.Upsert({ sender = "A-R", id = "t", source = "TEST", kind = "TEST", state = "DETECTED", uiMapID = 1, x = 0, y = 0 })
		M.ClearTemporary()
		local real, test = M.Count()
		H.eq(real, 1, "historique conservé")
		H.eq(test, 0)
	end)

	H.test("les marqueurs TEST expirent selon testTTL et sont bornés en nombre", function()
		M.Reset()
		local marker = M.Upsert({ sender = "A-R", id = "t", source = "TEST", kind = "TEST", state = "DETECTED",
			uiMapID = 1, x = 0, y = 0 }, 0)
		H.eq(M.GetStatus(marker, 119), "TEST")
		H.eq(M.GetStatus(marker, 121), nil)
		M.Reset()
		for i = 1, M.MAX_TEST + 15 do
			M.Upsert({ sender = "S" .. (i % 5), id = "t" .. i, source = "TEST", kind = "TEST", state = "DETECTED",
				uiMapID = 1, x = 0, y = 0 }, i)
		end
		local _, test = M.Count()
		H.eq(test, M.MAX_TEST, "plafond global")
		for i = 1, 30 do
			M.Upsert({ sender = "Seul", id = "u" .. i, source = "TEST", kind = "TEST", state = "DETECTED",
				uiMapID = 1, x = 0, y = 0 }, 1000 + i)
		end
		local fromOne = 0
		M.ForEach(function(marker) if marker.sender == "Seul" then fromOne = fromOne + 1 end end, 1030, "test")
		H.eq(fromOne, M.MAX_TEST_PER_SENDER, "plafond par émetteur")
		M.Reset()
	end)

	---------------------------------------------------------------------------
	H.suite("Coordonnées : validation, conversions, projection")
	---------------------------------------------------------------------------

	H.test("validation des coordonnées et des cartes", function()
		H.eq(C.IsValidMapCoord(0), true)
		H.eq(C.IsValidMapCoord(1), true)
		H.eq(C.IsValidMapCoord(-0.01), false)
		H.eq(C.IsValidMapCoord(1.01), false)
		H.eq(C.IsValidMapCoord(0 / 0), false)
		H.eq(C.IsValidMapCoord("0.5"), false)
		H.eq(C.IsValidMapID(1429), true)
		H.eq(C.IsValidMapID(0), false)
		H.eq(C.IsValidMapID(1.5), false)
	end)

	H.test("décalage en mètres et application inverse", function()
		local east, north = C.OffsetYards(3470, 2315, 0.5, 0.5, 0.5 + 34.7 / 3470, 0.5 - 23.15 / 2315)
		H.near(east, 34.7, 1e-9, "est")
		H.near(north, 23.15, 1e-9, "nord")
		local x, y = C.ApplyOffset(3470, 2315, 0.5, 0.5, east, north)
		H.near(x, 0.51, 1e-12)
		H.near(y, 0.49, 1e-12)
	end)

	H.test("projection sur la minicarte, avec et sans rotation", function()
		local px, py = C.ProjectToMinimap(100, 0, 200, 70, 70, nil)
		H.near(px, 35, 1e-9)
		H.near(py, 0, 1e-9)
		-- face à l'ouest (pi/2) : un point à l'ouest apparaît en haut, un point au nord à droite
		local wx, wy = C.ProjectToMinimap(-100, 0, 200, 70, 70, math.pi / 2)
		H.near(wx, 0, 1e-9)
		H.near(wy, 35, 1e-9)
		local nx, ny = C.ProjectToMinimap(0, 100, 200, 70, 70, math.pi / 2)
		H.near(nx, 35, 1e-9)
		H.near(ny, 0, 1e-9)
	end)

	H.test("bord de la minicarte : ronde ou carrée", function()
		H.eq(C.IsInsideMinimap(60, 60, 70, 70, true, 0), false, "coin hors du cercle")
		H.eq(C.IsInsideMinimap(60, 60, 70, 70, false, 0), true, "coin dans le carré")
		H.eq(C.IsInsideMinimap(66, 0, 70, 70, true, 7), false, "marge de l'icône")
	end)

	H.test("conversion entre cartes d'un même continent, refus entre continents", function()
		C.ResetCaches()
		-- bas d'Elwynn (y=1) = haut de la Marche de l'Ouest (y=0) dans la carte simulée
		local x, y = C.TranslateToMap(1429, 0.5, 1, 1436)
		H.near(x, 0.5 * 3470 / 3500, 1e-9, "x")
		H.near(y, 0, 1e-9, "y")
		H.eq(C.TranslateToMap(1429, 0.5, 0.5, 1411), nil, "Durotar est sur un autre continent")
	end)

	H.test("dimensions de carte : repli par conversions si GetMapWorldSize est absent", function()
		C.ResetCaches()
		local api = solo.env.__api
		local original = api.C_Map.GetMapWorldSize
		api.C_Map.GetMapWorldSize = nil
		local width, height = C.GetMapSizeYards(1429)
		api.C_Map.GetMapWorldSize = original
		C.ResetCaches()
		H.near(width, 3470, 1e-6)
		H.near(height, 2315, 1e-6)
	end)

	H.test("position du joueur indisponible en instance ou si secrète", function()
		solo.inInstance = true
		local mapID, reason = C.GetPlayerMapPosition()
		solo.inInstance = false
		H.eq(mapID, nil)
		H.eq(reason, "instance")
		local api = solo.env.__api
		local original = api.C_Map.GetBestMapForUnit
		api.C_Map.GetBestMapForUnit = function() return H.SECRET end
		local secretMap, secretReason = C.GetPlayerMapPosition()
		api.C_Map.GetBestMapForUnit = original
		H.eq(secretMap, nil)
		H.eq(secretReason, "secret")
	end)

	---------------------------------------------------------------------------
	H.suite("Configuration et SavedVariables")
	---------------------------------------------------------------------------

	H.test("valeurs hors bornes ou de mauvais type corrigées", function()
		local settings = ns.Config.Sanitize({ iconSize = 100, iconAlpha = "x", liveTTL = -5,
			colors = { live = { r = 2, g = "a" } } })
		H.eq(settings.iconSize, 32)
		H.eq(settings.iconAlpha, ns.Config.DEFAULTS.iconAlpha)
		H.eq(settings.liveTTL, 10)
		H.eq(settings.colors.live.r, 1)
		H.eq(settings.colors.live.g, ns.Config.DEFAULTS.colors.live.g)
		H.eq(settings.shareEnabled, true, "défaut ajouté")
	end)

	H.test("Config.Set refuse un type incorrect et borne les nombres", function()
		H.eq(ns.Config.Set("iconSize", "grand"), false)
		H.eq(ns.Config.Set("inconnu", true), false)
		H.eq(ns.Config.Set("iconSize", 4), true)
		H.eq(ns.Config.Get("iconSize"), 8)
		ns.Config.Set("iconSize", 14)
	end)

	---------------------------------------------------------------------------
	H.suite("File d'envoi")
	---------------------------------------------------------------------------

	H.test("classement des codes de retour de SendAddonMessage", function()
		local S = ns.Sender
		H.eq(S.ClassifyResult(0), "ok")
		H.eq(S.ClassifyResult(true), "ok")
		H.eq(S.ClassifyResult(nil), "ok")
		H.eq(S.ClassifyResult(false), "refused")
		H.eq(S.ClassifyResult(3), "throttle")
		H.eq(S.ClassifyResult(8), "throttle")
		H.eq(S.ClassifyResult(11), "lockdown")
		H.eq(S.ClassifyResult(5), "nogroup")
		H.eq(S.ClassifyResult(9), "refused")
		H.eq(S.ResultName(11), "AddOnMessageLockdown")
	end)

	H.test("sans groupe : aucun canal, rien n'est mis en file", function()
		H.eq(ns.Sender.GetChannel(), nil)
		local ok, reason = ns.Sender.SendHello(false)
		H.eq(ok, false)
		H.eq(reason, "nogroup")
		H.eq(ns.Sender.GetQueueLength(), 0)
	end)


	---------------------------------------------------------------------------
	H.suite("Robustesse interne (revue de code)")
	---------------------------------------------------------------------------

	H.test("un écouteur qui se retire pendant la répartition ne fait sauter personne", function()
		local calls = {}
		ns.On("PGR_TEST_DISPATCH", "TestA", function()
			calls[#calls + 1] = "A"
			ns.Off("PGR_TEST_DISPATCH", "TestA")
		end)
		ns.On("PGR_TEST_DISPATCH", "TestB", function() calls[#calls + 1] = "B" end)
		ns.Fire("PGR_TEST_DISPATCH")
		H.eq(table.concat(calls, ","), "A,B", "premier passage")
		ns.Fire("PGR_TEST_DISPATCH")
		H.eq(table.concat(calls, ","), "A,B,B", "A retiré, B toujours appelé")
		ns.Off("PGR_TEST_DISPATCH", "TestB")
	end)

	H.test("erreurs espacées tolérées, rafale d'erreurs = module désactivé", function()
		local module = ns.NewModule("TestErreurs")
		local fail = function() error("panne") end
		ns.SafeCall("TestErreurs", fail)
		world.time = world.time + 61
		ns.SafeCall("TestErreurs", fail)
		world.time = world.time + 61
		ns.SafeCall("TestErreurs", fail)
		H.eq(module.enabled, true, "3 erreurs sur 2 minutes")
		ns.SafeCall("TestErreurs", fail)
		ns.SafeCall("TestErreurs", fail)
		H.eq(module.enabled, false, "3 erreurs en moins de 60 s")
		H.eq(ns.SafeCall("TestErreurs", function() end), false, "module désactivé : plus appelé")
	end)

	H.test("alias de fusion bornés : un flot d'identifiants au même endroit ne grossit pas la mémoire", function()
		M.Reset()
		M.Upsert(Live("A-R", "1", 0.5, 0.5), 100)
		for i = 1, 50 do
			M.Upsert(Live("B-R", "x" .. i, 0.5, 0.5), 100 + i)
		end
		H.eq(M.Count(), 1)
		local aliases = M.AliasCount()
		H.eq(aliases, 1, "un seul alias pour B vers ce marqueur")
		M.Reset()
	end)

	H.test("quota par émetteur : un joueur ne peut pas évincer les marqueurs des autres", function()
		M.Reset()
		M.Upsert(Live("A-R", "a", 0.9, 0.9), 100)
		for i = 1, M.MAX_REAL_PER_SENDER + 20 do
			M.Upsert(Live("B-R", "b" .. i, 0.002 * i, 0.1), 100 + i)
		end
		local fromB = 0
		M.ForEach(function(marker) if marker.sender == "B-R" then fromB = fromB + 1 end end, 200, "real")
		H.eq(fromB, M.MAX_REAL_PER_SENDER, "B plafonné")
		H.ok(M.Get("A-R", "a"), "marqueur de A conservé")
		M.Reset()
	end)

	H.test("échec de conversion de carte : retenté après quelques secondes, jamais d'erreur", function()
		C.ResetCaches()
		local api = solo.env.__api
		local size, toWorld = api.C_Map.GetMapWorldSize, api.C_Map.GetWorldPosFromMapPos
		api.C_Map.GetMapWorldSize = function() error("carte inconnue") end
		api.C_Map.GetWorldPosFromMapPos = function() error("carte inconnue") end
		H.eq(C.GetMapSizeYards(1429), nil, "échec sans erreur Lua")
		H.eq(C.TranslateToMap(1429, 0.5, 0.5, 1436), nil)
		api.C_Map.GetMapWorldSize, api.C_Map.GetWorldPosFromMapPos = size, toWorld
		H.eq(C.GetMapSizeYards(1429), nil, "échec encore mémorisé")
		world.time = world.time + 6
		H.near(C.GetMapSizeYards(1429), 3470, 1e-6, "nouvel essai réussi")
		H.eq(C.IsKnownMap(9999999), false, "carte inconnue du client")
		H.eq(C.IsKnownMap(1429), true)
		C.ResetCaches()
	end)

	---------------------------------------------------------------------------
	H.suite("Localisation")
	---------------------------------------------------------------------------

	local function LoadLocale(file, locale)
		local env = setmetatable({ GetLocale = function() return locale end }, { __index = _G })
		local chunk = assert(loadfile(root .. "/" .. file))
		setfenv(chunk, env)
		local fakeNs = { L = {} }
		chunk("PartyGatherRadar", fakeNs)
		return fakeNs.L
	end

	local function Specifiers(text)
		local list = {}
		for spec in text:gmatch("%%[%-%d%.]*[sdfx%%]") do
			list[#list + 1] = spec
		end
		return table.concat(list, " ")
	end

	H.test("frFR et enUS : mêmes clés, mêmes spécificateurs de format", function()
		local fr = LoadLocale("Localization/frFR.lua", "frFR")
		local en = LoadLocale("Localization/enUS.lua", "enUS")
		for key, text in pairs(fr) do
			H.ok(en[key], "clé absente en enUS : " .. key)
			H.eq(Specifiers(en[key]), Specifiers(text), "format de " .. key)
		end
		for key in pairs(en) do
			H.ok(fr[key], "clé absente en frFR : " .. key)
		end
		local skipped = LoadLocale("Localization/enUS.lua", "frFR")
		H.eq(next(skipped), nil, "enUS ignoré sur un client français")
	end)

	H.test("toutes les clés utilisées par le code existent", function()
		local fr = LoadLocale("Localization/frFR.lua", "frFR")
		local dynamic = {
			KIND_ = { "HERB", "ORE", "TEST", "OTHER" },
			STATUS_ = { "ACTIVE", "UNCERTAIN", "HISTORY", "MANUAL", "TEST" },
			CAP_ = { "SHARE", "RECEIVE", "HERB_TRACKING", "ORE_TRACKING", "MINIMAP_PROBE" },
		}
		for prefix, values in pairs(dynamic) do
			for _, value in ipairs(values) do
				H.ok(fr[prefix .. value], "clé dynamique absente : " .. prefix .. value)
			end
		end
		for _, file in ipairs(world.tocFiles) do
			local handle = assert(io.open(root .. "/" .. file, "r"))
			local source = handle:read("*a")
			handle:close()
			for key in source:gmatch("ns%.T%(%s*\"([%u_]+)\"") do
				-- les préfixes dynamiques ("KIND_" .. type) sont vérifiés plus haut
				if key:sub(-1) ~= "_" then
					H.ok(fr[key], file .. " : clé absente " .. key)
				end
			end
			for key in source:gmatch("TooltipLine%(%s*\"([%u_]+)\"") do
				H.ok(fr[key], file .. " : clé absente " .. key)
			end
			for key in source:gmatch("ns%.T%(%s*value and \"([%u_]+)\"") do
				H.ok(fr[key], file .. " : clé absente " .. key)
			end
		end
		for _, key in ipairs({ "HELP_PGR", "HELP_HELP", "HELP_STATUS", "HELP_DEBUG", "HELP_TEST", "HELP_PEERS",
			"HELP_CLEAR", "HELP_VERSION", "HELP_DIAG", "HELP_PROBE", "HELP_LOG", "HELP_TOGGLES", "DEBUG_ON", "DEBUG_OFF" }) do
			H.ok(fr[key], "clé absente " .. key)
		end
	end)
end
