# PartyGatherRadar

**Share the herbs and ore nodes your minimap tracking reveals with your whole party.** One gatherer tracks, everyone in the group sees the nodes on their own minimap.

> **Experimental prototype for World of Warcraft: Forever (1.60.1, interface 16001).** It relies on minimap APIs that only exist on Forever. Group communication and herb detection have been checked in game with two clients; please report what you see.
>
> **November 2026:** a WoW Forever update no longer lets addons read the minimap remotely. Version 0.4.0 notices it by itself and switches to **hover detection**: move your mouse over a herb or ore on your minimap and it is shared with your group. If the probe comes back, automatic detection comes back too.
>
> **Without the mouse (0.5.0):** type `/pgr near on` and the herb or ore node closest to you (about 15 yd) is shared through the game's own soft interact target, even without tracking. Nodes already seen are kept as **known spots** and stay on everyone's minimap as discreet icons. Not checked in game yet.

## How it works

1. A party member with **Find Herbs** or **Find Minerals** active walks around as usual. Nothing to type.
2. Every 2 seconds the addon reads the gatherer's minimap through Forever's official minimap probe API and keeps only known herb and ore names (quest areas and player names are ignored).
3. Each node is sent to the group. Other members see an icon at the same place on **their own minimap**; hovering it shows the plant name, who found it and how old the information is.
4. When the node disappears (gathered), its icon is removed for everyone within a few seconds.
5. If the client blocks the minimap sweep, nodes you hover with the mouse on your minimap are shared instead, and a herb you pick is removed for everyone right away.
6. With proximity detection on (`/pgr near on`), the node the game picks as your soft interact target (the closest one, about 15 yd) is shared at your position, without the mouse.

## Features

- Automatic detection and sharing, refreshed every 25 s while the node stays visible.
- Works both ways: any gatherer in the group shares with everyone.
- Minimap button and settings window (`/pgr`): addon version, which party members use PartyGatherRadar, show or hide other players' information, sharing, herbs, ores.
- Proximity detection without the mouse (off by default): the addon turns on the game's soft interact target and restores your original settings with `/pgr near off`. Nothing is changed in combat.
- Known spots: herbs and ore nodes seen, gathered or received are kept per map and shown as discreet icons, marked "presence not confirmed". `/pgr spots` counts them, `/pgr spots clear` removes them.
- Herb names learned automatically the first time you gather a plant missing from the built-in list.
- Adapts to the client: a blocked sweep, repeated probe failures and addon restrictions (encounters, Mythic+, PvP) are detected and reported once in chat.
- Hides "No player named '...' is currently playing" when it targets an online group member: another addon whispering a malformed name (seen with ForeverGuide). `/pgr quiet off` shows it again.
- Diagnostics for bug reports: `/pgr diag`, saved to the SavedVariables.
- French and English.

## What it does not do

- No memory reading, no external program, no automation of movement, interaction or gathering.
- Never turns tracking on by itself, and never invents a position: no reliable data, no icon.
- Does not probe the minimap in combat or while your mouse is over the minimap.

## Commands

- `/pgr`: settings window. `/pgr help`: all commands.
- `/pgr status`, `/pgr peers`, `/pgr test` (controlled test marker), `/pgr diag`.
- `/pgr spots [clear]`: known spots.
- `/pgr share|receive|minimap|button|auto|near on|off`: quick toggles (`near`: proximity detection without the mouse).

## Known limitations

- Experimental: icon accuracy is about 10 to 30 m when the minimap is zoomed out.
- On the restricted live client, no addon can see minimap nodes without the mouse over them. Without the mouse, only the closest node (about 15 yd, with `/pgr near on`) and known spots are available. Hover detection and sharing were checked in game with two clients on November 8, 2026; proximity detection and known spots were not checked in game yet.
- A known spot only means a node was seen there: it may have been gathered since.
- Herb and ore names are matched in French and English; other client languages learn names when gathering.
- Addon messages only reach party or raid members; trial accounts cannot send addon messages on Forever.

---

# PartyGatherRadar (français)

**Partagez avec tout le groupe les herbes et minerais que le pistage affiche sur votre minicarte.** Un herboriste ou un mineur piste, chaque membre du groupe voit les ressources sur sa propre minicarte.

