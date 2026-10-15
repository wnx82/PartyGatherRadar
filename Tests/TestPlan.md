# Plan de tests — PartyGatherRadar 0.1.1

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

Le partage automatique des détections réelles n'existe pas en 0.1.1. Vérifiable aujourd'hui :
`/pgr test` (marqueur TEST) et l'alignement des marqueurs reçus avec la position réelle.

| Étape | Résultat attendu | Statut |
|---|---|---|
| Les deux personnages côte à côte, `/pgr test` chez Aekiss | Le marqueur TEST apparaît au même endroit sur les deux minicartes | Partiel (2026-10-15) : côte à côte (4 m), test lancé par Aedot, marqueur reçu par Aekiss ; position à l'écran non rapportée (pas de capture) |
| Aedot à 50 m d'Aekiss | Le marqueur reste au même endroit du terrain (décalé sur la minicarte d'Aedot) | Non exécuté |
| Survol du marqueur chez Aedot | Infobulle : Nom, Type Test, Détecté par Aekiss, État TEST, Dernière détection, Distance | Non exécuté |

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

### Scénarios complémentaires

| Étape | Résultat attendu | Statut |
|---|---|---|
| Donjon : `/pgr status`, `/pgr test` | Position indisponible (instance) ; éventuel verrouillage de messagerie compté (« verrouillés ») | Non exécuté |
| Raid de 3+ joueurs | Canal RAID, découverte de tous | Non exécuté |
| Addon de minicarte (SexyMap, Leatrix Plus minicarte carrée) | Marqueurs dans la zone visible, forme carrée respectée | Non exécuté |
