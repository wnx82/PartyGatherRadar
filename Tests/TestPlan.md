# Plan de tests — PartyGatherRadar 0.1.0

Deux niveaux de tests :

1. **Tests automatisés hors jeu** : Lua 5.1 + bouchons de l'API WoW + simulation de plusieurs clients
   reliés par un faux réseau. Ils valident la logique de l'addon contre le comportement *documenté*.
2. **Tests en jeu** : seuls capables de valider le comportement réel du client Forever.
   **Aucun n'a encore été exécuté** : leur statut est « Non exécuté » tant qu'un rapport n'a pas été fourni.

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
| Changements de groupe | Départ d'un membre, dissolution du groupe, BYE, /reload, membre sans addon, raid |
| Séparation simulé / réel | Magasins séparés, mélanges refusés, pas de fusion TEST/réel, sonde de calibration en TEST uniquement |
| Robustesse | Module en erreur désactivé seul (rafale de 3 erreurs en 60 s), événement inconnu refusé sans erreur, écouteur retiré pendant la répartition, échec de conversion de carte retenté, toutes les commandes `/pgr`, client anglais |
| Messages hostiles | Carte inconnue, sources non prises en charge, flots de PING et de HELLO, NODE après BYE, quota par émetteur, alias bornés, journal non inondé |
| Projet | TOC (interface, version, fichiers), compilation Lua 5.1, aucun fichier hors TOC, aucune variable globale inattendue |

### Dernier résultat

| Date | Interpréteur | Résultat |
|---|---|---|
| 2026-10-14 | Lua 5.1 embarqué (lupa) | 89 réussis, 0 échec |

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
| `/pgr version` | 1.60.1, build ≥ 70374, interface 16001, WoW Forever : oui | Non exécuté |
| `/pgr diag` | Aucune `ERREUR` ; `detection.minimapProbeApi` = ATTENTION (disponible) ; localisation fiable = OUI en extérieur | Non exécuté |
| Aekiss : `/pgr probe tracking` | Découverte d'herbes listée (active ou non) | Non exécuté |
| Aekiss, pistage herbes actif, `/pgr probe minimap` puis survol d'un point | Nom de la plante affiché, position plausible | Non exécuté |
| Aekiss : `/pgr probe scan` hors combat, souris hors de la minicarte | Marqueurs « [Sonde] … » **superposés** aux points natifs (capture d'écran), aucun clignotement d'infobulle | Non exécuté |
| Idem, minicarte zoomée au maximum puis au minimum | Superposition conservée ; précision meilleure au zoom maximal | Non exécuté |
| Idem avec `/console rotateMinimap 1` | Superposition conservée, ou marqueurs masqués si l'orientation est inaccessible | Non exécuté |
| Idem en combat | « balayage impossible : en combat » | Non exécuté |
| Aedot : `/pgr probe tracking`, `/pgr probe scan` | Pas de pistage d'herbes ; aucune plante trouvée (seuls PNJ/joueurs éventuels) | Non exécuté |

### Scénario 1 — HELLO et découverte mutuelle

| Étape | Résultat attendu | Statut |
|---|---|---|
| Aekiss invite Aedot | Chez chacun : « <autre> utilise PartyGatherRadar 0.1.0 (protocole 1) » en quelques secondes | Non exécuté |
| `/pgr peers` chez les deux | L'autre listé, compatible, capacités cohérentes | Non exécuté |
| `/pgr status` | B. synchronisation = OUI (message valide reçu) | Non exécuté |
| `/pgr test` chez Aekiss | Marqueur TEST local à ~21 m au nord-est ; « PONG reçu de Aedot en N ms » ; marqueur TEST chez Aedot | Non exécuté |

### Scénario 2 — Détections accessibles à chacun

| Étape | Résultat attendu | Statut |
|---|---|---|
| Aekiss pistage herbes actif, Aedot sans pistage, `/pgr peers` | Aekiss annonce « herbes », Aedot non | Non exécuté |
| `/pgr probe scan` chez les deux au même endroit | Plantes trouvées seulement chez Aekiss | Non exécuté |

### Scénario 3 — Transmission d'une plante (phase 3)

Le partage automatique des détections réelles n'existe pas en 0.1.0. Vérifiable aujourd'hui :
`/pgr test` (marqueur TEST) et l'alignement des marqueurs reçus avec la position réelle.

| Étape | Résultat attendu | Statut |
|---|---|---|
| Les deux personnages côte à côte, `/pgr test` chez Aekiss | Le marqueur TEST apparaît au même endroit sur les deux minicartes | Non exécuté |
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
