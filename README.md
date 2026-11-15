# DingCalc

A **WoW Forever** addon that tells you how many **kills** and **quests** you need to reach the next level, live, in game. It shows the same tables as Wowhead's *WoW Forever experience calculator*, worked out for your current level and XP.

## Features

- **Window** (`/ding`): your XP to next level, with an XP bar and rested XP. It shows:
  - a **kills table**: for mob levels from your level −5 to +4, the XP per kill and kills needed, for normal and elite mobs;
  - a **quests table**: typical XP per quest by quest level (with the penalty once you are 6+ levels above the quest) and how many quests you need;
  - your **quest log**: total XP of the quests in your log, and the share of what you need;
  - your **target**: kills to ding on the mob you are targeting.
- **Tooltip**: a "Kills to ding: N" line when you hover an enemy mob.
- **Rested XP** is counted: kills give double XP until the pool runs out.
- **Well-Rested (+3%)** and **Well Fed (+5% kills)** checkboxes.
- **Learns quest XP** from your own turn-ins. Quest levels with no data yet show an estimate, marked `~`.
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

You can drag the window to move it. Its position and settings are saved per account (`DingCalcDB`).

## How XP is computed

It uses the Classic XP rules, the same as Wowhead's Forever calculator:

- **Mob XP**: `level × 5 + 45` for a same-level mob, +5% per level above you (capped at +4), reduced for lower mobs, and 0 for gray mobs. Elites give double XP.
- **Quest XP**: 80% / 60% / 40% / 20% / 10% of full XP once you are 6 / 7 / 8 / 9 / 10+ levels above the quest.
- **Typical quest XP** comes from Wowhead's table for levels 5–14. Other levels come from your own turn-ins (averaged), or are scaled from the nearest known level.

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

## License

[MIT](LICENSE)
