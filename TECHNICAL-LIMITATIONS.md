# PartyGatherRadar — Faisabilité et limitations techniques

Document de la **phase 0** (recherche et diagnostic), mis à jour le 2026-11-09 pour la version 0.6.0.

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
> 1.2.17, qui a retiré sa fonction équivalente ; Constaté (tiers), puis **constaté en jeu** par ce projet
> le 2026-11-08, build 70862). La 0.4.0 s'y adapte seule : détection au survol, voir § 3.A.
>
> **Sans souris (0.5.0).** Lire la minicarte sans survol reste impossible. La 0.5.0 ajoute deux sources
> légitimes : la cible d'interaction douce du jeu (détection de proximité, environ 15 m) et les
> emplacements connus (herbes et filons déjà vus, gardés d'une session à l'autre). Voir § 3.A.
>
> **Restriction voulue (0.6.0).** Sur Stanzilla/WoWUIBugs#894 (2026-11-07), il a été répondu au nom de
> Blizzard : « This is intentional and an unwanted interaction. The API will be removed entirely in a
> future update », puis « Blizzard told us. Minimap is off limits. » La portée de la cible douce est
> plafonnée à environ 15 m quels que soient les réglages (mesuré par NodeRadar, `SoftTargetInteractRange`
> 60 : 15,4 à 15,6 m ; Constaté (tiers)). Déplacer la minicarte sous le curseur immobile permet encore de
> la lire (NodeRadar, 2026-11-08) : écarté, car c'est contourner une restriction que Blizzard dit voulue.
> La 0.6.0 ajoute les points d'apparition de QuestieDB. Voir § 3.A.

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
| **A. Lire le nom d'un point sous un survol** | Possible | `C_TooltipInfo.GetMinimapMouseover()` (données de l'infobulle native) ; sous le vrai curseur : **détection au survol** (0.4.0) | Confirmé (doc) ; **vérifié en jeu** par le balayage (2026-10-15) ; **survol vérifié en jeu** (2026-11-08, build 70862 : lecture et réception par le groupe) |
| **A. Sonder la minicarte sans bouger la souris** | **Bloqué depuis novembre 2026** | `Minimap:SetUsingSoftCursor(bool)` + `Minimap:UpdateMouseoverAtPoint(x, y)` : fonctions **propres à la branche Forever** | Confirmé (doc) ; **vérifié en jeu** (2026-10-15, 293 points sans erreur ; plantes partagées dans le journal du client live) ; depuis la mise à jour de novembre 2026, ne nomme plus qu'un point sous le vrai curseur (Constaté (tiers)) |
| **A. Détecter une ressource proche sans souris** | Possible, portée limitée | Cible d'interaction douce du jeu (unité `softinteract`, `PLAYER_SOFT_INTERACT_CHANGED`) : GUID « GameObject-… », `UnitName`, `UnitIsInInteractRange` ; réglages `SoftTargetInteract*` posés par l'addon (0.5.0, opt-in) | **Vérifié en jeu** (2026-11-09) : herbes lues et partagées, premières vues à environ 4 à 13 m ; limite d'environ 15 m constatée par un tiers (ForeverLootSparkles) |
| A. Endroits où une ressource peut pousser | Possible avec QuestieDB | Points d'apparition lus en jeu dans QuestieDB (`LibQuestieDB.Object.spawns`, table des zones `Support.Get("ZoneDB")`) (0.6.0) | Coordonnées comparées hors jeu aux emplacements vus en jeu ; affichage non vérifié en jeu |
| A. Emplacements déjà vus | Possible | Positions gardées dans les SavedVariables, affichées comme positions historiques (0.5.0) | Testé hors jeu ; non vérifié en jeu |
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
  - **constaté en jeu** le 2026-11-08 (build 70862, deux clients) : 5 balayages sans aucun nom, puis deux
    plantes survolées (Feuillargent, Pacifique) lues, partagées et reçues par l'autre client ; mode survol
    choisi seul et mémorisé (`blindBuild = "70862"`) ;
  - **renvoi espacé (0.4.1)** : la souris qui parcourt un point déplace la position estimée à chaque
    lecture (4 messages en 0,6 s vus en jeu). Une position affinée est renvoyée au plus toutes les 2 s, et
    la dernière part même après le survol. L'arrivée d'un membre ne lève pas cet espacement ;
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

