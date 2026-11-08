# PartyGatherRadar — Faisabilité et limitations techniques

Document de la **phase 0** (recherche et diagnostic), mis à jour le 2026-11-08 pour la version 0.4.0.

Légende des niveaux de confiance :

- **Confirmé (doc)** : présent dans la documentation d'API générée par Blizzard pour la branche Forever ou le client 12.x.
- **Confirmé (local)** : constaté sur l'installation de la bêta de ce poste (fichiers du client, addons installés).
- **Constaté (tiers)** : observé dans un addon publié qui fonctionne sur Forever, sans documentation officielle.
- **Vérifié en jeu** : constaté par ce projet dans le client réel (deux clients, 2026-10-15).
- **Non vérifié en jeu** : pas encore exécuté dans un client WoW réel par ce projet.

> Premiers tests en jeu le 2026-10-15 (deux clients, 0.1.0 puis 0.1.1) : chargement, sondes d'API,
> identité et communication de groupe vérifiés. La détection sur la minicarte et l'affichage des icônes
> ne le sont pas encore. Les tests automatisés hors jeu (Lua 5.1 + bouchons d'API) valident la logique de
> l'addon, pas le comportement du client. Voir `Tests/TestPlan.md`.
>
> **Novembre 2026 : sonde restreinte.** Une mise à jour du client WoW Forever de novembre 2026 limite
> `Minimap:UpdateMouseoverAtPoint` : la sonde ne nomme plus un point que sous le **vrai** curseur, donc le
> balayage de la minicarte ne lit plus rien, sans erreur (constat publié par NaowhForever_Professions
> 1.2.17, qui a retiré sa fonction équivalente ; Constaté (tiers), pas encore constaté par ce projet en
> jeu). La 0.4.0 s'y adapte seule : détection au survol, voir § 3.A.

## 1. Client ciblé

| Élément | Valeur | Confiance |
|---|---|---|
| Produit | `wow_classic_beta`, dossier `_classic_beta_` | Confirmé (local, `.build.info`) |
| Build | 1.60.1.70374 | Confirmé (local) |
| Interface TOC | 16001 | Confirmé (local : plus de 30 addons Forever installés l'utilisent ; wiki Patch 1.60.1) |
| Famille d'API | Mainline 12.x (« la grande majorité des API de 12.1.5 »), restrictions de Midnight et valeurs secrètes actives | Confirmé (annonce Blizzard citée par le wiki) |
| Identification | `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` (18) ; un addon installé signale que certaines builds renvoient `WOW_PROJECT_MAINLINE` | Constaté (tiers) |
| Client live | produit `wowf`, dossier `_forever_`, build 1.60.1.70862 (2026-11-08), interface 16001 inchangée | Confirmé (local, `.build.info`) ; `/pgr diag` d'Aedot sur ce build |

PartyGatherRadar identifie Forever par le numéro d'interface (16000 à 19999) et, en complément, par
`WOW_PROJECT_CAMELOT`. `/pgr version` affiche la build réellement utilisée via `GetBuildInfo()`.

## 2. Matrice de faisabilité

| Capacité | Verdict | Mécanisme retenu | Confiance |
|---|---|---|---|
| **A. Énumérer les points de pistage de la minicarte** | **Impossible** | Aucune API : les 23 fonctions `C_Minimap` n'en listent aucun ; l'événement `MINIMAP_UPDATE_TOOLTIP` n'existe pas | Confirmé (doc) |
| **A. Lire le nom d'un point sous un survol** | Possible | `C_TooltipInfo.GetMinimapMouseover()` (données de l'infobulle native) ; sous le vrai curseur : **détection au survol** (0.4.0) | Confirmé (doc) ; **vérifié en jeu** par le balayage (2026-10-15) ; survol de la 0.4.0 non vérifié en jeu |
| **A. Sonder la minicarte sans bouger la souris** | **Bloqué depuis novembre 2026** | `Minimap:SetUsingSoftCursor(bool)` + `Minimap:UpdateMouseoverAtPoint(x, y)` : fonctions **propres à la branche Forever** | Confirmé (doc) ; **vérifié en jeu** (2026-10-15, 293 points sans erreur ; plantes partagées dans le journal du client live) ; depuis la mise à jour de novembre 2026, ne nomme plus qu'un point sous le vrai curseur (Constaté (tiers)) |
| A. Position d'un point détecté | Approximative | Grille de sondage → décalage en unités de minicarte → mètres (`C_Minimap.GetViewRadius`) → coordonnées de carte | Calcul testé hors jeu ; en jeu, joueurs retrouvés à 0,3 m et 8 m (près du centre) ; échelle à distance non vérifiée |
| A. Identifiant de ressource | Indisponible | L'infobulle ne donne que des noms localisés | Confirmé (doc : données d'infobulle) |
| A. Type herbe / minerai | Indirect | Table de noms (français, anglais, sans accents), forme des noms de gisements, noms appris à la récolte (`Detection/ResourceNames.lua`) | Testé hors jeu ; « Pacifique » et « Eglantine » vus en jeu |
| A. Disparition d'une ressource | Partielle | Absence lors d'un nouveau balayage *dans le rayon* ; herbe cueillie par le joueur (`UNIT_SPELLCAST_SENT` puis `UNIT_SPELLCAST_SUCCEEDED`) retirée tout de suite ; sinon expiration | Testé hors jeu ; cible du sort potentiellement secrète |
| **B. Communication de groupe** | Possible | `C_ChatInfo.RegisterAddonMessagePrefix`, `SendAddonMessage`, `CHAT_MSG_ADDON`, canaux PARTY / RAID / INSTANCE_CHAT | Confirmé (doc + DBM, BigWigs, EkinoksXP installés l'utilisent) ; **vérifié en jeu** entre deux clients (PARTY, 0.1.1, 2026-10-15) |
| **C. Icônes personnalisées sur la minicarte** | Possible | Cadres enfants de `Minimap`, positionnés depuis `C_Map` + `C_Minimap.GetViewRadius` | Confirmé (doc, HereBeDragons et TomTom le font sur Forever) ; non vérifié en jeu |
| C. Suivi des déplacements, du zoom, des changements de carte | Possible | Rafraîchissement 10 Hz quand des marqueurs existent ; conversions officielles carte ↔ monde | Testé hors jeu |
| C. Rotation de la minicarte | Partielle | CVar `rotateMinimap` + `GetPlayerFacing()` ; icônes masquées si l'orientation est inaccessible | Blizzard a corrigé en bêta 4 un accès aux valeurs de rotation **pendant les rencontres** |
| C. Formes de minicarte non rondes | Approximée | `GetMinimapShape()` : seule la forme ronde est exacte, les autres sont traitées comme carrées | Choix de conception |
| C. Carte du monde | Non implémenté | Prévu en phase 3 | — |

**Conclusion de la phase 0** : la fonctionnalité prioritaire (« un herboriste détecte une plante, un
autre membre la voit sur sa minicarte ») est **techniquement envisageable sans contournement** grâce
aux fonctions officielles de sondage de la minicarte propres à Forever. Elle reste **expérimentale** :
ces fonctions ne sont documentées que par leur signature, aucune exécution en jeu n'a encore validé
leur comportement dans ce projet, et Blizzard peut les restreindre à tout moment pendant la bêta.
Le mode de secours (positions de récolte, marqueurs manuels) reste donc nécessaire et sera
développé en phase 2/3, clairement séparé des détections actives.

**Mise à jour du 2026-11-08** : la restriction de novembre a confirmé ce risque. Le sondage à distance ne
voit plus rien ; seule la lecture sous le vrai curseur reste possible. La 0.4.0 en fait un mode de
détection au survol, choisi automatiquement (§ 3.A).

## 3. Détails par capacité

### A. Détection locale

- **Ce qui est impossible** : lister les points de pistage. Ils sont dessinés par le moteur dans la
  minicarte et ne sont pas des cadres accessibles au Lua. Aucune lecture de mémoire ni outil externe
  n'est utilisé ou envisagé.
- **Survol manuel** (`/pgr probe minimap`) : quand le joueur survole lui-même la minicarte, l'interface
  Blizzard appelle `GameTooltip:SetMinimapMouseover()` à chaque image ; l'addon lit les mêmes données
  avec `C_TooltipInfo.GetMinimapMouseover()`. Position estimée sous le curseur.
- **Sondage programmé** (`/pgr probe scan`, phase 0 : balayage unique à la demande) :
  - `Minimap:SetUsingSoftCursor(true)`, puis `Minimap:UpdateMouseoverAtPoint(x, y)` pour chaque point de
    la grille, lecture synchrone de `C_TooltipInfo.GetMinimapMouseover()`, puis `SetUsingSoftCursor(false)`
    dans la même image ;
  - coordonnées passées en pixels écran (unités du cadre × échelle effective), d'après les commentaires
    de NodeSight : **non documenté officiellement** ;
  - jamais en combat, jamais pendant que le vrai curseur survole la minicarte (risque de perturber
    l'infobulle native), 40 points par image ;
  - les résultats de la sonde sont des marqueurs **TEST** locaux (« [Sonde] … »), jamais partagés :
    superposés aux points natifs, ils valident visuellement la chaîne de conversion.
- **Précision** : grille de 10 unités ; au zoom minimal (rayon ≈ 233 m pour 70 unités), une unité vaut
  ≈ 3,3 m, soit une incertitude de l'ordre de 10 à 30 m ; au zoom maximal ≈ 1 m par unité. Deux
  ressources très proches peuvent fusionner en un seul repère.
- **Données de l'infobulle** : une ligne peut contenir plusieurs noms séparés par des retours à la
  ligne, avec des codes de couleur (le gris signalerait une grotte) et des flèches d'altitude : non
  exploités en 0.1.1.
- **Constaté en jeu** (2026-10-15, Les Tarides, zoom 0) : l'infobulle ne contient pas que des
  ressources. Elle renvoie aussi les **zones d'objectif de quête** (titre « Les échantillons de racines »
  et ligne d'objectif « - Echantillon de racines : 0/8 », sur presque toute la minicarte), ainsi que le
  joueur et les membres du groupe (« Aekiss Desbisous », « Aedot Wnx »). Sur 131 repères : 2 plantes
  (« Pacifique », « Eglantine », noms français du client, sans accent), 124 de quête, 5 de joueurs. Une
  plante touche environ 6 points de grille : la zone de survol d'un point est large. La détection doit
  donc trier les noms (phase 2).
- **Valeurs secrètes** : la documentation ne marque pas `GetMinimapMouseover` comme secret ; chaque
  lecture est néanmoins protégée par `issecretvalue`.
- **Restriction de novembre 2026 et adaptation (0.4.0)** :
  - constat (tiers) : depuis une mise à jour du client Forever de novembre 2026, la sonde ne nomme plus un
    point que sous le vrai curseur. Le balayage ne renvoie ni erreur ni valeur secrète, seulement aucun
    nom : sans adaptation, la détection s'arrête en silence ;
  - **détection au survol** : quand le joueur passe la souris sur un point de sa minicarte, l'infobulle
    native est lue toutes les 0,2 s (sans curseur logiciel). Une herbe ou un minerai reconnu est placé
    sous le curseur, suivi et partagé comme une détection du balayage. Toujours active, même quand le
    balayage marche ;
  - **balayage aveugle** : une ressource vue au survol moins de 10 s avant le balayage suivant, absente de
    ce balayage alors qu'il n'a lu aucune ressource, est une preuve. Une preuve vaut pour une ressource
    physique (même nom à moins de 50 m : une seule preuve), compte 10 min, et toutes sont effacées dès
    qu'un balayage lit une ressource (la sonde marche : l'absence venait d'une plante cueillie par un
    autre). Après 2 preuves, le balayage est déclaré aveugle : un avertissement dans la discussion, un
    essai toutes les 30 s au lieu de 2 s, plus de capacité « sondage minicarte » annoncée au groupe
    (nouveau HELLO à chaque changement de mode). Le mode est mémorisé pour le build du client
    (`PartyGatherRadarDB.probe.blindBuild`) et réévalué à chaque nouveau build ; un essai qui relit une
    ressource sur au plus la moitié de ses points rétablit la détection automatique (une ressource lue
    partout vient d'une infobulle restée figée, pas de la sonde) ;
  - une ressource vue seulement au survol n'est jamais retirée par un balayage qui n'a lu aucune
    ressource : elle expire (récente 60 s, incertaine 240 s) ou disparaît à la cueillette ;
  - **échecs répétés** : 5 balayages d'affilée interrompus par la sonde elle-même (erreur, valeur
    secrète) affichent un avertissement unique ; des fonctions de sondage retirées du client aussi ;
  - **restrictions d'addons** (`C_RestrictedActions.IsAddOnRestrictionActive` : combat, rencontre, mode
    défi, JcJ, carte) : ni balayage ni lecture au survol pendant qu'elles sont actives.

