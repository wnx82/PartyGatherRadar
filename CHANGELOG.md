# Journal des modifications

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) ; versions selon
[SemVer](https://semver.org/lang/fr/). La version figure dans `PartyGatherRadar.toc` (`## Version`) et
`Core/Init.lua` (`ns.VERSION`).

## [0.3.1] - 2026-10-15

### Modifié

- Infobulle des icônes sur la minicarte : le nom de la ressource (« Pacifique ») sert de titre, dans la
  couleur de son statut, à la place de « PartyGatherRadar » ; la ligne « Nom » n'est plus répétée. Si le
  nom est absent ou masqué (`showTooltipName`), le titre de l'addon revient.

## [0.3.0] - 2026-10-15

Phases 2 et 3 (cœur) : l'addon fonctionne seul, sans commande. Testé hors jeu, pas encore vérifié en jeu.

### Ajouté

- Détection automatique (`Detection/AutoDetect.lua`) : quand le pistage des herbes ou des minerais est
  actif, la minicarte est sondée toutes les 2 s (API de sondage propre à Forever, vérifiée en jeu le
  2026-10-15), par lots de 40 points par image ; chaque lot utilise la position du joueur du moment, ce qui
  garde le balayage juste en déplacement. Jamais en combat, jamais quand la souris survole la minicarte,
  jamais sans pistage actif.
- Suivi des ressources : une plante revue garde son identifiant et sa position s'affine (moyenne) ; elle
  est envoyée au groupe à sa découverte, rafraîchie toutes les 25 s tant qu'elle reste visible, renvoyée à
  un nouveau membre, puis retirée chez tous (REMOVE) quand elle manque à 2 balayages alors qu'elle devrait
  être visible (récoltée ou disparue).
- Tri des noms (`Detection/ResourceNames.lua`) : herbes et minerais en français et en anglais, comparés
  sans accents ni majuscules, forme des noms de gisements (« Filon de ... », « ... Vein »). Les zones de
  quête et les joueurs, vus en jeu dans l'infobulle de la minicarte, sont ignorés.
- Noms appris à la récolte : le nom ciblé par Cueillette ou Minage devient une ressource connue
  (`PartyGatherRadarDB.learnedNames`, 200 noms au plus par type).
- Réglages `autoDetect` (cases de la fenêtre, `/pgr auto on|off`) et `showOwnDetections` (ses propres
  détections sont masquées par défaut sur sa minicarte : le point natif y est déjà).
- Diagnostics : sonde `detection.auto`, ligne de `/pgr status`, capacité « détection locale » ;
  journal : découverte, disparition, noms ignorés (une fois chacun), noms appris, réception du PONG.
- Tests hors jeu (122) : ressources simulées dans le monde, zones de quête, combat, survol de la
  minicarte, déplacement, disparition, rafraîchissement, apprentissage des noms.

### Modifié

- `/pgr probe scan` : une seule ligne de résumé dans le journal pour les repères qui ne sont pas des
  ressources (un balayage remplissait le journal sauvegardé) ; interrompt la détection automatique.
- Détection automatique : points touchés regroupés par voisinage sur la grille, une ressource donne un
  seul repère. Le regroupement autour d'un centre mobile, gardé par `/pgr probe scan`, a découpé le
  joueur en 3 repères en jeu le 2026-10-15.

## [0.2.0] - 2026-10-15

### Ajouté

- Bouton autour de la minicarte (icône de fleur) : clic pour ouvrir la fenêtre de réglages, glisser pour
  le déplacer sur le bord (minicarte ronde ou carrée), infobulle avec la version et le nombre de membres
  du groupe qui utilisent l'addon. Masquable (`/pgr button off`), position conservée.
- Fenêtre de réglages (`/pgr`, `/pgr config`, Échap pour fermer) : version de l'addon, du protocole et du
  client ; membres du groupe avec leur version de PartyGatherRadar ou « sans addon détecté » ; cases
  « Activer », « Afficher les infos des autres joueurs », « Partager mes infos », « Afficher les
  marqueurs sur la minicarte », « Herbes », « Minerais », « Bouton autour de la minicarte »,
  « Journal de diagnostic » ; boutons « Test de communication » et « Diagnostic ».
- Réglages `showMinimapButton` et `minimapButtonAngle` (schéma inchangé, valeurs par défaut ajoutées).
- Tests hors jeu (106) : bouton, position, déplacement, masquage, infobulle, fenêtre, cases, anglais.

### Modifié

- `/pgr` sans argument ouvre la fenêtre de réglages ; la liste des commandes reste dans `/pgr help`.
- `/pgr peers` liste les membres sans addon à partir de la composition du groupe déjà connue.

## [0.1.1] - 2026-10-15

Correctif issu du premier essai en jeu à deux clients (journal d'Aedot du 2026-10-15).

### Corrigé

- Noms régionaux de WoW Forever (prénom et nom de famille) : l'émetteur reçu a la forme
  `Prénom Nom-Royaume` (ex. `Aedot Wnx-ClassicBetaPvE2`), alors que l'identité était construite avec
  `UnitFullName` (`Nom-Royaume`). Conséquence en 0.1.0 : chaque membre rejeté (`not_in_group`), propre écho
  non reconnu, aucune découverte mutuelle. Quand `RegionalUniqueNamesEnabled()` est vrai, l'identité est
  maintenant `Prénom Nom` (via `UnitNameUnmodified`, comme `NameUtil` de Blizzard) et le royaume est retiré
  de l'émetteur. Les royaumes classiques gardent `Nom-Royaume`.

### Ajouté

- `/pgr diag` sauvegarde son rapport complet (sondes, capacités, compteurs, rejets, dernière erreur) dans
  `PartyGatherRadarDB.diagnostics.lastReport`, même sans le mode journal.
- Sonde `identity.player` : identité utilisée, mode des noms régionaux, valeurs brutes de `UnitFullName`
  et `UnitNameUnmodified`.
- Journal : rejet `not_in_group` avec l'émetteur brut quand il diffère de l'identité comparée ; ligne
  « composition » quand la taille du groupe change.
- Tests hors jeu (97) : simulation de clients Forever à noms régionaux (découverte, écho, PING/PONG,
  homonymes de prénom, départ, normalisation, rapport de diagnostic).

## [0.1.0] - 2026-10-14

Prototype des phases 0 (recherche et diagnostic) et 1 (prototype minimal). Non vérifié en jeu.

### Ajouté

- TOC pour WoW Forever 1.60.1 (interface 16001), SavedVariables `PartyGatherRadarDB` avec validation.
- Espace de noms commun, répartiteur d'événements protégé (désactivation d'un module après 3 erreurs),
  minuteurs, journal de diagnostic sauvegardable.
- Sondes d'API et matrice de capacités (`/pgr diag`, `/pgr probe`).
- Sondes de détection expérimentales : lecture de l'infobulle de minicarte au survol, balayage unique
  par les fonctions officielles `Minimap:SetUsingSoftCursor` / `Minimap:UpdateMouseoverAtPoint` /
  `C_TooltipInfo.GetMinimapMouseover` (marqueurs TEST de calibration).
- Protocole réseau v1 (préfixe `PGRadar`) : HELLO, BYE, PING/PONG, NODE, REMOVE, validation stricte.
- File d'envoi (limitation de fréquence, regroupement, gestion des refus et du verrouillage).
- Découverte des membres du groupe, compatibilité de protocole, nettoyage au départ.
- Gestion des marqueurs : statuts récent / incertain / historique / manuel / TEST, déduplication,
  expiration, séparation stricte TEST / réel.
- Couche d'icônes sur la minicarte avec infobulle.
- Commandes `/pgr` : help, status, peers, test, clear, debug, version, diag, probe, log, on/off, share,
  receive, minimap.
- Localisation française (référence) et anglaise.
- Tests hors jeu (89) : protocole, validation, déduplication, versions, expiration, groupe, séparation
  TEST / réel, simulation multi-clients, messages hostiles ; plan de tests en jeu.
- Scripts : tests (`Tools/run-tests.ps1`), empaquetage et installation (`Tools/package.ps1`) ;
  génération Visual Studio branchée sur ces scripts.

### Sécurité et robustesse (revue de code avant publication)

- Identifiants de carte reçus vérifiés (`C_Map.GetMapInfo`) et appels `C_Map` protégés.
- Quotas par émetteur, alias de fusion bornés, sources non encore prises en charge refusées.
- PONG limités par pair, réponses HELLO groupées et différées, NODE ignorés après un BYE.
- Valeurs secrètes testées avant toute comparaison ; échecs de conversion de carte retentés.
- Désactivation d'un module seulement après une rafale d'erreurs (3 en 60 s).
- Balayage de la sonde abandonné si le personnage bouge, tourne ou garde la souris sur la minicarte.
- Réception désactivée : les marqueurs déjà reçus sont aussi masqués.