- **Détection de proximité (0.5.0, réglage `proximityDetect`, désactivé par défaut)** :
  - la cible d'interaction douce du jeu (unité `softinteract`, celle de la touche d'interaction) désigne
    l'objet le plus proche. Un objet du monde n'est pas une unité (`UnitExists` faux) mais a un GUID
    « GameObject-… » et un nom (`UnitName`) ; `UnitIsInInteractRange` dit s'il est à portée. Constaté
    (tiers) : ForeverLootSparkles 1.3.1 et RareScanner lisent cette cible sur Forever ;
  - lecture toutes les 0,5 s et à `PLAYER_SOFT_INTERACT_CHANGED`, jamais en combat ni pendant une
    restriction d'addons. Le nom est trié comme au survol (`Detection/ResourceNames.lua`) : coffres,
    boîtes aux lettres et objets de quête ne sont jamais partagés. Un nom secret est ignoré ;
  - lecture seulement quand le réglage est actif, même si le joueur a activé la cible douce lui-même ;
  - position : celle du joueur, à ±5 m si l'objet est à portée d'interaction, sinon ±15 m. Une vue à
    portée remplace une position moins précise ; une vue lointaine ne déplace jamais une position plus
    précise. La même cible est confirmée toutes les 5 s ; le renvoi au groupe suit l'espacement habituel
    (25 s) ;
  - le GUID identifie l'objet : vu de deux côtés opposés (jusqu'à 30 m d'écart entre les deux positions du
    joueur), il reste une seule ressource ; deux objets du même nom tout proches ne sont jamais fusionnés.
    Deux joueurs qui voient le même objet produisent encore deux détections (pas de GUID dans le
    protocole) ;
  - le pistage n'est pas nécessaire : un joueur sans Découverte d'herbes partage aussi ce qu'il approche ;
  - réglages du jeu : `SoftTargetInteract` 3, `SoftTargetInteractArc` 2, `SoftTargetInteractOnlyInRange`
    0, `SoftTargetInteractRange` au moins 15 (jamais réduit). Les valeurs d'origine sont gardées dans
    `PartyGatherRadarDB.proximityCVars` ; `/pgr near off` rétablit celles que personne n'a changées
    entre-temps. En combat, l'action attend la fin du combat ;
  - **limite** : ForeverLootSparkles 1.3.1 demande 60 m et note que Forever lâche la cible au-delà
    d'environ 15 m (Constaté (tiers)). La précision annoncée (±15 m) en dépend. Pour la vérifier, le
    journal note « ciblé à environ N m » : la distance parcourue entre la première vue d'un objet et
    l'arrivée à portée d'interaction (à 5 m près). Une seule cible à la fois : celle que le jeu
    choisit, en général l'objet le plus proche. Effets visibles en jeu des réglages non vérifiés ;
  - **vérifié en jeu le 2026-11-09** (build 70862, deux clients) : GUID et nom des herbes lisibles ;
    « ciblé à environ 8 m » puis « 4 m » avant la portée d'interaction, soit environ 4 à 13 m de la
    plante ; Aedot, sans pistage, a partagé une herbe vue de près. Les réglages du jeu avaient déjà les
    valeurs voulues sur les deux clients (`proximityCVars` vide). Conséquence : la proximité ne voit que la
    plante toute proche, et ne remplace pas le survol pour les plantes lointaines de la minicarte ;
  - une herbe cueillie reste ciblée le temps de disparaître (constaté en jeu : revue 0,3 s après). Elle
    n'est pas signalée de nouveau pendant 60 s (`AutoDetect.GATHERED_IGNORE_SECONDS`) : même GUID, ou, sans
    GUID connu des deux côtés, même nom à portée de l'endroit de la cueillette. Non vérifié en jeu ;
  - aucune touche n'est liée ; l'addon ne cible, ne déplace et ne récolte rien.
- **Emplacements connus (0.5.0)** :
  - chaque herbe ou filon détecté par le joueur (balayage, survol, proximité), récolté (à ±5 m, même sans
    pistage) ou reçu du groupe (détection récente) est gardé par carte dans
    `PartyGatherRadarDB.knownSpots` : position, sorte, nom, précision, date (`time()`), nombre de vues ;
  - fusion à 15 m pour une même sorte, ou jusqu'à la somme des deux précisions (au plus 30 m) ; la position
    la plus précise est gardée ; au plus 300 par carte et 3000 en tout, les plus anciens retirés, ceux reçus
    du groupe avant ceux vus par le joueur ; données validées au chargement ;
  - une ressource récoltée par le joueur, ou retirée par un membre (`REMOVE` GATHERED), n'affiche pas son
    emplacement pendant 5 min (temps de repousse inconnu : simple délai) ; une nouvelle vue lève ce délai ;
  - affichés sur la minicarte comme des positions historiques (icône discrète, infobulle « Emplacement
    connu », « présence actuelle non confirmée »). Cachés près d'une détection récente de la même sorte
    (20 m) affichée ou faite par le joueur, pour une sorte que le personnage piste (les points natifs
    suffisent), et, s'ils viennent d'un autre joueur, quand la réception est coupée ;
  - la boucle d'affichage (10 Hz) ne tourne que s'il existe des marqueurs, ou des emplacements connus
    affichables sur la carte courante ;
