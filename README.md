<p align="center"><img src="media/logo-256.png" alt="DingCalc logo" width="160"></p>

# DingCalc

A **WoW Forever** addon that tells you how many **kills** and **quests** you need to reach the next level, live, in game. It shows the same tables as Wowhead's *WoW Forever experience calculator*, worked out for your current level and XP.

## Features

- **Window** (`/ding`): your XP to next level, with an XP bar and rested XP. It shows:
  - a **kills table** with one row per difficulty color, **green**, **yellow** and **orange** (red mobs are left out): the mob levels in that color, XP per kill and kills needed, for normal and elite mobs. Values are shown as a range, from the lowest to the highest level of the color;
  - a **quests table**, by the same green / yellow / orange colors: the quest levels in that color, XP per quest (with the penalty once you are 6+ levels above the quest) and how many quests you need. Normal, Elite and Dungeon quests each have their own table, switched with a button next to the title;
  - your **quest log**: total XP of the quests in your log, and the share of what you need;
  - your **target**: kills to ding on the mob you are targeting;
  - your **XP per hour**, live, for this **session**, the **last hour**, **this level** and this **character**, with the time played for each, and an **ETA to ding** at your current pace.
- **Tooltip**: a "Kills to ding: N" line when you hover an enemy mob.
- **Rested XP** is counted: kills give double XP until the pool runs out.
- **Well-Rested (+3%)** and **Well Fed (+5% kills)** checkboxes, saved per character.
- **Learns from your journey**: every quest you turn in is recorded, and its XP feeds the averages. The data is shared by all characters on your account, so each alt starts with what your other characters learned. Levels with no data yet show an estimate, marked `~`.
- Mob levels are colored by difficulty (red, orange, yellow, green, gray).

## Install

1. Download this repo (**Code → Download ZIP**, or `git clone`) and put it in the **Interface/AddOns** folder of your **WoW Forever** install.
2. The folder must be named exactly `DingCalc`. A ZIP download unpacks as `DingCalc-main`, so rename it.
3. Restart the game, or `/reload`, and check that DingCalc is enabled in the AddOns list.

## Commands

| Command | Effect |
| --- | --- |
| `/ding` or `/dingcalc` | Show or hide the window |
| `/ding tooltip` | Turn the tooltip line on or off |
| `/ding reset` | Move the window back to the center of the screen |
| `/ding quests` | List the quests in your log and the type (normal / elite / dungeon) DingCalc detects for each |
| `/ding stats` | For the quest type shown in the window, list each quest level you have data for: turn-ins, median, average and range |
| `/ding rate` | XP per hour of this character level by level, then of every character on the account |
| `/ding resetrate` | Forget this character's XP rate data |
| `/ding resetquests` | Forget the learned quest XP (for all characters) |

You can drag the window to move it.

What is saved where:

- **Per account** (`DingCalcDB`): learned quest XP, window position, tooltip on/off. Quest XP depends only on the quest, so every character adds to and uses the same table.
- **Per character** (`DingCalcCharDB`): the Well-Rested and Well Fed checkboxes, and the XP rate data (session, last hour, per level, total).
- The account file also keeps a one-line summary per character (level, XP/h, time played) for `/ding rate`.

## How XP per hour is measured

- Every XP gain counts (kills, quests, exploration), including across a level-up.
- Only **play time** counts: logged in, not AFK, below level 60. So it is XP per hour of play, not per hour of the clock.
- **Session**: since you logged in. A logout shorter than 5 minutes (a `/reload`) keeps the session.
- **Last hour**: the last 60 minutes of the clock. Time logged out or AFK in that hour doesn't count against you.
- **This level** and **Character**: everything since the addon started tracking on this character.
- A rate shows once it has a minute of data. The ding ETA uses the last-hour pace, or the next one that has data.

## How XP is computed

It uses the Classic XP rules, the same as Wowhead's Forever calculator:

- **Mob XP**: `level × 5 + 45` for a same-level mob, +5% per level above you (capped at +4), reduced for lower mobs, and 0 for gray mobs. Elites give double XP.
- **Quest XP**: 80% / 60% / 40% / 20% / 10% of full XP once you are 6 / 7 / 8 / 9 / 10+ levels above the quest.
- **Quest XP per level**: built from the XP of every quest you turn in during your journey, by quest type and level, and shared by all characters on your account. The value shown is the **median** (P50) of your turn-ins, not the average: quest XP comes in a few fixed amounts and most quests give the normal one, so the median ignores the small quest-chain steps (talk to X, deliver a letter) that give only a few hundred XP, as long as they are fewer than half. Until a level has 3 turn-ins, normal quests of levels 5–14 use Wowhead's values. Levels with no data are scaled from the nearest known level (`~`).
- **Quest types**: each quest's type comes from its quest tag (Elite, Dungeon; Raid counts as Dungeon). If the client gives no tag but the quest has a suggested group size, it counts as Elite. Elite and Dungeon have no built-in values, so their table stays empty (`-`) until you turn in one of that type; after that, other levels are scaled from it (`~`).
- **Learning**: each turn-in is converted back to full XP (undoing the level penalty and Well-Rested) before it is averaged, so turn-ins at any level count the same. Turn-ins made 8+ levels above the quest (40% XP or less) are ignored, because rounding makes them inaccurate.

## Releases

Releases follow CurseForge's three release types, read from the version / tag name (the same rule the BigWigs packager uses):

| Version in `DingCalc.toc` | Tag | CurseForge type |
| --- | --- | --- |
| `1.1.0-alpha.1` | `v1.1.0-alpha.1` | Alpha |
| `1.0.0-beta.1` | `v1.0.0-beta.1` | Beta |
| `1.0.0` | `v1.0.0` | Release |

**To cut a release, bump `## Version:` in `DingCalc.toc` and merge to `main`.** No manual tag is needed: `.github/workflows/release.yml` runs on every push to `main`, and when the version has no tag yet it:

1. runs the Lua syntax check;
2. checks the version format and builds `DingCalc-<version>.zip` (a `DingCalc/` folder with the `.toc`, the Lua file, README and LICENSE) with `.github/scripts/package.sh`, which you can also run locally;
3. creates the tag `v<version>` on that commit;
4. creates a GitHub release with the zip and a changelog built from the commits since the previous tag. Alpha and beta releases are marked as pre-releases;
5. uploads the zip to CurseForge with the matching release type, but only once these are set under *Settings → Secrets and variables → Actions*:
   - secret `CF_API_KEY`: a CurseForge API token (legacy.curseforge.com → Account → API tokens);
   - variable `CF_PROJECT_ID`: the project's numeric id;
   - variable `CF_GAME_VERSION_IDS`: comma-separated CurseForge game version ids for the Forever client.

   Without `CF_PROJECT_ID`, that step is skipped and only the GitHub release is made.

Pushes that don't change the version release nothing. Pushing a `v*` tag by hand also works.

## Logo

`media/logo.svg` is the source of the logo, with PNG exports at 512, 256 and 64 px; use `logo-512.png` as the CurseForge project logo. It is original artwork. The lettering is [Cinzel](https://github.com/NDISCOVER/Cinzel) (SIL Open Font License), converted to outlines. `media/make_logo.py` regenerates the SVG. The `media/` folder is not included in the release zip.

In the game's AddOns list, the `.toc` uses a game icon (`## IconTexture: Interface\Icons\INV_Misc_PocketWatch_01`), so no Blizzard file is copied into the addon. Clients without `IconTexture` support ignore the line.

## License

[MIT](LICENSE)
