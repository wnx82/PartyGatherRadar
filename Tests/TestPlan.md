# Plan de tests — PartyGatherRadar 0.5.0

Deux niveaux de tests :

1. **Tests automatisés hors jeu** : Lua 5.1 + bouchons de l'API WoW + simulation de plusieurs clients
   reliés par un faux réseau. Ils valident la logique de l'addon contre le comportement *documenté*.
2. **Tests en jeu** : seuls capables de valider le comportement réel du client Forever.
   Statut « Non exécuté » tant qu'un rapport n'a pas été fourni. Essais du 2026-10-15 : 0.1.0 en échec,
   puis 0.1.1 validée pour la découverte mutuelle (voir le scénario 1). Sources : `diagnostics.lastReport`
   et `diagnostics.log` d'Aedot (PC MSI) et d'Aekiss (PC ASUS).

## 1. Tests automatisés

### Exécution

```powershell
powershell -ExecutionPolicy Bypass -File Tools\run-tests.ps1
```

- Utilise `lua5.1` / `luajit` s'ils sont dans le PATH ;
- sinon crée `Tools\.venv` et installe le paquet PyPI `lupa` (Lua 5.1 embarqué) au premier lancement ;
- code de sortie 0 si tout réussit, 1 sinon. La génération Visual Studio lance aussi ces tests.

### Couverture (exigences du cahier des charges)

