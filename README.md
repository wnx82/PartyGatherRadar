# PartyGatherRadar

Addon pour **World of Warcraft: Forever** (1.60.1, interface 16001) : partager en temps réel,
entre membres d'un groupe, les ressources de récolte (herbes, minerais) détectées sur la minicarte.

> **État : prototype 0.5.0.** Détection des herbes et minerais de la minicarte et partage au groupe
> (phases 2 et 3, expérimental), bouton de minicarte et fenêtre de réglages. Le tout est testé hors jeu
> (simulation de plusieurs clients). **Vérifié en jeu** (2026-10-15, deux clients) : chargement, sondes
> d'API, identité, communication de groupe, lecture des plantes par le balayage ; le journal du client
> live montre ensuite des plantes détectées par Aekiss et reçues par Aedot.
>
> **Novembre 2026** : une mise à jour de WoW Forever empêche désormais les addons de lire la minicarte à
> distance (la sonde ne nomme plus un point que sous le vrai curseur). La 0.4.0 s'adapte seule : elle
> repère le balayage aveugle, prévient une fois dans la discussion et passe en **détection au survol** :
> passer la souris sur une plante de sa minicarte la partage au groupe. Si Blizzard rouvre la sonde, la
> détection automatique revient seule. **Vérifié en jeu** (2026-11-08, build 70862, deux clients) :
> balayage aveugle repéré, passage automatique en mode survol, plante survolée lue, partagée et reçue.
> **Pas encore vérifié en jeu** : icône affichée chez l'autre client, retour au balayage, bouton et
> fenêtre de réglages. Voir [Tests/TestPlan.md](Tests/TestPlan.md).
>
> **Sans souris (0.5.0)** : lire la minicarte sans survol reste impossible sur ce client. Deux sources
> légitimes s'ajoutent : la **détection de proximité** (`/pgr near on`, désactivée par défaut), qui lit la
> cible d'interaction douce du jeu et partage l'herbe ou le filon le plus proche (environ 15 m), même sans
> pistage ; et les **emplacements connus**, les herbes et filons déjà vus, gardés d'une session à
> l'autre et affichés en icônes discrètes (présence non confirmée). **Pas encore vérifié en jeu.**

## Objectif

Aekiss (prêtre herboriste) active Découverte d'herbes ; une plante apparaît sur sa minicarte ;
Aedot (démoniste, sans Herboristerie), dans le même groupe, voit un marqueur au même endroit sur sa
propre minicarte. Le partage fonctionne dans les deux sens et prévoit les minerais.

## Faisabilité (phase 0)

| Capacité | Verdict |
|---|---|
| Lister les points de pistage de la minicarte | **Impossible** : aucune API |
| Lire le nom d'un point sous le vrai curseur (survol) | **Vérifié en jeu** (détection au survol, 2026-11-08) ; les noms lus doivent être triés (quêtes, joueurs) |
| Sonder la minicarte à distance (sondage officiel propre à Forever) | **Vérifié en jeu** (balayage, 2026-10-15) ; **bloqué** depuis une mise à jour de novembre 2026 |
| Communiquer entre membres du groupe (messages d'addon) | **Vérifié en jeu** entre deux clients (0.1.1) |
| Lire l'objet le plus proche (cible d'interaction douce du jeu) | Vérifié en jeu (2026-11-09) : plantes vues à environ 4 à 13 m, limite d'environ 15 m |
| Afficher des icônes personnalisées sur la minicarte | Possible, non vérifié en jeu |

Détails, niveaux de confiance et sources : [TECHNICAL-LIMITATIONS.md](TECHNICAL-LIMITATIONS.md).

Principes : uniquement des API publiques du client, aucune lecture de mémoire, aucun programme
externe, aucune automatisation de déplacement, d'interaction ou de récolte, aucun pistage activé
artificiellement chez un joueur qui ne le possède pas. Aucune position n'est inventée : sans donnée
fiable, rien n'est affiché.