### B. Communication

- Préfixe `PGRadar` (7 caractères ≤ 16), inscrit au chargement (inscription perdue à chaque /reload,
  refaite automatiquement).
- Messages ≤ 255 octets (le plus long message du protocole v1 fait 112 octets, vérifié par les tests).
- Limitation Blizzard documentée : 10 messages par préfixe puis 1 par seconde, valeurs modifiables par
  le serveur. PartyGatherRadar limite à 5 messages puis 0,8 par seconde et regroupe les mises à jour.
- Codes de retour gérés (`Enum.SendAddonMessageResult`, 0 à 12) : limitation (3, 8) → nouvel essai après
  2 s ; verrouillage (11, `AddOnMessageLockdown`) → pause de 10 s ou jusqu'à `ADDON_RESTRICTION_STATE_CHANGED`
  (type Chat = 5, état Inactive = 0) ; pas de groupe (5) → file vidée.
- Verrouillage de la messagerie : documenté pour les rencontres, clés mythiques, JcJ **et** les
  « cartes à communication restreinte comme les donjons et raids ». Des annonces ultérieures parlent
  d'un assouplissement. **À vérifier en jeu** : en donjon, le partage peut être indisponible.
- `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` est affiché à titre informatif seulement : un
  autre auteur signale qu'il renvoie souvent vrai à tort ; le code de retour de l'envoi fait foi.
  **Vérifié en jeu** (2026-10-15) : il renvoie `true` chez les deux clients alors que les messages PARTY
  passent dans les deux sens.
