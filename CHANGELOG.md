# Journal des modifications

Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) ; versions selon
[SemVer](https://semver.org/lang/fr/). La version figure dans `PartyGatherRadar.toc` (`## Version`) et
`Core/Init.lua` (`ns.VERSION`).

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
