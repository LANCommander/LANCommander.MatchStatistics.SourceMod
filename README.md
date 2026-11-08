# LANCommander Match Statistics for SourceMod

Reports the matches played on a Source game server to [LANCommander](https://github.com/LANCommander/LANCommander)'s
match statistics: who played, what happened (kills, damage, objectives, rounds, chat, admin
actions), and how each match ended. LANCommander builds leaderboards from these reports and links
in-game players to its users.

It works on any Source game with SourceMod 1.12 or later. Game modules add each game's own events;
see [Supported games](#supported-games). Integrations add what popular plugins know: Get5,
PugSetup, Retakes, SourceBans++/SourceComms, Left4DHooks and map votes.

Delivery is handled by the [LANCommander Interposer](https://github.com/LANCommander/LANCommander.Interposer),
which is built into the extension. It batches events and retries while LANCommander can't be
reached. It also keeps anything unsent on disk, so a crash, restart or network outage loses
nothing.

## How it fits together

| Part | File | What it does |
|---|---|---|
| Extension | `extensions/lancommander.ext.so` / `.dll` | The Interposer, with SourcePawn natives for its match API and `LCPayload`, a JSON builder. Built with no game SDK, so one binary per OS and architecture serves every game. |
| Core plugin | `plugins/lancommander_stats.smx` | Owns the cvars and the match lifecycle: one LANCommander match per map. Records players and the events every Source game shares, works out the standings, and offers an API to the other plugins. |
| Game modules | `plugins/disabled/lancommander_stats_<game>.smx` | Each game's objectives and rules. The core plugin loads the one for the running game, so the full set can be installed everywhere. |
| Integrations | `plugins/lancommander_stats_<plugin>.smx` | What other plugins know. Each one does nothing unless its plugin is loaded. |
| Event map | `configs/lancommander_events.cfg` | Records any other game's events with no code. |

## Installing

1. Copy the release's `addons/` folder into the game directory (`cstrike/`, `tf/`, `dod/`, ...).
   Leave the game modules in `plugins/disabled/`: the core plugin loads the right one.
   - 32-bit servers load `addons/sourcemod/extensions/lancommander.ext.so` (or `.dll`).
   - 64-bit servers load the copy in `extensions/x64/`.
2. In LANCommander, open **Profile → Access Tokens** and create a token with **Report matches**
   (the `matches:report` scope). Create it under an administrator account if the reports should
   count as authoritative. Otherwise LANCommander trusts them only as far as it trusts that user.
3. Start the server once to write `cfg/sourcemod/lancommander.cfg`, then set:

   ```
   lc_server_url "http://lancommander.lan:1337"
   lc_token      "lc_pat_..."
   lc_game_id    "6f1e2c64-0d47-4b8e-9a43-3a1c2bde0f11"   // the game's id in LANCommander
   ```

4. Change map or restart. `sm_lc_status` shows the match being recorded and how delivery is
   going.

**Linux servers can only use `http://`.** The Interposer's Linux HTTP client has no TLS, and an
`https://` URL is refused with a line in its log. LANCommander on a LAN is normally plain HTTP.

**Linux needs glibc 2.36 or newer** (Debian 12, Ubuntu 22.10 or later, and LANCommander's own game
server images). That comes from the build environment the Interposer's Linux build uses.

## Configuration (`cfg/sourcemod/lancommander.cfg`)

### Where reports go

| Cvar | Default | |
|---|---|---|
| `lc_enabled` | `1` | `0` records nothing. |
| `lc_server_url` | | The LANCommander server. |
| `lc_token` | | A personal access token with the `matches:report` scope. `%VARIABLE%` reads an environment variable, so the token can be kept out of the file. The cvar is protected: its value is never shown to clients. |
| `lc_game_id` | | The game's id in LANCommander (a GUID). |
| `lc_server_id` | | This server's id in LANCommander, if LANCommander manages it. |
| `lc_reporter_name` | hostname | How the server is named in LANCommander. |
| `lc_flush_interval` | `2000` | Milliseconds between batches of events. |

The settings are handed to the extension when the configs run, and again whenever one changes.
They apply to the next match started.

### What a match is

| Cvar | Default | |
|---|---|---|
| `lc_min_players` | `1` | Human players needed before a match opens on a new map. Bots don't count. |
| `lc_mode` | | The mode reported. Empty lets the game module decide (`defusal`, `payload`, `versus`, ...). |
| `lc_settings_cvars` | `mp_timelimit,mp_fraglimit,...` | Cvars kept with each match as its settings. |

A match starts when the map's configs have run and enough players are in. It ends at game over:
the final scoreboard in CS, `teamplay_game_over` in TF2, the finale or the safe room in L4D. If
the game has no game over of its own, it ends when the map changes. If the server shuts down
mid-match, the match is left open and LANCommander marks it abandoned. A plugin reload on the
same map continues the same match.

### What is recorded

| Cvar | Default | |
|---|---|---|
| `lc_record_bots` | `1` | Bots as players (`bot:<name>`). |
| `lc_record_warmup` | `0` | Events during warmup (CS:GO, Get5, PugSetup), marked `warmup: true`. |
| `lc_record_damage` | `0` | Every hit as an event. Damage totals are kept either way. |
| `lc_record_spawns` | `1` | Spawns. |
| `lc_record_chat` | `0` | Chat messages. |
| `lc_record_positions` | `1` | Player positions in kill, spawn and objective events. |
| `lc_record_weapon_fire` | `0` | Every shot as an event. Shot totals are kept either way. |
| `lc_attach_demos` | `1` | Uploads SourceTV demos recorded with `tv_record` to the match they cover. |
| `lc_events_include` | | Records only these event types. Comma-separated, `*` as a wildcard. Empty records every type. |
| `lc_events_exclude` | | Never records these event types. Same format, applied after `lc_events_include`. |

**Filtering events.** The two `lc_events_*` cvars choose which events are recorded, by event type.
The event types are listed under [What is recorded](#what-is-recorded) and in the modules.

- They apply to every event, whether it comes from the core plugin, a game module, an integration
  or the event map.
- **They leave statistics, standings and players alone.** With `kill` excluded, `kills`, `deaths`
  and `headshots` are still totalled and the results still worked out; only the individual kill
  events are left out.
- They take effect immediately when changed.

```
lc_events_exclude "spawn,team_change,purchase,grenade_*"   // a lighter record
lc_events_include "kill,round_*,bomb_*,game_end"            // only these
```

The `lc_record_*` switches above come first: an event they turn off, such as `damage` or `chat`,
is not recorded whatever the filter says.

## Admin commands

| Command | Access | |
|---|---|---|
| `sm_lc_status` | generic | The match being recorded, where it is sent, what is still waiting, and the last delivery problem. |
| `sm_lc_flush` | rcon | Sends what is waiting now. Blocks the server for up to 5 s. |
| `sm_lc_startmatch [mode]` | changemap | Starts a new match now, ignoring `lc_min_players`. |
| `sm_lc_endmatch [reason]` | changemap | Ends the match. No new match starts on this map unless one is started by hand. |
| `sm_lc_abandonmatch` | changemap | Ends the match as abandoned, so its results don't count. |

## Players

A player key names a player to LANCommander for the whole match:

- **`steam:STEAM_0:1:123`**: a Steam account. CS:GO's `STEAM_1` is normalised to `STEAM_0`.
- **`bot:<name>`**: a bot.
- **`name:<name>`**: a player with no Steam id. This is the usual case at a LAN party with `sv_lan 1`.

LANCommander links these keys to its users.

## What is recorded

**Every game.** Events and per-player statistics (`kills`, `deaths`, `assists`, `headshots`,
`suicides`, `teamkills`, `damage_dealt`, `damage_taken`, `team_damage`, `hits`, `shots`, `score`,
`time_played_ms`):

| Event | Notes |
|---|---|
| `kill` | Weapon, headshot, assister, positions and distance. Suicides and teamkills are flagged. |
| `damage` | Optional (`lc_record_damage`). |
| `spawn` | |
| `team_change`, `name_change` | |
| `disconnect` | With the reason. |
| `round_start`, `round_end` | Where the game has them, with the winner and reason. Every event carries the round number. |
| `chat` | Optional (`lc_record_chat`). |
| `admin_ban` | |
| `weapon_fire` | Optional (`lc_record_weapon_fire`). |

At the end, team games rank the teams by score, and each player takes their team's place:
`Finished` for the winners, `Defeated` for the rest. Free-for-all games rank players by frags.
A player who left before the end is `DidNotFinish`.

Not every game reports everything. What the shared events carry differs from game to game, so
some statistics exist only in some games:

- **Damage amounts:** CS:S, DoD:S, FoF, L4D 1/2, TF2, and PVKII and MCV (through their own
  events). The other games report hits only.
- **Shots:** CS:S, L4D 1/2, MCV, DoD:S, FoF.
- **Headshots:** CS:S, FoF, L4D 1/2, MCV, PVKII, TF2 (backstab and headshot kills).
- **Assists:** FoF, MCV, PVKII, TF2.

## Supported games

The game modules were written against each game's own event definitions (`modevents.res` and the
shared `gameevents.res`/`serverevents.res`), read from the dedicated server files.
`tests/tools/check_events.py` checks every event and field the modules read against those
definitions. The games themselves have not all been run with the plugin; see the last column.

| Game | Server OS | SourceMod gamedata | Module adds | Run with the plugin |
|---|---|---|---|---|
| **Counter-Strike: Source** | Linux 32/64-bit, Windows | yes | Bomb plants, defusals and explosions (with the site), hostages, the VIP, purchases and money spent, flashes (attributed to the thrower), grenades, MVPs, dominations and revenges, fall damage, round end reasons and scores, warmup, the CS:GO mode, team names from `mp_teamname_1/2` | yes (Linux 32-bit) |
| **Team Fortress 2** | Linux 32/64-bit, Windows | yes | Captures and blocks, flags, buildings, teleports, ÜberCharges and drops, healing, dominations, revenges, backstabs, headshots, crits, classes, round wins and stalemates, MvM waves. Dead Ringer feigns are not counted. | no |
| **Day of Defeat: Source** | Linux 32/64-bit, Windows | yes | Flag captures and blocks, bomb plants, defusals and explosions, planters and defusers killed, classes, shots, dominations and revenges, warmup, round wins, the reason the game ended | no |
| **Left 4 Dead** and **Left 4 Dead 2** | Linux 32-bit, Windows | yes | Special infected attacks, tanks and witches (crowns too), incapacitations, revives, heals, defibs, pills and adrenaline, closet rescues, friendly fire, gas cans (scavenge), common infected totals, awards, the safe room, the finale, the mode and difficulty | no |
| **Pirates, Vikings and Knights II** | Linux 32/64-bit, Windows | yes | Backstabs, crits, combos, specials, nemesis and revenge, NPC and building kills, damage amounts, classes, points, chests, flags, the grail, territory and payload, team wins at the end | no |
| **Fistful of Frags** | Linux 32-bit, Windows | yes | Penetration kills, shots, round winners, scores and MVPs, hat shots, chain reactions, the Unforgiven, dynamite, course completions, team objectives | no |
| **Double Action: Boogaloo** | **Windows only** | **no** | Brawl and grenade kills, characters, and the 26 stunts it reports (dive punches, sky punches, ...) | no |
| **Half-Life 2: Deathmatch** | Linux 32/64-bit, Windows | yes | The mode (deathmatch or teamplay); the rest is the shared events | no |
| **Dark Messiah of Might and Magic** | **Windows only** | yes | Classes, capture-the-flag, end-of-map tickets, campaign progress, Colliseum duels | no |
| **Empires** | Linux 32-bit, Windows | yes | Points captured and neutralised, commander elections, research, vehicles bought and lost, revives, score points, the round winner | no |
| **Lambda Wars** | **Windows only** | **no** | Control point fortification, classes. Lambda Wars reports nothing else of its RTS play as game events. | no; **whether SourceMod runs on it is unconfirmed** |
| **Military Conflict: Vietnam** | Linux, Windows (64-bit) | yes | Kill details (penetration, backblast, kill distance, wipes, dominations), damage amounts (from its `character_hurt`), bomb plants and defusals, grenades, MVPs, Conquest flag captures, CTF and demolition actions, airstrike calls | no |
| **Insurgency / Day of Infamy** | Linux, Windows | yes | Point captures and neutralisations, objectives destroyed (from memory; not checked against their files) | no |

**Windows only** means the game ships its dedicated server for Windows alone (`server.dll`). The
Windows build of the extension is the one to use there.

For DAB and Lambda Wars, SourceMod has no gamedata. Its core and these plugins need none: they use
game events, team netprops and player positions. Plugins that need gamedata, such as SDK Tools'
game-specific functions, may not work there.

Lambda Wars runs on the Alien Swarm engine branch. Metamod:Source and SourceMod are not known to
have been run on it.

The modes come from the map prefix (`ctf`, `bt`, `tw`, `tp`, ...) unless a module or `lc_mode`
names one.

| Integration | Adds |
|---|---|
| **Get5** | One match per series map, starting when Get5 goes live, identified by Get5's server and match ids and the map number. Keeps the series metadata, pauses and backup restores. |
| **PugSetup** | The match starts when the PUG goes live and ends when it's over, or is abandoned if an admin force-ends it. |
| **Retakes** | The mode, and each retake's site and winner. |
| **SourceBans++ / SourceComms** | Mutes, gags and silences (and their removal), and player reports. SB++ bans arrive as `admin_ban` through SourceMod. |
| **Left4DHooks** | When the survivors leave the safe area. |
| **Map votes** | The next map, however it was decided, and MapChooser Extended's vote result. |

Other games are covered by the event map, `configs/lancommander_events.cfg`. The file documents
its format. It ships with No More Room in Hell's events, mapped as NMRiH plugins name them.

## Writing your own module

`scripting/include/lancommander_stats.inc` is the core plugin's API:

- record events with clients as actors and subjects
- add statistics and set results
- rename teams
- mark warmup
- hold the automatic start until play is live, then start the match yourself
- change any event before it is sent (`LCStats_OnEvent`)

The game modules in `scripting/modules/` are worked examples. `scripting/include/lancommander.inc`
is the extension's lower-level API, one native per Interposer function.

## Where things are kept

The Interposer works from `.interposer/` next to the extension
(`addons/sourcemod/extensions/.interposer/`, or `extensions/x64/.interposer/`):

- `Logs/`: a session log per server start. Add `Logging: { Matches: true }` to
  `.interposer/Config.yml` to log every report.
- `Matches/`: reports not yet delivered. They are sent on the next start once the cvars are set,
  and removed once LANCommander has them.

## Building

The extension builds with CMake and vcpkg against the SourceMod SDK and the Interposer, both git
submodules:

```bash
git submodule update --init --recursive
export VCPKG_ROOT=/path/to/vcpkg

# Windows (Visual Studio 2022 or later, v143 toolset)
cmake --preset windows-x64 && cmake --build --preset windows-x64-release
cmake --preset windows-x86 && cmake --build --preset windows-x86-release
```

Linux builds run inside the Interposer's build image (Debian 12, x64 and x86 multilib):

```bash
docker build -f external/LANCommander.Interposer/docker/build.Dockerfile -t lancommander-interposer-build external/LANCommander.Interposer/docker
docker run --rm -v "$PWD:/src" -w /src lancommander-interposer-build sh -c '
  cmake --preset linux-x86 && cmake --build --preset linux-x86-release &&
  cmake --preset linux-x64 && cmake --build --preset linux-x64-release'
```

To build against a working copy of the Interposer instead of the submodule, add
`-DLANCOMMANDER_INTERPOSER_DIR=/path/to/LANCommander.Interposer` to the configure step.

`ctest --preset <preset>` runs the extension's unit tests. Compile the plugins with SourceMod
1.12's compiler, with warnings as errors:

```bash
SPCOMP=/path/to/sourcemod/scripting/spcomp scripting/compile.sh
```

**Checking modules against the games' events.** `tests/tools/extract_gameinfo.py <server-dir>
<out-dir>` copies a dedicated server's event definitions out, from loose files and VPKs, and lists
its server binaries. `tests/tools/fetch_all.sh name:appid:platform ...` does that for servers it
downloads with SteamCMD in Docker, and deletes each download afterwards. With the definitions in
`out/gameinfo/<game>/`, `python -I tests/tools/check_events.py` checks every event and field the
modules read. Valve's and the mods' files are not committed; regenerate them from a server install
or a client install of the game.

`tests/e2e/` has the end-to-end tools:

- `fake_lancommander.py`: a stand-in LANCommander that checks and logs every request.
- `summarize.py`: reports on what the stand-in received.
- `rcon.py`: drives the server.

## Licence

GPLv3, as SourceMod requires of its plugins and extensions. See `LICENSE`.