## Fonctionnalités de la version 0.5.0

Réellement implémenté :

- chargement sur Forever (TOC 16001), vérification de la build avec `GetBuildInfo()` ;
- SavedVariables `PartyGatherRadarDB` validées (bornes, types, schéma) ;
- protocole réseau versionné (préfixe `PGRadar`) : HELLO, BYE, PING/PONG, NODE, REMOVE ;
  validation stricte, messages ≤ 255 octets, aucun canal public ;
- découverte des autres clients, compatibilité de protocole, nettoyage au départ d'un membre ;
  identité « Prénom Nom » avec les noms régionaux de Forever, « Nom-Royaume » ailleurs ;
- file d'envoi avec limitation de fréquence, regroupement, gestion des refus (limitation,
  verrouillage de la messagerie) ;
- marqueurs avec statuts **détection récente** (vert), **incertaine** (gris), **position historique**
  (discret), **TEST** (bleu, fictif) ; déduplication à 5 m ; expiration configurable ;
- couche d'icônes sur la minicarte : déplacements, zoom, changements de carte, rotation si
  l'orientation est accessible, infobulle détaillée avec le nom de la ressource en titre ;
- diagnostics : sondes d'API, matrice de capacités, compteurs, journal sauvegardable ; rapport de
  `/pgr diag` sauvegardé dans `diagnostics.lastReport` ;
- **détection automatique** (pistage des herbes ou des minerais actif) : la minicarte est sondée toutes
  les 2 s ; seuls les noms d'herbes et de minerais connus sont gardés (les zones de quête et les joueurs
  sont ignorés) ; une plante découverte est envoyée au groupe, rafraîchie toutes les 25 s tant qu'elle
  reste visible, puis retirée chez tous quand elle disparaît (récoltée) ; noms appris à la récolte ;
- **détection au survol** : une plante ou un filon survolé à la souris sur sa minicarte est partagé,
  même quand le client bloque le balayage ; une herbe cueillie est retirée chez tous tout de suite ;
