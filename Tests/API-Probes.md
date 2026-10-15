# Sondes d'API (phase 0)

Les sondes vérifient **dans le client réel** ce que la documentation et les tests hors jeu ne peuvent
pas garantir. Elles n'appellent que des fonctions publiques, protégées par `pcall` : une API absente
produit `ABSENT` ou `ERREUR`, jamais une erreur Lua.

## Lancer les sondes

| Commande | Effet |
|---|---|
| `/pgr diag` | Version, toutes les sondes, matrice de capacités, compteurs et dernière erreur |
| `/pgr probe` | Sondes seules |
| `/pgr probe tracking` | Types de pistage connus du personnage (herbes, minerais, actif ou non) |
| `/pgr probe vignettes` | Vignettes visibles (15 premières) et leur position, pour vérifier si des ressources en font partie |
| `/pgr probe minimap` | Sonde passive : survolez vous-même un point de la minicarte ; le nom lu et la position estimée s'affichent. Journalise aussi `UNIT_SPELLCAST_SENT` (cible des sorts de récolte). Refaire la commande pour arrêter |
| `/pgr probe scan` | Balayage unique et expérimental de la minicarte par le curseur logiciel ; chaque point trouvé devient un marqueur **TEST** local « [Sonde] nom » |
| `/pgr debug` | Journal détaillé affiché et sauvegardé dans `WTF\Account\<compte>\SavedVariables\PartyGatherRadar.lua` |
| `/pgr log 30` | 30 dernières lignes du journal |

## Statuts

| Statut | Sens |
|---|---|
| `OK` | Fonction présente / résultat cohérent |
| `ABSENT` | Fonction inexistante dans ce client |
| `INDISPONIBLE` | Fonction présente mais résultat inexploitable ici (instance, pas de groupe…) |
| `SECRET` | Le client renvoie une valeur secrète : donnée inutilisable par un addon |
| `ATTENTION` | Fonctionne mais expérimental, ou différent de la cible |
| `INFO` | Information sans jugement |
| `ERREUR` | L'appel a levé une erreur (détail affiché) |

## Liste des sondes

| Identifiant | Ce qui est vérifié | Résultat attendu sur 1.60.1 (non vérifié en jeu) |
|---|---|---|
| `build` | `GetBuildInfo()`, `WOW_PROJECT_ID`, `WOW_PROJECT_CAMELOT` | 1.60.1, build 70374 (ou plus récente), interface 16001 |
| `interface` | Interface du client = 16001 | OK |
| chemins d'API (`C_ChatInfo.*`, `C_Map.*`, `C_Minimap.*`, `C_TooltipInfo`…) | Présence des fonctions utilisées | OK, sauf éventuellement `C_VignetteInfo.*`, `GetMinimapShape` (fourni par certains addons) |
| `prefix.registered` | Préfixe `PGRadar` inscrit | OK |
| `comm.lockdown` | `C_ChatInfo.InChatMessagingLockdown()` | OK (libre) hors rencontre ; à relever en donjon |
| `comm.realmRestricted` | `AreOutgoingAddonChatMessagesRestricted()` | INFO (peu fiable selon d'autres auteurs) |
| `comm.channel` | Canal de groupe choisi | PARTY en groupe, INDISPONIBLE seul |
| `map.player` | Carte et position du joueur | OK en extérieur, INDISPONIBLE (instance) en donjon |
| `map.size` | Dimensions de la carte (m) | OK |
| `map.roundtrip` | Carte → monde → carte, écart < 0,0005 | OK |
| `UnitPosition.live` | Position monde brute | OK en extérieur (information) |
| `minimap.radius` | `C_Minimap.GetViewRadius()` et zoom | OK, valeur qui change avec le zoom |
| `minimap.rotation` | Rotation et orientation | OK si rotation désactivée |
| `minimap.shape` | `GetMinimapShape()` | INFO (ROUND par défaut) |
| `tracking.types` | Pistage herbes / minerais | Selon les métiers du personnage |
| `detection.blipEnumeration` | API d'énumération des points | INDISPONIBLE (n'existe pas) |
| `detection.minimapProbeApi` | `SetUsingSoftCursor`, `UpdateMouseoverAtPoint`, `GetMinimapMouseover` | ATTENTION : disponible (expérimental) |
| `detection.minimapTooltip` | Une infobulle de minicarte a été lue | INFO tant que la sonde n'a rien lu |
| `detection.minimapScan` | Résultat du dernier balayage | INFO tant que `/pgr probe scan` n'a pas été lancé |
| `detection.vignettes` | Nombre de vignettes visibles | INFO |

## Matrice de capacités (`/pgr diag`, `/pgr status`)

| Ligne | OUI / PARTIEL / NON CONFIRMÉ / NON |
|---|---|
| A. détection locale | NON CONFIRMÉ tant qu'aucun point n'a été lu ; PARTIEL (expérimental) après une lecture réussie |
| localisation fiable | OUI si la position et l'aller-retour carte/monde sont cohérents |
| B. synchronisation | NON CONFIRMÉ jusqu'au premier message valide d'un autre client, puis OUI |
| C. affichage minicarte | OUI si la minicarte et son rayon de vue sont lisibles |

## Rapporter les résultats

1. `/pgr debug` (activer le journal sauvegardé), puis `/pgr diag`, `/pgr probe tracking`, `/pgr probe scan`
   près de quelques plantes avec Découverte d'herbes active.
2. `/reload` pour écrire les SavedVariables.
3. Joindre `WTF\Account\<compte>\SavedVariables\PartyGatherRadar.lua` (champ `diagnostics.log`) et une
   capture de la minicarte montrant les marqueurs « [Sonde] » superposés (ou non) aux points natifs.
   Ce fichier ne contient ni mot de passe ni identifiant de compte, mais il contient des noms de
   personnages : relisez-le avant de le partager.