- **Comptes d'essai** : depuis la bêta 4 (build 70291), ils ne peuvent plus envoyer de messages d'addon.
- Un message « accepté » par l'API n'est **jamais** considéré comme reçu : seule une réponse (PONG,
  HELLO) prouve la réception.
- Raids : canal RAID (option, activée par défaut, expérimental) ; sans l'option, PARTY ne touche que le
  sous-groupe. Groupes de recherche : INSTANCE_CHAT, désactivé par défaut.
- `CHAT_MSG_ADDON` n'est pas marqué secret dans la documentation 12.x ; l'addon vérifie quand même
  chaque champ.
- Protections contre un membre du groupe malveillant ou défaillant : identifiant de carte vérifié par
  `C_Map.GetMapInfo` avant toute conversion ; sources HISTORY et MANUAL refusées tant que le mode de
  secours n'existe pas ; quota de 150 marqueurs par émetteur (20 en TEST) ; alias de fusion bornés ;
  au plus un PONG par pair toutes les 2 s et une réponse HELLO (diffusée) toutes les 5 s, différée
  plutôt que perdue ; messages d'un pair ayant envoyé BYE ignorés ; rejets journalisés 20 fois par
  motif au plus.
- Un module n'est désactivé qu'après 3 erreurs en moins de 60 s ; toutes les fonctions `C_Map`
  appelées avec des données reçues sont protégées.

