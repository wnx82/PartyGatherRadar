# PartyGatherRadar

**Share the herbs and ore nodes your minimap tracking reveals with your whole party.** One gatherer tracks, everyone in the group sees the nodes on their own minimap.

> **Experimental prototype for World of Warcraft: Forever (beta 1.60.1, interface 16001).** It relies on minimap APIs that only exist on Forever. Group communication and herb detection have been checked in game with two clients; the full automatic sharing is new, so please report what you see.

## How it works

1. A party member with **Find Herbs** or **Find Minerals** active walks around as usual. Nothing to type.
2. Every 2 seconds the addon reads the gatherer's minimap through Forever's official minimap probe API and keeps only known herb and ore names (quest areas and player names are ignored).
3. Each node is sent to the group. Other members see an icon at the same place on **their own minimap**; hovering it shows the plant name, who found it and how old the information is.
4. When the node disappears (gathered), its icon is removed for everyone within a few seconds.

## Features

- Automatic detection and sharing, refreshed every 25 s while the node stays visible.
- Works both ways: any gatherer in the group shares with everyone.
- Minimap button and settings window (`/pgr`): addon version, which party members use PartyGatherRadar, show or hide other players' information, sharing, herbs, ores.
- Herb names learned automatically the first time you gather a plant missing from the built-in list.
- Diagnostics for bug reports: `/pgr diag`, saved to the SavedVariables.
- French and English.

## What it does not do

- No memory reading, no external program, no automation of movement, interaction or gathering.
- Never turns tracking on by itself, and never invents a position: no reliable data, no icon.
- Does not probe the minimap in combat or while your mouse is over the minimap.

## Commands

- `/pgr`: settings window. `/pgr help`: all commands.
- `/pgr status`, `/pgr peers`, `/pgr test` (controlled test marker), `/pgr diag`.
- `/pgr share|receive|minimap|button|auto on|off`: quick toggles.

## Known limitations

- Experimental: icon accuracy is about 10 to 30 m when the minimap is zoomed out.
- Herb and ore names are matched in French and English; other client languages learn names when gathering.
- Addon messages only reach party or raid members; trial accounts cannot send addon messages on Forever.

---

# PartyGatherRadar (français)

**Partagez avec tout le groupe les herbes et minerais que le pistage affiche sur votre minicarte.** Un herboriste ou un mineur piste, chaque membre du groupe voit les ressources sur sa propre minicarte.

> **Prototype expérimental pour World of Warcraft: Forever (bêta 1.60.1, interface 16001).** Il utilise des fonctions de minicarte propres à Forever. La communication de groupe et la lecture des plantes ont été vérifiées en jeu avec deux clients ; le partage automatique complet est nouveau : vos retours sont les bienvenus.

## Fonctionnement

1. Un membre du groupe active **Découverte d'herbes** ou **Découverte de gisements** et joue normalement. Rien à taper.
2. Toutes les 2 secondes, l'addon lit sa minicarte avec la fonction officielle de sondage de Forever et ne garde que les noms d'herbes et de minerais connus (zones de quête et joueurs ignorés).
3. Chaque ressource est envoyée au groupe. Les autres membres voient une icône au même endroit **sur leur propre minicarte** ; le survol affiche le nom de la plante, qui l'a trouvée et depuis quand.
4. Quand la ressource disparaît (récoltée), son icône est retirée chez tout le monde en quelques secondes.

## Fonctions

- Détection et partage automatiques, rafraîchis toutes les 25 s tant que la ressource reste visible.
- Dans les deux sens : chaque récolteur du groupe partage avec tous.
- Bouton de minicarte et fenêtre de réglages (`/pgr`) : version, membres qui utilisent l'addon, afficher ou masquer les infos des autres joueurs, partage, herbes, minerais.
- Noms d'herbes appris à la première récolte d'une plante absente de la liste.
- Diagnostic pour les rapports de bogue : `/pgr diag`, sauvegardé dans les SavedVariables.
- Français et anglais.

## Ce que l'addon ne fait pas

- Aucune lecture de mémoire, aucun programme externe, aucune automatisation du déplacement, des interactions ou de la récolte.
- N'active jamais le pistage à votre place et n'invente aucune position : sans donnée fiable, pas d'icône.
- Ne sonde pas la minicarte en combat, ni quand votre souris la survole.

## Commandes

- `/pgr` : fenêtre de réglages. `/pgr help` : toutes les commandes.
- `/pgr status`, `/pgr peers`, `/pgr test` (marqueur de test contrôlé), `/pgr diag`.
- `/pgr share|receive|minimap|button|auto on|off` : réglages rapides.

## Limites connues

- Expérimental : précision des icônes d'environ 10 à 30 m quand la minicarte est dézoomée.
- Noms d'herbes et de minerais reconnus en français et en anglais ; dans les autres langues, les noms sont appris à la récolte.
- Les messages d'addon n'atteignent que les membres du groupe ou du raid ; les comptes d'essai ne peuvent pas en envoyer sur Forever.

MIT License. Not affiliated with or endorsed by Blizzard Entertainment.