- **Points d'apparition (0.6.0, réglage `showSpawns`, désactivé par défaut ; QuestieDB n'est pas lu tant
  qu'il est désactivé)** :
  - source : QuestieDB (GPL-3), s'il est installé, par son interface publique `_G.LibQuestieDB` (contrat 4) ;
    rien n'est copié dans l'addon. `## OptionalDeps: QuestieDB` le charge avant l'addon ;
  - liste fixe d'identifiants d'objets de récolte (herbes et filons, variantes de Forever comprises), établie
    le 2026-11-09 sur QuestieDB 1.0.13 : un nom seul ne suffit pas, des objets de quête portent un nom de
    ressource ;
  - zones de QuestieDB rapportées aux cartes du jeu par sa table `areaIdToUiMapId` (et ses alias) ; une
    zone absente n'est pas affichée ; la sentinelle d'instance (-1, -1) est ignorée ;
  - lecture par carte à l'arrivée, 8 objets par image, jamais en combat ; 4 cartes gardées ; un objet en
    erreur n'empêche pas les autres ; deux objets au même endroit (au centième de pourcent) font un point ;
  - affichés plus petits et plus pâles qu'un emplacement connu (infobulle « Point d'apparition possible »,
    « présence actuelle non confirmée »), cachés près d'une détection ou d'un emplacement connu de la même
    sorte (20 m, récolte récente comprise) et pour une sorte que le personnage piste ;
  - précision : comparés hors jeu le 2026-11-09 aux emplacements vus en jeu par Aedot, 0,1 à 0,3 % de carte
    (5 à 15 m) pour les relevés précis. QuestieDB décrit quatre zones redessinées entre Era et Forever
    (Mulgore, Maleterres de l'Est, Les Carmines, Hurlevent) sans convertir ses lectures : non vérifié ;
  - une ressource peut avoir été récoltée par un autre joueur ou ne pas être réapparue : un emplacement
    connu n'est jamais présenté comme une détection.

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
- PartyGatherRadar n'envoie jamais de chuchotement (WHISPER). Des addons qui chuchotent un membre du groupe
  sous la forme « Prénom-Nom » provoquent « Aucun joueur nommé '…' ne joue actuellement » : sur Forever, le
  tiret désigne un royaume. Constaté le 2026-11-09 avec ForeverGuide 1.39.5 (préfixe `FGD`, échange direct
  expérimental), identifié en jeu par un relevé des envois `WHISPER`. La 0.5.0 masque ce message quand il
  vise un membre du groupe connecté (`ChatFrameUtil.AddMessageEventFilter`, `ERR_CHAT_PLAYER_NOT_FOUND_S`) ;
  les envois de l'autre addon continuent.
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

## 4. Limitations connues de la version 0.6.0

1. Sur le client live restreint (novembre 2026), seule la **détection au survol** fonctionne : une
   ressource n'est partagée que si le joueur passe la souris dessus sur sa minicarte. Elle n'est pas
   déclarée disparue par le balayage : elle expire, sauf une herbe cueillie par le joueur. Un filon miné
   n'est pas retiré (il peut souvent être miné plusieurs fois). Aucune détection sans survol n'est
   possible sur ce client : aucune API ne donne les points de la minicarte, et la sonde ne lit plus que
   sous le vrai curseur. Sans souris, la 0.5.0 offre seulement la détection de proximité (objet le plus
   proche ; vérifiée en jeu le 2026-11-09 : plantes vues à environ 4 à 13 m), les emplacements connus
   et, avec QuestieDB, les points d'apparition (0.6.0) ; ni les uns ni les autres n'affirment la présence. Le passage automatique en mode survol est vérifié en jeu (2026-11-08) ; la
   précision sous le curseur, l'icône chez l'autre client et le retour au balayage ne le sont pas encore.
   Détection par balayage (clients non restreints) : coût en images par seconde et effet sur
   l'infobulle native non mesurés.
2. Tri par noms : une herbe absente de la liste (nom français mal orthographié, autre langue que le
   français ou l'anglais) est ignorée jusqu'à sa première récolte, qui l'apprend. Les noms ignorés sont
   dans le journal (« nom ignoré »). Deux plantes du même nom à moins d'environ 50 m (zoom minimal)
   donnent un seul marqueur. Deux herboristes qui voient la même plante peuvent produire deux
   marqueurs à plus de 5 m l'un de l'autre (fusion limitée à 5 m).
3. Mode de secours partiel : détection au survol et retrait à la cueillette (0.4.0), détection de
   proximité et emplacements connus (0.5.0). Les emplacements connus ne sont pas envoyés au groupe en
   tant que tels : chacun garde ce qu'il a vu ou reçu en direct. Pas encore de marqueurs manuels
   (phase 2/3). Comme les détections reçues, un emplacement connu peut recouvrir un point natif d'une
   autre sorte sur la minicarte d'un joueur qui piste.
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
- ForeverLootSparkles 1.3.1, `SoftTarget.lua`, et RareScanner, `Core/Service/RSEventHandler.lua`
  (installés le 2026-11-09) : lecture de la cible `softinteract` et des GUID « GameObject » sur Forever,
  limite d'environ 15 m. Lus pour le constat, **aucun code copié**.
