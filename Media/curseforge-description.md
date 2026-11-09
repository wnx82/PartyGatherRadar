# PartyGatherRadar

**Share the herbs and ore nodes on your minimap with your whole party.** Move the mouse over a herb or ore icon on your minimap, and everyone in the group sees it on their own minimap.

> **Important: hover with the mouse.** Since Blizzard's November 2026 WoW Forever client update (build 70862), addons can no longer read the minimap on their own: the game only names a minimap icon while the real mouse cursor is over it. Blizzard says this is intended ("Minimap is off limits"), so it is not an addon bug. **A herb or ore node now appears for your group only when the player who sees it moves the mouse over its icon on the minimap.** Before the update, nodes were shared automatically. The addon notices the restriction by itself and switches to hover detection.
>
> **Without the mouse**, these optional sources help:
>
> - `/pgr near on`: the node right next to you (the game's soft interact target, about 4 to 13 m in practice) is shared, even without tracking.
> - **Known spots**: nodes already seen stay on the minimap as discreet icons ("presence not confirmed"). You can hide them in the settings window.
> - **Spawn points (new in 0.6.0, off by default)**: with **QuestieDB** installed (it comes with Questie), `/pgr spawns on` shows where each herb and ore node can spawn, as pale icons (presence not confirmed). Not checked in game yet.
>
> Experimental prototype for World of Warcraft: Forever (1.60.1, interface 16001). Please report what you see.

## How it works

1. A party member with **Find Herbs** or **Find Minerals** active plays as usual.
2. They **move the mouse over a herb or ore icon on their minimap**. The addon reads its name through Forever's official minimap API, keeps only known herb and ore names (quest areas and player names are ignored), and sends it to the group.
3. Other members see an icon at the same place on **their own minimap**. Hovering it shows the plant name, who found it and how old the information is.
4. When the node is gathered, its icon is removed for everyone within a few seconds.
5. With proximity detection on (`/pgr near on`), the node the game picks as your soft interact target is shared at your position, without the mouse.
6. On a client without the restriction, the addon sweeps the minimap every 2 seconds by itself, without the mouse.

## Features

- Hover detection and sharing, in both directions: any gatherer in the group shares with everyone.
- Minimap button and settings window (`/pgr`): addon version, which party members use PartyGatherRadar, show or hide other players' information, sharing, herbs, ores, known spots, spawn points.
- Proximity detection without the mouse (off by default): the addon turns on the game's soft interact target and restores your original settings with `/pgr near off`. Nothing is changed in combat.
- Known spots: herbs and ore nodes seen, gathered or received are kept per map and shown as discreet icons, marked "presence not confirmed". `/pgr spots` counts them, `/pgr spots clear` removes them.
- Spawn points from QuestieDB (off by default, `/pgr spawns on`): read in game from QuestieDB if it is installed, never copied into the addon. Hidden near a reported node or a known spot, and for a kind you track yourself.
- Herb names learned automatically the first time you gather a plant missing from the built-in list.
- Adapts to the client: a blocked sweep, repeated probe failures and addon restrictions (encounters, Mythic+, PvP) are detected and reported once in chat.
- Hides "No player named '...' is currently playing" when it targets an online group member: another addon whispering a malformed name (seen with ForeverGuide). `/pgr quiet off` shows it again.
- Diagnostics for bug reports: `/pgr diag`, saved to the SavedVariables.
- French and English.

## What it does not do

- No memory reading, no external program, no automation of movement, interaction or gathering.
- Never moves the mouse for you: hovering a node is always your own action.
- Never turns tracking on by itself, and never invents a position: no reliable data, no icon.
- Does not probe the minimap in combat.

## Commands

- `/pgr` or `/pgr options`: settings window. `/pgr help`: all commands.
- `/pgr status`, `/pgr peers`, `/pgr test` (controlled test marker), `/pgr diag`.
- `/pgr spots [clear]`: known spots.
- `/pgr share|receive|minimap|button|auto|near|quiet|spawns on|off`: quick toggles (`near`: proximity detection without the mouse; `spawns`: QuestieDB spawn points).

## Known limitations

- On the live client, a node is shared only while someone hovers it on the minimap. This is Blizzard's intended restriction. Without the mouse, only the node right next to you (`/pgr near on`), known spots and QuestieDB spawn points (optional) are available.
- Checked in game with two clients: hover detection and sharing (November 8, 2026), and proximity detection (November 9, 2026: nodes first seen about 4 to 13 m away). Not checked in game yet: known spot and spawn point icons.
- Icon accuracy is about 10 to 30 m when the minimap is zoomed out.
- A known spot or a spawn point only means a node can be there: it may have been gathered, or not have spawned yet.
- Herb and ore names are matched in French and English; other client languages learn names when gathering.
- Addon messages only reach party or raid members; trial accounts cannot send addon messages on Forever.

---

# PartyGatherRadar (français)

**Partagez avec tout le groupe les herbes et minerais de votre minicarte.** Passez la souris sur l'icône d'une herbe ou d'un minerai de votre minicarte : chaque membre du groupe la voit sur sa propre minicarte.

> **Important : passez la souris dessus.** Depuis la mise à jour du client WoW Forever de novembre 2026 (build 70862), les addons ne peuvent plus lire la minicarte seuls : le jeu ne nomme une icône de la minicarte que sous le vrai curseur de la souris. Blizzard indique que c'est voulu (« Minimap is off limits ») : ce n'est pas un bogue de l'addon. **Une herbe ou un minerai n'apparaît désormais chez le groupe que quand le joueur qui le voit passe la souris sur son icône de minicarte.** Avant cette mise à jour, les ressources étaient partagées automatiquement. L'addon repère seul la restriction et passe en détection au survol.
>
> **Sans souris**, ces sources facultatives aident :
>
> - `/pgr near on` : la ressource juste à côté de vous (cible d'interaction douce du jeu, environ 4 à 13 m en pratique) est partagée, même sans pistage.
> - **Emplacements connus** : les ressources déjà vues restent sur la minicarte en icônes discrètes (« présence non confirmée »). Vous pouvez les masquer dans la fenêtre de réglages.
> - **Points d'apparition (nouveau en 0.6.0, désactivés par défaut)** : avec **QuestieDB** installé (il vient avec Questie), `/pgr spawns on` montre où chaque herbe et chaque filon peut pousser, en icônes pâles (présence non confirmée). Pas encore vérifié en jeu.
>
> Prototype expérimental pour World of Warcraft: Forever (1.60.1, interface 16001). Vos retours sont les bienvenus.

## Fonctionnement

1. Un membre du groupe active **Découverte d'herbes** ou **Découverte de gisements** et joue normalement.
2. Il **passe la souris sur l'icône d'une herbe ou d'un minerai de sa minicarte**. L'addon lit son nom avec la fonction officielle de minicarte de Forever, ne garde que les noms d'herbes et de minerais connus (zones de quête et joueurs ignorés) et l'envoie au groupe.
3. Les autres membres voient une icône au même endroit **sur leur propre minicarte**. Le survol affiche le nom de la plante, qui l'a trouvée et depuis quand.
4. Quand la ressource est récoltée, son icône est retirée chez tout le monde en quelques secondes.
5. Avec la détection de proximité (`/pgr near on`), la ressource que le jeu choisit comme cible d'interaction douce est partagée à votre position, sans souris.
6. Sur un client sans la restriction, l'addon balaie seul la minicarte toutes les 2 secondes, sans souris.

## Fonctions

- Détection au survol et partage, dans les deux sens : chaque récolteur du groupe partage avec tous.
- Bouton de minicarte et fenêtre de réglages (`/pgr`) : version, membres qui utilisent l'addon, afficher ou masquer les infos des autres joueurs, partage, herbes, minerais, emplacements connus, points d'apparition.
- Détection de proximité sans souris (désactivée par défaut) : l'addon active la cible d'interaction douce du jeu et rétablit vos réglages d'origine avec `/pgr near off`. Rien n'est changé en combat.
- Emplacements connus : herbes et filons vus, récoltés ou reçus, gardés par carte et affichés en icônes discrètes, marqués « présence non confirmée ». `/pgr spots` les compte, `/pgr spots clear` les efface.
- Points d'apparition de QuestieDB (désactivés par défaut, `/pgr spawns on`) : lus en jeu dans QuestieDB s'il est installé, jamais copiés dans l'addon. Masqués près d'une ressource signalée ou d'un emplacement connu, et pour une sorte que vous pistez vous-même.
- Noms d'herbes appris à la première récolte d'une plante absente de la liste.
- S'adapte au client : balayage bloqué, échecs répétés de la sonde et restrictions d'addons (rencontres, mode défi, JcJ) repérés et signalés une fois dans la discussion.
- Masque « Aucun joueur nommé '…' ne joue actuellement » quand il vise un membre du groupe connecté : un autre addon chuchote un nom mal formé (vu avec ForeverGuide). `/pgr quiet off` le réaffiche.
- Diagnostic pour les rapports de bogue : `/pgr diag`, sauvegardé dans les SavedVariables.
- Français et anglais.

## Ce que l'addon ne fait pas

- Aucune lecture de mémoire, aucun programme externe, aucune automatisation du déplacement, des interactions ou de la récolte.
- Ne bouge jamais la souris à votre place : survoler une ressource reste votre geste.
- N'active jamais le pistage à votre place et n'invente aucune position : sans donnée fiable, pas d'icône.
- Ne sonde pas la minicarte en combat.

## Commandes

- `/pgr` ou `/pgr options` : fenêtre de réglages. `/pgr help` : toutes les commandes.
- `/pgr status`, `/pgr peers`, `/pgr test` (marqueur de test contrôlé), `/pgr diag`.
- `/pgr spots [clear]` : emplacements connus.
- `/pgr share|receive|minimap|button|auto|near|quiet|spawns on|off` : réglages rapides (`near` : détection de proximité sans souris ; `spawns` : points d'apparition de QuestieDB).

## Limites connues

- Sur le client live, une ressource n'est partagée que pendant qu'un joueur la survole sur la minicarte. C'est la restriction voulue par Blizzard. Sans souris, seules la ressource juste à côté de vous (`/pgr near on`), les emplacements connus et les points d'apparition de QuestieDB (facultatifs) sont disponibles.
- Vérifié en jeu avec deux clients : détection au survol et partage (8 novembre 2026), détection de proximité (9 novembre 2026 : ressources vues d'abord à environ 4 à 13 m). Pas encore vérifié en jeu : icônes des emplacements connus et des points d'apparition.
- Précision des icônes d'environ 10 à 30 m quand la minicarte est dézoomée.
- Un emplacement connu ou un point d'apparition indique seulement qu'une ressource peut s'y trouver : elle a pu être récoltée, ou ne pas encore avoir poussé.
- Noms d'herbes et de minerais reconnus en français et en anglais ; dans les autres langues, les noms sont appris à la récolte.
- Les messages d'addon n'atteignent que les membres du groupe ou du raid ; les comptes d'essai ne peuvent pas en envoyer sur Forever.

MIT License. Not affiliated with or endorsed by Blizzard Entertainment.