### C. Affichage

- Les icônes sont des boutons enfants de `Minimap` : elles suivent sa taille, son échelle et sa
  visibilité, y compris avec les addons qui conservent le cadre `Minimap` (forme : `GetMinimapShape`).
- Rayon de vue : `C_Minimap.GetViewRadius()` (mètres/yards) ; table de repli publique par niveau de
  zoom si absent. `MINIMAP_UPDATE_ZOOM` ne se déclenche pas sur les boutons +/- : le rayon est relu à
  chaque rafraîchissement.
- Position du joueur : `C_Map.GetPlayerMapPosition` (nil en instance, champ de bataille, arène) →
  icônes masquées.
- Conversion entre cartes : uniquement `C_Map.GetWorldPosFromMapPos` / `GetMapPosFromWorldPos` ; un
  marqueur d'un autre continent n'est jamais affiché.
- Distance affichée dans l'infobulle uniquement quand elle provient de ces conversions officielles.
- Les icônes peuvent recouvrir des points natifs (quêtes) : taille 14 px et transparence 0,9 par défaut,
  réglables.

## 4. Limitations connues de la version 0.4.0

1. Sur le client live restreint (novembre 2026), seule la **détection au survol** fonctionne : une
   ressource n'est partagée que si le joueur passe la souris dessus sur sa minicarte. Elle n'est pas
   déclarée disparue par le balayage : elle expire, sauf une herbe cueillie par le joueur. Un filon miné
   n'est pas retiré (il peut souvent être miné plusieurs fois). Le passage automatique en mode survol,
   la position sous le curseur et le retour au balayage ne sont **pas encore vérifiés en jeu**.
   Détection par balayage (clients non restreints) : coût en images par seconde et effet sur
   l'infobulle native non mesurés.
