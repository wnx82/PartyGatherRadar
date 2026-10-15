# PartyGatherRadar

Addon pour **World of Warcraft: Forever** (bêta 1.60.1, interface 16001) : partager en temps réel,
entre membres d'un groupe, les ressources de récolte (herbes, minerais) détectées sur la minicarte.

> **État : prototype 0.1.1 (phases 0 et 1).** L'infrastructure (protocole réseau, découverte des
> membres, couche d'icônes sur la minicarte, diagnostics, sondes de détection) est en place et testée
> hors jeu. Le partage automatique des plantes détectées arrive en phase 2/3. **Vérifié en jeu** (2026-10-15,
> deux clients) : chargement, sondes d'API, identité et communication de groupe. **Pas encore vérifié** :
> détection sur la minicarte et affichage des icônes. Voir [Tests/TestPlan.md](Tests/TestPlan.md).

## Objectif

Aekiss (prêtre herboriste) active Découverte d'herbes ; une plante apparaît sur sa minicarte ;
Aedot (démoniste, sans Herboristerie), dans le même groupe, voit un marqueur au même endroit sur sa
propre minicarte. Le partage fonctionne dans les deux sens et prévoit les minerais.

## Faisabilité (phase 0)

| Capacité | Verdict |
|---|---|
| Lister les points de pistage de la minicarte | **Impossible** : aucune API |
| Lire le nom d'un point (survol, ou sondage officiel propre à Forever) | **Possible, expérimental**, non vérifié en jeu |
| Communiquer entre membres du groupe (messages d'addon) | **Vérifié en jeu** entre deux clients (0.1.1) |
| Afficher des icônes personnalisées sur la minicarte | Possible, non vérifié en jeu |

Détails, niveaux de confiance et sources : [TECHNICAL-LIMITATIONS.md](TECHNICAL-LIMITATIONS.md).

Principes : uniquement des API publiques du client, aucune lecture de mémoire, aucun programme
externe, aucune automatisation de déplacement, d'interaction ou de récolte, aucun pistage activé
artificiellement chez un joueur qui ne le possède pas. Aucune position n'est inventée : sans donnée
fiable, rien n'est affiché.

## Fonctionnalités de la version 0.1.1

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
  l'orientation est accessible, infobulle détaillée ;
- diagnostics : sondes d'API, matrice de capacités, compteurs, journal sauvegardable ; rapport de
  `/pgr diag` sauvegardé dans `diagnostics.lastReport` ;
- sondes de détection : lecture de l'infobulle de minicarte au survol, balayage expérimental ;
- test contrôlé `/pgr test` (données marquées TEST, jamais mélangées aux détections réelles) ;
- isolation des erreurs : un module défaillant est désactivé sans arrêter les autres ;
- français (référence) et anglais.

Prévu (non implémenté) : détection continue des herbes et minerais et leur partage (phases 2-3),
mode de secours (positions de récolte, marqueurs manuels partagés), carte du monde (phase 3),
fenêtre de paramètres à onglets et bouton de minicarte (phase 4).

## Installation

Chemin cible : `World of Warcraft\_classic_beta_\Interface\AddOns\PartyGatherRadar\`

**Depuis le ZIP** : extraire `dist\PartyGatherRadar-0.1.1.zip` dans le dossier `AddOns` ; le ZIP
contient déjà le dossier `PartyGatherRadar\`. Vérifier que le chemin final est
`AddOns\PartyGatherRadar\PartyGatherRadar.toc` (et non `AddOns\PartyGatherRadar\PartyGatherRadar\…`).

**Avec le script** (crée le ZIP puis copie l'addon, remplace une ancienne copie) :

```powershell
powershell -ExecutionPolicy Bypass -File Tools\package.ps1 -Install
# autre dossier :  -AddOnsPath "D:\Jeux\World of Warcraft\_classic_beta_\Interface\AddOns"
```

Puis, en jeu : écran de sélection des personnages → AddOns → cocher PartyGatherRadar (et
« Charger les addons périmés » seulement si le client a changé d'interface). Aucune compilation
n'est nécessaire.

## Commandes

| Commande | Effet |
|---|---|
| `/pgr`, `/pgr help` | Aide (la fenêtre de paramètres arrive en phase 4) |
| `/pgr status` | État de l'addon, du groupe, des messages, des marqueurs, capacités |
| `/pgr peers` | Membres utilisant l'addon (version, protocole, compatibilité, capacités) et membres sans addon |
| `/pgr test` | Test contrôlé : marqueur TEST local, PING/PONG, marqueur TEST envoyé au groupe |
| `/pgr clear` | Retire de votre affichage les détections et marqueurs TEST, y compris ceux reçus des autres (positions historiques conservées) ; `/pgr clear log` vide le journal sauvegardé |
| `/pgr debug` | Journal de diagnostic affiché et sauvegardé |
| `/pgr version` | Version de l'addon, du protocole et build du client |
| `/pgr diag` | Sondes d'API, matrice de capacités, compteurs, dernière erreur |
| `/pgr probe [minimap\|scan\|tracking\|vignettes]` | Sondes de détection (voir [Tests/API-Probes.md](Tests/API-Probes.md)) |
| `/pgr log [n]` | Dernières lignes du journal |
| `/pgr on\|off` | Active / désactive l'addon |
| `/pgr share\|receive\|minimap [on\|off]` | Partage, réception, affichage sur la minicarte |

## Premier essai à deux

1. Installer l'addon chez les deux joueurs, se grouper.
2. Chacun voit « <autre> utilise PartyGatherRadar 0.1.1 ». Sinon : `/pgr status` et `/pgr diag`.
3. Aekiss tape `/pgr test` : un marqueur bleu TEST apparaît chez les deux, au même endroit du terrain,
   et Aekiss lit « PONG reçu de Aedot ».
4. Aekiss, Découverte d'herbes active : `/pgr probe scan` ; les marqueurs « [Sonde] » doivent
   recouvrir les points natifs. Envoyer le résultat (voir [Tests/API-Probes.md](Tests/API-Probes.md)).

## Réglages par défaut

Partage et réception activés, minicarte activée, canal RAID en raid (expérimental), INSTANCE_CHAT
désactivé ; icônes 14 px, opacité 0,9 ; détection récente 60 s puis incertaine 240 s ; TEST 120 s.
Modifiables dans `PartyGatherRadarDB.settings` en attendant la fenêtre de paramètres.

## Structure du projet

```
PartyGatherRadar/
├── PartyGatherRadar.toc        ordre de chargement, interface 16001
├── Core/                       Init (espace de noms), Diagnostics, Events, Config, Commands
├── Localization/               frFR (référence), enUS
├── Detection/                  Coordinates (cartes, minicarte), Tracking (pistage, sondes)
├── Communication/              Protocol (pur), Sender, GroupSync, Receiver
├── Map/                        MarkerManager (pur), MinimapOverlay
├── Tests/                      Harness, ProtocolTests, SyncSimulationTests, run.lua, API-Probes.md, TestPlan.md
├── Tools/                      run-tests.ps1/.py, package.ps1 (non inclus dans le ZIP)
├── README.md, CHANGELOG.md, TECHNICAL-LIMITATIONS.md, LICENSE
└── PartyGatherRadar.slnx / .vcxproj   projet Visual Studio (édition, tests, empaquetage)
```

Chaque fichier Lua commence par `local addonName, ns = ...` ; seules variables globales créées :
`PartyGatherRadarDB` (SavedVariables) et `SLASH_PARTYGATHERRADAR1` (commande), vérifié par les tests.

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
