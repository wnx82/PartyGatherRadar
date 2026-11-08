# Journal des modifications

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) ; versions selon
[SemVer](https://semver.org/lang/fr/). La version figure dans `PartyGatherRadar.toc` et
`PartyGatherRadar_Forever.toc` (`## Version`, fichiers identiques) et `Core/Init.lua` (`ns.VERSION`).

## [0.4.1] - 2026-11-08

### Contexte

Premier essai en jeu de la 0.4.0 sur le client live (build 1.60.1.70862, deux clients). Le balayage ne
lit plus rien ; la détection au survol, le passage automatique en mode survol et la réception par le
groupe fonctionnent. Mais une herbe survolée a produit 4 messages en 0,6 s : la souris qui parcourt le
point déplace la position estimée de plus de 8 m à chaque lecture, et chaque déplacement était renvoyé.

### Corrigé

- Survol : une position affinée est renvoyée au groupe au plus toutes les 2 s. La dernière position part
  aussi après le survol, une fois le délai écoulé. La première annonce reste immédiate ; le balayage
  n'est pas concerné.
- Mode survol : l'arrivée d'un membre ne déclenche plus un envoi à chaque lecture au survol (toutes les
  0,2 s). La demande de renvoi n'était remise à zéro que par un balayage qui lit des ressources, donc
  jamais en mode survol.

### Ajouté

- 3 tests hors jeu (142 au total) : souris qui bouge sur une herbe survolée, position en attente envoyée
  après le survol, arrivée d'un membre en mode survol.

### Modifié

- Documentation : résultats du premier essai en jeu (scénario 11). Sur ce client, aucune détection n'est
  possible sans survol : aucune API ne donne les points de la minicarte.

## [0.4.0] - 2026-11-08

### Contexte

Une mise à jour du client WoW Forever de novembre 2026 restreint la sonde de minicarte : elle ne nomme plus
un point que sous le vrai curseur (constat publié par NaowhForever_Professions 1.2.17). Le balayage de la
0.3.2 ne lisait donc plus rien, sans erreur ni message : la détection s'arrêtait en silence.

### Ajouté

- Détection au survol : quand le joueur passe la souris sur un point de sa minicarte, l'infobulle native
  sous le vrai curseur est lue toutes les 0,2 s. Une herbe ou un minerai reconnu est placé sous le curseur,
  suivi et partagé avec le groupe comme une détection du balayage.
- Adaptation automatique au client : une ressource vue au survol, absente du balayage suivant alors que ce
  balayage n'a lu aucune ressource, compte comme une preuve (une par ressource physique, valable 10 min,
  effacées dès qu'un balayage lit une ressource). Après deux preuves, le balayage est déclaré aveugle :
  avertissement unique dans la discussion, mode survol, un essai de balayage toutes les 30 s, capacité
  « sondage minicarte » plus annoncée (nouveau HELLO au groupe à chaque changement de mode). Un essai qui
  relit une ressource sur au plus la moitié de ses points rétablit la détection automatique ; une
  infobulle restée figée sur tous les points ne compte pas. Le mode est mémorisé pour le build du client
  (`PartyGatherRadarDB.probe`) et réévalué à chaque nouveau build.
- Herbe cueillie par le joueur (`UNIT_SPELLCAST_SUCCEEDED` du sort de cueillette) : retirée tout de suite,
  chez lui et dans le groupe. Un filon miné n'est pas retiré, car il peut souvent être miné plusieurs fois.
- Avertissement unique après 5 balayages d'affilée interrompus par la sonde (erreur, valeur secrète), ou
  si les fonctions de sondage disparaissent du client. Avant, ces échecs restaient silencieux.
- Aucun balayage ni lecture au survol en combat ou pendant une restriction d'addons
  (`C_RestrictedActions.IsAddOnRestrictionActive` : combat, rencontre, mode défi, JcJ, carte).
- `/pgr status`, `/pgr diag` : mode de détection, ressources trouvées au survol, herbes cueillies, sonde
  « restreinte par le client » ; `/pgr probe scan` explique un balayage vide sur un client restreint.
- 15 tests hors jeu (139 au total) : client restreint, preuves et passage en mode survol, retour au
  balayage, mémoire par build, cueillette, échecs répétés, restrictions d'addons, fonctions de sondage
  absentes, preuves expirées, dédoublonnées ou effacées, infobulle figée, survol en combat.

### Modifié

- Une ressource vue seulement au survol n'est plus déclarée disparue par un balayage qui n'a lu aucune
  ressource : elle expire normalement (récente 60 s, puis incertaine 240 s).
- Balayage : un nom reconnu dont le type n'est pas pisté (filon sans Découverte de gisements) n'est plus
  compté comme une ressource lue.
- Documentation : client live (build 1.60.1.70862), restriction de novembre, scénario en jeu 11.

## [0.3.2] - 2026-11-04

### Ajouté

- `PartyGatherRadar_Forever.toc` : copie exacte de `PartyGatherRadar.toc`, chargée en priorité par le
  client WoW Forever (même convention que Questie ou Offhand). `Tools/package.ps1` l'inclut dans le ZIP et
  refuse d'empaqueter si les deux TOC diffèrent ; un test hors jeu vérifie la même chose.

### Corrigé

- Publication CurseForge : l'app CurseForge signalait la 0.3.1 « might be corrupt (Belongs to 'Retail') »
  dans l'instance Forever, car l'index de CurseForge rangeait ce fichier sous Retail 12.1.5 malgré son
  tag WoW Forever 1.60.1. La 0.3.2 est publiée comme nouveau fichier avec le tag WoW Forever 1.60.1.

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