2. Tri par noms : une herbe absente de la liste (nom français mal orthographié, autre langue que le
   français ou l'anglais) est ignorée jusqu'à sa première récolte, qui l'apprend. Les noms ignorés sont
   dans le journal (« nom ignoré »). Deux plantes du même nom à moins d'environ 50 m (zoom minimal)
   donnent un seul marqueur. Deux herboristes qui voient la même plante peuvent produire deux
   marqueurs à plus de 5 m l'un de l'autre (fusion limitée à 5 m).
3. Mode de secours partiel : détection au survol et retrait à la cueillette (0.4.0). Pas encore de
   positions de récolte partagées ni de marqueurs manuels (phase 2/3).
4. Fenêtre de réglages simple (cases à cocher) : taille, couleurs et durées seulement dans
   `PartyGatherRadarDB.settings` (phase 4). Bouton et fenêtre non encore vérifiés en jeu.
5. Pas d'affichage sur la carte du monde : phase 3.
6. Formes de minicarte non rondes approximées comme carrées.
7. Rotation de minicarte : non vérifiée en jeu ; icônes masquées si l'orientation est inaccessible.
8. Identité des émetteurs vérifiée par comparaison avec les membres du groupe. Sur Forever (noms
   régionaux, `RegionalUniqueNamesEnabled()`), l'identité est « Prénom Nom ». **Vérifié en jeu**
   (2026-10-15) : `UnitNameUnmodified` **et** `UnitFullName` renvoient (prénom, nom de famille), jamais le
   royaume ; l'émetteur reçu a la forme « Prénom Nom-Royaume » ; avec 0.1.1, découverte mutuelle sans
   aucun rejet. Non vérifié : un nom de famille contenant un tiret (le royaume est retiré au dernier
   tiret). Royaumes classiques : « Nom-Royaume » via `UnitFullName`.
9. Aucune garantie de réception des messages (limitation inhérente à la messagerie d'addon).

## 5. Sources

- Documentation d'API générée par Blizzard, branche Forever : `MinimapFrameAPIDocumentation.lua`,
  `TooltipInfoDocumentation.lua`, `MinimapDocumentation.lua`, `Blizzard_Minimap/Mainline/Minimap.lua`,
  `UnitDocumentation.lua`, `Blizzard_FrameXMLUtil/Camelot/NameUtil.lua` (noms régionaux)
  — https://github.com/Gethe/wow-ui-source/tree/forever
- Constantes de messagerie et restrictions 12.x (`ChatInfoDocumentation`, `ChatConstants`,
  `RestrictedActionsDocumentation`) — https://github.com/Gethe/wow-ui-source/tree/live
- https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes
- https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage
- https://warcraft.wiki.gg/wiki/API_C_Minimap.GetViewRadius
- https://news.blizzard.com/en-us/article/24304160/the-world-of-warcraft-forever-beta-now-live
- NodeSight (référence fonctionnelle, licence « All Rights Reserved », **aucun code ni ressource copiés**) —
  https://www.curseforge.com/wow/addons/node-sight
- GatherMate2 (détection à la récolte, protections contre les valeurs secrètes) —
  https://github.com/Nevcairiel/GatherMate2
- NaowhForever_Professions 1.2.17, `README.md` (installé le 2026-11-08) : « A Forever update in November
  2026 stopped that: the probe now names a node only under the real cursor (#918) ». Lu pour le constat,
  **aucun code copié**.