| Exigence | Tests |
|---|---|
| Analyse des messages réseau | Protocole : aller-retour HELLO, NODE, BYE, PING, PONG, REMOVE ; découpage ; taille ≤ 255 octets |
| Validation des coordonnées | Coordonnées hors bornes, NaN, notations `0x10`, `1.5`, `-1` ; cartes invalides ; conversions entre cartes et continents |
| Déduplication | Fusion < 5 m entre émetteurs, pas de fusion entre types/sources/au-delà de 5 m, alias des mises à jour |
| Gestion des versions | Version future illisible signalée, HELLO futur toujours lisible, compatibilité min/max |
| Expiration des marqueurs | Récente → incertaine (60 s) → supprimée (300 s), âge transmis, TEST (120 s), historique sans expiration |
| Messages invalides | Types, tailles, champs, énumérations, noms avec `|`, incohérences TEST, émetteur hors groupe, canaux interdits, valeurs secrètes |
| Identité des joueurs | Noms régionaux de Forever (« Prénom Nom-Royaume ») : découverte, écho, PING/PONG, homonymes de prénom, départ, normalisation ; mode classique « Nom-Royaume » |
| Détection automatique | Tri des noms (herbes, minerais ; quêtes et joueurs ignorés), herbe partagée au bon endroit (≤ 15 m), sans doublon chez le détecteur, deux plantes de même nom séparées, disparition (REMOVE) seulement dans la zone fiable, déplacement (≤ 12 m), rafraîchissement sans flot, réception réactivée, nouveau membre, partage désactivé, noms appris à la récolte, conditions d'arrêt (pistage, combat, souris, option), cohabitation avec la sonde manuelle, statut et diagnostic |
| Sans souris (0.5.0) | Proximité : herbe de la cible douce partagée (±15 m, puis ±5 m à portée, position remplacée), rafraîchie, sans doublon ; même objet vu de deux côtés : une ressource ; autre objet du même nom : une autre ; herbe cueillie encore ciblée ignorée 60 s (même GUID, ou même nom à portée sans GUID), autre nom signalé ; position précise jamais dégradée ; minerai sans pistage ; cible douce inactive ou réglage coupé : rien lu ; réglages du jeu gardés, rétablis sauf ceux changés par le joueur, différés en combat (aussi après un `/reload` en combat), portée jamais réduite ; PNJ, coffres, noms secrets et combat refusés. Emplacements connus : reçus, gardés après expiration et `/reload`, infobulle, masqués pour une sorte pistée, près d'une détection affichée et 5 min après une récolte, affichés quand les détections sont masquées, remplacés par une détection, emplacement de récolte, réception coupée, fusion jusqu'à 30 m, précision, bornes et ordre de retrait, boucle d'affichage arrêtée, `/pgr spots`, SavedVariables modifiées à la main |
| Discussion | « Aucun joueur nommé » masqué pour un membre connecté (« Prénom-Nom », prénom seul, casse), affiché hors du groupe, pour un membre déconnecté, réglage ou addon coupé ; un seul filtre après `/reload` ; client anglais ; motif du message (caractères spéciaux, `%1$s`, format absent ou secret) |
| Interface | Bouton de minicarte (création, position ronde/carrée, déplacement, masquage conservé), fenêtre de réglages (version, membres avec et sans l'addon, mise à jour au départ du groupe, chaque case modifie son réglage, infos des autres masquées puis réaffichées), anglais |
| Changements de groupe | Départ d'un membre, dissolution du groupe, BYE, /reload, membre sans addon, raid |
| Séparation simulé / réel | Magasins séparés, mélanges refusés, pas de fusion TEST/réel, sonde de calibration en TEST uniquement |
| Robustesse | Module en erreur désactivé seul (rafale de 3 erreurs en 60 s), événement inconnu refusé sans erreur, écouteur retiré pendant la répartition, échec de conversion de carte retenté, toutes les commandes `/pgr`, client anglais |
| Messages hostiles | Carte inconnue, sources non prises en charge, flots de PING et de HELLO, NODE après BYE, quota par émetteur, alias bornés, journal non inondé |
| Projet | TOC (interface, version, fichiers), compilation Lua 5.1, aucun fichier hors TOC, aucune variable globale inattendue |

### Dernier résultat

| Date | Interpréteur | Résultat |
|---|---|---|
| 2026-10-14 | Lua 5.1 embarqué (lupa) | 89 réussis, 0 échec (0.1.0) |
| 2026-10-15 | Lua 5.1 embarqué (lupa) | 97 réussis, 0 échec (0.1.1) |
| 2026-10-15 | Lua 5.1 embarqué (lupa) | 106 réussis, 0 échec (0.2.0) |
| 2026-10-15 | Lua 5.1 embarqué (lupa) | 122 réussis, 0 échec (0.3.0) |
| 2026-10-15 | Lua 5.1 embarqué (lupa) | 123 réussis, 0 échec (0.3.1) |
| 2026-11-04 | Lua 5.1 embarqué (lupa) | 124 réussis, 0 échec (0.3.2) |
| 2026-11-08 | Lua 5.1 embarqué (lupa) | 139 réussis, 0 échec (0.4.0) |
| 2026-11-08 | Lua 5.1 embarqué (lupa) | 142 réussis, 0 échec (0.4.1) |
| 2026-11-09 | Lua 5.1 embarqué (lupa) | 165 réussis, 0 échec (0.5.0) |

## 2. Tests en jeu

### Préparation commune

- Deux comptes ou deux postes, personnages **Aekiss** (prêtre, Herboristerie, Découverte d'herbes) et
  **Aedot** (démoniste, sans Herboristerie), même royaume, même faction. Comptes **non** d'essai (les
  comptes d'essai ne peuvent plus envoyer de messages d'addon depuis la bêta 4).
- Addon installé chez les deux (voir README), `/pgr debug` activé chez les deux.
- Zone extérieure riche en plantes (ex. Forêt d'Elwynn, Marche de l'Ouest, Durotar).
- Après chaque scénario : `/reload` puis récupérer `WTF\Account\<compte>\SavedVariables\PartyGatherRadar.lua`.

### Scénario 0 — Sondes (phase 0)

| Étape | Résultat attendu | Statut |
|---|---|---|
| `/pgr version` | 1.60.1, build ≥ 70374, interface 16001, WoW Forever : oui | **OK** (2026-10-15, les deux) : 1.60.1 (70374), interface 16001, `WOW_PROJECT_ID` = `WOW_PROJECT_CAMELOT` = 18 |
| `/pgr diag` | Aucune `ERREUR` ; `detection.minimapProbeApi` = ATTENTION (disponible) ; localisation fiable = OUI en extérieur | **OK** (2026-10-15, les deux) ; `GetMinimapShape` ABSENT (normal sans addon de minicarte), `comm.realmRestricted` = true alors que les messages passent |
| `/pgr diag` : ligne `identity.player` | Identité « Prénom Nom » (ex. « Aedot Wnx »), noms régionaux : true ; rapport copié dans `diagnostics.lastReport` après `/reload` | **OK** (2026-10-15) : « Aedot Wnx », « Aekiss Desbisous » ; `UnitFullName` et `UnitNameUnmodified` renvoient tous deux (prénom, nom de famille) |
| Aekiss : `/pgr probe tracking` | Découverte d'herbes listée (active ou non) | **OK** (2026-10-15, via `tracking.types` de `/pgr diag`) : 24 types, herbes actif |
| Aekiss, pistage herbes actif, `/pgr probe minimap` puis survol d'un point | Nom de la plante affiché, position plausible | Non rapporté |
| Aekiss : `/pgr probe scan` hors combat, souris hors de la minicarte | Marqueurs « [Sonde] … » **superposés** aux points natifs (capture d'écran), aucun clignotement d'infobulle | **Partiel** (2026-10-15, Les Tarides, zoom 0) : 293 points, 131 repères, aucune erreur ; herbes lues (« Pacifique », « Eglantine ») ; Aekiss retrouvée à 0,3 m et Aedot à 8 m de leur position réelle ; bruit : 124 repères de zone de quête, 5 de joueurs ; superposition et clignotement non rapportés (pas de capture) |
| Idem, minicarte zoomée au maximum puis au minimum | Superposition conservée ; précision meilleure au zoom maximal | Non exécuté (second balayage identique au premier : même zoom) |
| Idem avec `/console rotateMinimap 1` | Superposition conservée, ou marqueurs masqués si l'orientation est inaccessible | Non exécuté |
| Idem en combat | « balayage impossible : en combat » | Non exécuté |
| Aedot : `/pgr probe tracking`, `/pgr probe scan` | Pas de pistage d'herbes ; aucune plante trouvée (seuls PNJ/joueurs éventuels) | Partiel (2026-10-15) : herbes non (OK) ; balayage non exécuté |

### Scénario 1 — HELLO et découverte mutuelle

| Étape | Résultat attendu | Statut |
|---|---|---|
| Aekiss invite Aedot | Chez chacun : « <autre> utilise PartyGatherRadar 0.1.1 (protocole 1) » en quelques secondes | **OK en 0.1.1** (2026-10-15) : message valide reçu des deux côtés, 0 rejet ; échec en 0.1.0 |
| `/pgr peers` chez les deux | L'autre listé, compatible, capacités cohérentes | Non rapporté (sortie dans la discussion seulement) |
| `/pgr status` | B. synchronisation = OUI (message valide reçu) | **OK** (2026-10-15) : OUI chez les deux, via `/pgr diag` |
| `/pgr test` chez Aekiss | Marqueur TEST local à ~21 m au nord-est ; « PONG reçu de Aedot en N ms » ; marqueur TEST chez Aedot | Partiel (2026-10-15) : dans les deux sens (Aekiss puis Aedot), PING et NODE TEST envoyés, NODE TEST reçu et PONG renvoyé par l'autre ; réception du PONG non journalisée |

Essai du 2026-10-15 (0.1.0, journal d'Aedot) : HELLO envoyé, messages d'Aekiss bien reçus, mais rejetés
(`not_in_group`) ; propre écho non reconnu. Cause : sur Forever, l'émetteur a la forme `Prénom Nom-Royaume`
(`Aedot Wnx-ClassicBetaPvE2`) alors que l'identité venait de `UnitFullName`. Corrigé en 0.1.1 (identité
« Prénom Nom »).

Essai du 2026-10-15 (0.1.1, les deux journaux) : découverte mutuelle réussie, aucun rejet, échos
reconnus (3 chez Aedot, 4 chez Aekiss), aucune erreur Lua.

### Scénario 2 — Détections accessibles à chacun

| Étape | Résultat attendu | Statut |
|---|---|---|
| Aekiss pistage herbes actif, Aedot sans pistage, `/pgr peers` | Aekiss annonce « herbes », Aedot non | Partiel (2026-10-15) : pistage confirmé par `/pgr diag` ; annonce via `/pgr peers` non rapportée |
| `/pgr probe scan` chez les deux au même endroit | Plantes trouvées seulement chez Aekiss | Partiel (2026-10-15) : plantes trouvées chez Aekiss ; balayage non lancé chez Aedot |

### Scénario 3 — Transmission d'une plante (phase 3)

Depuis 0.3.0, les plantes détectées sont partagées automatiquement (scénario 10). Les étapes ci-dessous
vérifient l'alignement avec le marqueur TEST de `/pgr test`.

| Étape | Résultat attendu | Statut |
|---|---|---|
| Les deux personnages côte à côte, `/pgr test` chez Aekiss | Le marqueur TEST apparaît au même endroit sur les deux minicartes | Partiel (2026-10-15) : côte à côte (4 m), test lancé par Aedot, marqueur reçu par Aekiss ; position à l'écran non rapportée (pas de capture) |
| Aedot à 50 m d'Aekiss | Le marqueur reste au même endroit du terrain (décalé sur la minicarte d'Aedot) | Non exécuté |
| Survol du marqueur chez Aedot | Infobulle : titre « Marqueur TEST », Type Test, Détecté par Aekiss, État TEST, Dernière détection, Distance | Non exécuté |

### Scénario 4 — Déplacements et incertitude

| Étape | Résultat attendu | Statut |
|---|---|---|
| Après `/pgr test`, Aekiss s'éloigne puis revient | Le marqueur disparaît hors du rayon puis réapparaît au même endroit | Non exécuté |
| Zoom +/- de la minicarte chez Aedot | Position recalculée à chaque niveau | Non exécuté |
| Attendre 120 s | Marqueur TEST supprimé | Non exécuté |

### Scénario 5 — Plante récoltée

| Étape | Résultat attendu | Statut |
|---|---|---|
| `/pgr probe minimap` actif, Aekiss récolte une plante | Journal : `UNIT_SPELLCAST_SENT` avec le nom de la plante, ou « cible secrète » | Non exécuté |
| `/pgr probe scan` après récolte | La plante n'est plus trouvée | Non exécuté |

### Scénario 6 — Départ du groupe

| Étape | Résultat attendu | Statut |
|---|---|---|
| Après `/pgr test`, Aedot quitte le groupe | Chez Aedot : marqueur d'Aekiss retiré, `/pgr peers` « pas en groupe » ; chez Aekiss : Aedot retiré | Non exécuté |
| `/pgr test` chez Aekiss seul | « pas de groupe, test de communication ignoré », aucun envoi | Non exécuté |

### Scénario 7 — /reload

| Étape | Résultat attendu | Statut |
|---|---|---|
| `/pgr minimap off`, `/reload` | Réglage conservé, aucune erreur Lua (`/console scriptErrors 1`) | Non exécuté |
| En groupe, `/reload` chez Aedot | Redécouverte mutuelle en quelques secondes | Non exécuté |

### Scénario 8 — Membre sans l'addon

| Étape | Résultat attendu | Statut |
|---|---|---|
| Aedot désactive l'addon, `/reload`, groupe avec Aekiss | Chez Aekiss : aucun pair, `/pgr peers` liste Aedot « sans addon détecté » | Non exécuté |
| `/pgr test` chez Aekiss | « aucun PONG reçu en 5 s », aucune erreur | Non exécuté |

### Scénario 9 — Bouton de minicarte et fenêtre de réglages (0.2.0 et suivantes)

| Étape | Résultat attendu | Statut |
|---|---|---|
| Connexion | Bouton (icône de fleur) sur le bord de la minicarte, en bas à gauche | Non exécuté |
| Survol du bouton | Infobulle : « PartyGatherRadar 0.5.0 », membres du groupe et nombre avec l'addon | Non exécuté |
| Glisser le bouton, `/reload` | Le bouton suit le bord de la minicarte et garde sa place après `/reload` | Non exécuté |
| Clic sur le bouton (ou `/pgr`) | Fenêtre : version, liste des membres (« PartyGatherRadar 0.5.0 » en vert, « sans addon détecté » en gris), cases à cocher ; Échap la ferme | Non exécuté |
| Aedot `/pgr test`, Aekiss décoche « Afficher les infos des autres joueurs » | Le marqueur TEST d'Aedot disparaît de la minicarte d'Aekiss, puis revient quand la case est recochée | Non exécuté |
| Décocher « Bouton autour de la minicarte » | Bouton masqué ; `/pgr` rouvre la fenêtre ; `/pgr button on` le réaffiche | Non exécuté |

### Scénario 10 — Détection automatique et partage (0.3.0)

| Étape | Résultat attendu | Statut |
|---|---|---|
| Aekiss, Découverte d'herbes active, côte à côte avec Aedot près de plantes | En quelques secondes, chez Aedot : une icône verte par plante, au même endroit que le point natif chez Aekiss (captures des deux minicartes) | Non exécuté |
| Survol d'une icône chez Aedot | Titre : le nom de la plante (plus « PartyGatherRadar »), « Détecté par : Aekiss », état « Détection récente » | Non exécuté |
| Zone de quête active sur la minicarte | Aucune icône pour la quête ni pour les joueurs ; journal d'Aekiss : « nom ignoré » une fois par nom | Non exécuté |
| Aekiss récolte une plante | L'icône disparaît chez Aedot en ~4 s | Non exécuté |
| Aekiss court (monture) dans une zone riche en plantes | Icônes chez Aedot sans doublons, images par seconde d'Aekiss normales, infobulle native sans clignotement | Non exécuté |
| Aekiss coupe le pistage, ou entre en combat | Plus aucun sondage (`/pgr status` : nombre de balayages figé) | Non exécuté |
| Case « Afficher aussi mes propres détections » chez Aekiss | Icônes superposées aux points natifs (capture, zoom minimal et maximal) | Non exécuté |
| Aedot décoche « Afficher les infos des autres joueurs » | Icônes masquées, puis revenues au plus tard 25 s après la nouvelle coche | Non exécuté |
| Après l'essai : `/pgr diag` puis `/reload` chez les deux | `lastReport` : ligne `detection.auto` (balayages, ressources, noms ignorés) | Non exécuté |

### Scénario 11 — Client live restreint : détection au survol (0.4.0)

Contexte : depuis une mise à jour de WoW Forever de novembre 2026, la sonde ne nomme plus un point de la
minicarte que sous le vrai curseur (constat tiers). Le journal sauvegardé d'Aedot sur le client live
montre des plantes détectées par Aekiss et reçues avant cette restriction. Premier essai de la 0.4.0 le
2026-11-08 (build 70862) : journaux sauvegardés d'Aekiss (journal actif) et d'Aedot.

| Étape | Résultat attendu | Statut |
|---|---|---|
| Aekiss, Découverte d'herbes active, près de plantes, souris hors de la minicarte | Rien n'est partagé (balayage aveugle) ; `/pgr status` : balayages comptés, 0 trouvée | Réussi (2026-11-08) : `/pgr diag`, 5 balayages, 0 trouvée |
| Aekiss passe la souris sur une plante de sa minicarte | Chez Aedot : icône verte au même endroit, titre = nom de la plante ; journal d'Aekiss : « herbe : … (survol) » | Partiel (2026-11-08) : « herbe : Feuillargent, carte 1426 … (survol) », envoi accepté, reçu par Aedot (`RECV: NODE LIVE`) ; icône non confirmée |
| Aekiss bouge la souris sur une plante pendant 5 s (0.4.1) | Journal d'Aekiss : au plus un `SEND: NODE LIVE` toutes les 2 s pour cette plante | Non exécuté (0.4.0 : 4 messages en 0,6 s) |
| Aekiss survole une 2ᵉ plante, puis retire la souris quelques secondes | Message unique « Détection au survol activée » ; `/pgr status` : « mode survol (balayage aveugle) » | Partiel (2026-11-08) : passage journalisé (« balayage aveugle (2 ressource(s) … ») et nouveau HELLO ; message non confirmé |
| Attendre 1 min sans survol | Les icônes restent chez Aedot (récentes, puis incertaines) ; aucune disparition à tort | Non exécuté |
| Aekiss cueille une plante survolée | L'icône disparaît chez Aedot tout de suite ; journal : « récoltée : … » | Non exécuté |
| `/reload` chez Aekiss | Rappel unique « ce client bloque le balayage » ; mode survol conservé | Non exécuté |
| Position : capture des deux minicartes, plante survolée chez Aekiss | Icône d'Aedot à moins de ~15 m du point natif | Non exécuté |
| Après l'essai : `/pgr diag` puis `/reload` chez les deux | `lastReport` : `detection.minimapProbeApi` « restreinte par le client », `detection.auto` (mode, trouvées dont au survol) ; `PartyGatherRadarDB.probe.blindBuild` = build du client | Partiel (2026-11-08) : `blindBuild = "70862"` ; `/pgr diag` lancé avant le survol seulement |

### Scénario 12 — Sans souris : proximité et emplacements connus (0.5.0)

Contexte : sur le client live (build 70862), lire la minicarte sans survol est impossible. La 0.5.0 lit
la cible d'interaction douce du jeu (constat tiers : ForeverLootSparkles, RareScanner) et garde les
emplacements déjà vus. Les deux joueurs installent la 0.5.0 et activent `/pgr debug`.

| Étape | Résultat attendu | Statut |
|---|---|---|
| Aekiss : `/pgr near on` hors combat | « détection de proximité activée … » ; `/pgr status` : « ciblage doux du jeu oui » ; `PartyGatherRadarDB.proximityCVars` contient les valeurs d'origine | Partiel (2026-11-09) : réglage actif sur les deux clients ; `proximityCVars` vide, les réglages du jeu avaient déjà les valeurs voulues |
| Aekiss s'approche d'une plante à moins de 15 m, sans souris sur la minicarte | Journal d'Aekiss : « herbe : … (proximité) » ; chez Aedot : icône verte dans les 15 m de la plante | Partiel (2026-11-09) : Doulourante et Aciérite sauvage partagées à ±5 m (emplacement reçu chez Aedot) ; ces plantes avaient d'abord été survolées, l'icône d'Aedot due à la seule proximité n'est pas confirmée |
| Aekiss va jusqu'à la plante (portée d'interaction) | Position d'Aedot affinée (infobulle : précision ±5 m) ; journal d'Aekiss : « ciblé à environ N m » (N ≤ 15 attendu, à rapporter) | Réussi (2026-11-09) : « ciblé à environ 8 m » et « 4 m » ; emplacement reçu chez Aedot à ±5 m |
| Aekiss sans Découverte d'herbes, même essai | Plante partagée quand même | Réussi (2026-11-09) avec Aedot, sans pistage : Aciérite sauvage vue de près, reçue par Aekiss |
| Aekiss cueille une plante ciblée de près | Pas de nouvelle annonce juste après ; journal : « proximité : … ignorée, cueillie à l'instant » ; chez Aedot, l'emplacement reste masqué 5 min | Non exécuté (le 2026-11-09, avant correctif : plante revue 0,3 s après la cueillette et renvoyée) |
| Aekiss près d'un coffre ou d'une boîte aux lettres | Rien n'est partagé | Non exécuté |
| Si rien n'est partagé : journal d'Aekiss | Ligne « proximité : objet ciblé sans nom lisible (…) » ou aucune ligne (à rapporter avec `/pgr diag` : sondes `UnitGUID`, `UnitIsInInteractRange`, `C_CVar.SetCVar`) | Non exécuté |
| Aekiss entre en combat puis tape `/pgr near off` | « en combat : … à la fin du combat » ; après le combat, réglages d'origine rétablis | Non exécuté |
| Aedot, 5 min après une détection, au même endroit | Icône discrète ; infobulle « Emplacement connu », dernière vue, « présence actuelle non confirmée » | Non exécuté |
| Aedot : `/reload`, puis `/pgr spots` | Icône toujours là ; nombre d'emplacements sur cette carte et en tout | Non exécuté |
| Aekiss (pistage des herbes actif) au même endroit | Pas d'icône d'emplacement connu pour les herbes (points natifs) | Non exécuté |
| Aedot groupé avec un joueur qui utilise ForeverGuide | Plus de « Aucun joueur nommé '<membre>' » dans la discussion ; `/pgr quiet off` les fait revenir ; `/pgr diag` : compteur `hiddenNotFound` | Non exécuté |
| Un joueur sans pistage actif cueille ou mine, puis `/pgr spots` | Un emplacement de plus ; journal : « emplacement de récolte : … » ; pas d'icône à cet endroit pendant 5 min | Non exécuté |

### Scénarios complémentaires

| Étape | Résultat attendu | Statut |
|---|---|---|
| Donjon : `/pgr status`, `/pgr test` | Position indisponible (instance) ; éventuel verrouillage de messagerie compté (« verrouillés ») | Non exécuté |
| Raid de 3+ joueurs | Canal RAID, découverte de tous | Non exécuté |
| Addon de minicarte (SexyMap, Leatrix Plus minicarte carrée) | Marqueurs dans la zone visible, forme carrée respectée | Non exécuté |