- **détection de proximité** (0.5.0, `/pgr near on`, désactivée par défaut) : l'herbe ou le filon que le
  jeu choisit comme cible d'interaction douce (le plus proche, environ 15 m) est partagé à la position du
  joueur (±5 m à portée d'interaction, sinon ±15 m), sans souris ni pistage. L'addon règle le ciblage doux
  du jeu et rétablit les valeurs d'origine avec `/pgr near off` ; rien n'est changé en combat ;
- **emplacements connus** (0.5.0) : herbes et filons vus, récoltés ou reçus du groupe, gardés par carte
  (fusion à 15 m, 3000 au plus), affichés en icônes discrètes avec l'avertissement « présence actuelle
  non confirmée » ; cachés près d'une détection récente, 5 min après une récolte et pour une sorte que le
  personnage piste ;
- **adaptation au client** : balayage aveugle repéré seul (avertissement unique, mode survol, essai toutes
  les 30 s, retour automatique), mémorisé par build du client ; échecs répétés de la sonde signalés ;
  aucun sondage pendant les restrictions d'addons (rencontre, mode défi, JcJ) ;
- sondes de détection : lecture de l'infobulle de minicarte au survol, balayage manuel ;
- test contrôlé `/pgr test` (données marquées TEST, jamais mélangées aux détections réelles) ;
- isolation des erreurs : un module défaillant est désactivé sans arrêter les autres ;
- bouton autour de la minicarte (déplaçable, masquable) et fenêtre de réglages : version, membres du
  groupe qui utilisent l'addon, affichage des infos des autres joueurs, partage, herbes, minerais ;
- discussion : « Aucun joueur nommé '…' ne joue actuellement » masqué quand il vise un membre du groupe
  connecté (chuchotement mal formé d'un autre addon, par exemple ForeverGuide ; `/pgr quiet off` pour le
  revoir) ;
- français (référence) et anglais.

Prévu (non implémenté) : reste du mode de secours (marqueurs manuels partagés), carte du monde (phase 3),
réglages avancés (taille, couleurs, durées) dans la fenêtre (phase 4).

## Installation

Chemin cible : `World of Warcraft\_forever_\Interface\AddOns\PartyGatherRadar\` (client live ; la bêta
utilisait `_classic_beta_`)

**Depuis le ZIP** : extraire `dist\PartyGatherRadar-0.5.0.zip` dans le dossier `AddOns` ; le ZIP
contient déjà le dossier `PartyGatherRadar\`. Vérifier que le chemin final est
`AddOns\PartyGatherRadar\PartyGatherRadar.toc` (et non `AddOns\PartyGatherRadar\PartyGatherRadar\…`).

**Avec le script** (crée le ZIP puis copie l'addon, remplace une ancienne copie) :

```powershell
powershell -ExecutionPolicy Bypass -File Tools\package.ps1 -Install
# autre dossier (ex. bêta) :  -AddOnsPath "C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns"
```

Puis, en jeu : écran de sélection des personnages → AddOns → cocher PartyGatherRadar (et
« Charger les addons périmés » seulement si le client a changé d'interface). Aucune compilation
n'est nécessaire.

## Commandes

| Commande | Effet |
|---|---|
| `/pgr`, `/pgr config` | Fenêtre de réglages (aussi : clic sur le bouton autour de la minicarte) |
| `/pgr help` | Liste des commandes |
| `/pgr status` | État de l'addon, du groupe, des messages, des marqueurs, capacités |
| `/pgr peers` | Membres utilisant l'addon (version, protocole, compatibilité, capacités) et membres sans addon |
| `/pgr test` | Test contrôlé : marqueur TEST local, PING/PONG, marqueur TEST envoyé au groupe |
| `/pgr clear` | Retire de votre affichage les détections et marqueurs TEST, y compris ceux reçus des autres (positions historiques et emplacements connus conservés) ; `/pgr clear log` vide le journal sauvegardé |
| `/pgr spots [clear]` | Nombre d'emplacements connus (cette carte, en tout) ; `clear` les efface tous |
| `/pgr debug` | Journal de diagnostic affiché et sauvegardé |
| `/pgr version` | Version de l'addon, du protocole et build du client |
| `/pgr diag` | Sondes d'API, matrice de capacités, compteurs, dernière erreur |
| `/pgr probe [minimap\|scan\|tracking\|vignettes]` | Sondes de détection (voir [Tests/API-Probes.md](Tests/API-Probes.md)) |
| `/pgr log [n]` | Dernières lignes du journal |
| `/pgr on\|off` | Active / désactive l'addon |
| `/pgr share\|receive\|minimap\|button\|auto\|near\|quiet [on\|off]` | Partage, réception (infos des autres joueurs), affichage sur la minicarte, bouton de minicarte, détection automatique, détection de proximité sans souris, masquage de « Aucun joueur nommé … » pour un membre du groupe connecté (erreur d'un autre addon) |

## Premier essai à deux

1. Installer l'addon chez les deux joueurs, se grouper.
2. Chacun voit « <autre> utilise PartyGatherRadar 0.5.0 ». Sinon : `/pgr status` et `/pgr diag`.
3. Aekiss active Découverte d'herbes et s'approche de plantes : en quelques secondes, Aedot voit une
   icône verte à l'emplacement de chaque plante sur sa propre minicarte (survol : le nom de la plante
   en titre, « Détecté par : Aekiss »). Rien à taper : la détection est automatique.
   Sur un client qui bloque le balayage (live depuis novembre 2026) : Aekiss passe la souris sur chaque
   plante de sa minicarte ; après deux plantes, l'addon annonce « Détection au survol activée ».
   Sans souris : Aekiss tape `/pgr near on` et s'approche d'une plante (moins de 15 m) ; Aedot voit
   l'icône à ±15 m, puis ±5 m quand Aekiss est à portée d'interaction.
4. Aekiss cueille une plante : son icône disparaît chez Aedot tout de suite (sinon après deux balayages,
   environ 4 s, quand le balayage fonctionne).
5. Après l'expiration d'une détection (environ 5 min), Aedot garde une icône discrète « Emplacement
   connu » au même endroit, aussi après `/reload`.
6. Contrôle de la superposition chez Aekiss : case « Afficher aussi mes propres détections »
   (fenêtre `/pgr`), les icônes doivent recouvrir les points natifs.

## Réglages par défaut

Détection automatique, partage et réception activés ; détection de proximité désactivée ; emplacements
connus affichés ; propres détections masquées ; minicarte activée ; canal RAID en raid (expérimental), INSTANCE_CHAT
désactivé ; icônes 14 px, opacité 0,9 ; détection récente 60 s puis incertaine 240 s ; TEST 120 s.
Cases principales dans la fenêtre de réglages (`/pgr`) ; taille, couleurs et durées dans
`PartyGatherRadarDB.settings` en attendant la phase 4.

## Structure du projet

```
PartyGatherRadar/
├── PartyGatherRadar.toc        ordre de chargement, interface 16001
├── PartyGatherRadar_Forever.toc  copie exacte du TOC, chargée en priorité par le client Forever
├── Core/                       Init (espace de noms), Diagnostics, Events, Config, Commands
├── Localization/               frFR (référence), enUS
├── Detection/                  Coordinates (cartes, minicarte), Tracking (pistage, sondes), ResourceNames,
│                               AutoDetect (balayage, survol), Proximity (cible douce du jeu)
├── Communication/              Protocol (pur), Sender, GroupSync, Receiver
├── Map/                        MarkerManager (pur), KnownSpots (emplacements connus), MinimapOverlay
├── UI/                         SettingsPanel (fenêtre de réglages), MinimapButton, ChatFilter
├── Tests/                      Harness, ProtocolTests, SyncSimulationTests, run.lua, API-Probes.md, TestPlan.md
├── Tools/                      run-tests.ps1/.py, package.ps1 (non inclus dans le ZIP)
├── README.md, CHANGELOG.md, TECHNICAL-LIMITATIONS.md, LICENSE
└── PartyGatherRadar.slnx / .vcxproj   projet Visual Studio (édition, tests, empaquetage)
```

Chaque fichier Lua commence par `local addonName, ns = ...` ; seules variables globales créées :
`PartyGatherRadarDB` (SavedVariables) et `SLASH_PARTYGATHERRADAR1` (commande), vérifié par les tests,
plus deux cadres nommés : `PartyGatherRadarMinimapButton` (retrouvable par les addons qui regroupent
les boutons de minicarte) et `PartyGatherRadarSettingsFrame` (fermeture par Échap).

## Développement

- **Tests hors jeu** : `powershell -ExecutionPolicy Bypass -File Tools\run-tests.ps1`
  (Lua 5.1/LuaJIT natif, sinon Python + `lupa` dans `Tools\.venv`).
- **Paquet** : `powershell -ExecutionPolicy Bypass -File Tools\package.ps1` → `dist\PartyGatherRadar-<version>.zip`.
- **Visual Studio 2026** : ouvrir `PartyGatherRadar.slnx` ; « Générer » lance les tests puis crée le ZIP
  (projet de type Utilitaire, aucune compilation C++).
- Version unique : `## Version` du TOC et `ns.VERSION` (Core/Init.lua), vérifiés égaux par les tests ;
  historique dans [CHANGELOG.md](CHANGELOG.md).

## Licence et crédits

Licence MIT (voir [LICENSE](LICENSE)). NodeSight (CurseForge) a servi de référence **fonctionnelle**
pour identifier les API de sondage de la minicarte de Forever ; aucun code ni aucune ressource de
NodeSight n'a été copié. World of Warcraft est une marque de Blizzard Entertainment ; ce projet n'est
ni affilié ni approuvé par Blizzard.