> **Prototype expérimental pour World of Warcraft: Forever (1.60.1, interface 16001).** Il utilise des fonctions de minicarte propres à Forever. La communication de groupe et la lecture des plantes ont été vérifiées en jeu avec deux clients ; vos retours sont les bienvenus.
>
> **Novembre 2026 :** une mise à jour de WoW Forever ne laisse plus les addons lire la minicarte à distance. La version 0.4.0 le repère seule et passe en **détection au survol** : passez la souris sur une herbe ou un minerai de votre minicarte, il est partagé avec le groupe. Si la sonde revient, la détection automatique revient aussi.
>
> **Sans souris (0.5.0) :** tapez `/pgr near on` : l'herbe ou le filon le plus proche (environ 15 m) est partagé grâce à la cible d'interaction douce du jeu, même sans pistage. Les ressources déjà vues sont gardées comme **emplacements connus** et restent en icônes discrètes sur la minicarte de chacun. Pas encore vérifié en jeu.

## Fonctionnement

1. Un membre du groupe active **Découverte d'herbes** ou **Découverte de gisements** et joue normalement. Rien à taper.
2. Toutes les 2 secondes, l'addon lit sa minicarte avec la fonction officielle de sondage de Forever et ne garde que les noms d'herbes et de minerais connus (zones de quête et joueurs ignorés).
3. Chaque ressource est envoyée au groupe. Les autres membres voient une icône au même endroit **sur leur propre minicarte** ; le survol affiche le nom de la plante, qui l'a trouvée et depuis quand.
4. Quand la ressource disparaît (récoltée), son icône est retirée chez tout le monde en quelques secondes.
5. Si le client bloque le balayage de la minicarte, les ressources survolées à la souris sur votre minicarte sont partagées à la place, et une herbe cueillie est retirée chez tous tout de suite.
6. Avec la détection de proximité (`/pgr near on`), la ressource que le jeu choisit comme cible d'interaction douce (la plus proche, environ 15 m) est partagée à votre position, sans souris.

## Fonctions

- Détection et partage automatiques, rafraîchis toutes les 25 s tant que la ressource reste visible.
- Dans les deux sens : chaque récolteur du groupe partage avec tous.
- Bouton de minicarte et fenêtre de réglages (`/pgr`) : version, membres qui utilisent l'addon, afficher ou masquer les infos des autres joueurs, partage, herbes, minerais.
- Détection de proximité sans souris (désactivée par défaut) : l'addon active la cible d'interaction douce du jeu et rétablit vos réglages d'origine avec `/pgr near off`. Rien n'est changé en combat.
- Emplacements connus : herbes et filons vus, récoltés ou reçus, gardés par carte et affichés en icônes discrètes, marqués « présence non confirmée ». `/pgr spots` les compte, `/pgr spots clear` les efface.
- Noms d'herbes appris à la première récolte d'une plante absente de la liste.
- S'adapte au client : balayage bloqué, échecs répétés de la sonde et restrictions d'addons (rencontres, mode défi, JcJ) repérés et signalés une fois dans la discussion.
- Masque « Aucun joueur nommé '…' ne joue actuellement » quand il vise un membre du groupe connecté : un autre addon chuchote un nom mal formé (vu avec ForeverGuide). `/pgr quiet off` le réaffiche.
- Diagnostic pour les rapports de bogue : `/pgr diag`, sauvegardé dans les SavedVariables.
- Français et anglais.

## Ce que l'addon ne fait pas

- Aucune lecture de mémoire, aucun programme externe, aucune automatisation du déplacement, des interactions ou de la récolte.
- N'active jamais le pistage à votre place et n'invente aucune position : sans donnée fiable, pas d'icône.
- Ne sonde pas la minicarte en combat, ni quand votre souris la survole.

## Commandes

- `/pgr` : fenêtre de réglages. `/pgr help` : toutes les commandes.
- `/pgr status`, `/pgr peers`, `/pgr test` (marqueur de test contrôlé), `/pgr diag`.
- `/pgr spots [clear]` : emplacements connus.
- `/pgr share|receive|minimap|button|auto|near on|off` : réglages rapides (`near` : détection de proximité sans souris).

## Limites connues

- Expérimental : précision des icônes d'environ 10 à 30 m quand la minicarte est dézoomée.
- Sur le client live restreint, aucun addon ne voit plus les ressources de la minicarte sans la souris dessus. Sans souris, seules la ressource la plus proche (environ 15 m, avec `/pgr near on`) et les emplacements connus sont disponibles. Détection au survol et partage vérifiés en jeu avec deux clients le 8 novembre 2026 ; détection de proximité et emplacements connus pas encore vérifiés en jeu.
- Un emplacement connu indique seulement qu'une ressource y a été vue : elle a pu être récoltée depuis.
- Noms d'herbes et de minerais reconnus en français et en anglais ; dans les autres langues, les noms sont appris à la récolte.
- Les messages d'addon n'atteignent que les membres du groupe ou du raid ; les comptes d'essai ne peuvent pas en envoyer sur Forever.

MIT License. Not affiliated with or endorsed by Blizzard Entertainment.
