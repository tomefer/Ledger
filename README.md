# Ledger

A leveling analytics addon for World of Warcraft Classic Era and the WoW
Forever beta.

Ledger records every experience gain and shows you what your current level is
actually made of: where the XP came from, what you were doing while you earned
it, and how fast it is coming in.

## What it does

**Composition bar.** A segmented bar that takes the place of the native XP bar
(same position and size; only the native bar's fill is hidden, so the rest of
the Blizzard UI is untouched). Each segment is a chunk of XP, coloured by
source: kills, quest turn-ins, exploration. Rested bonus is shown as a lighter
shade within each segment. `/ldg native` gives the native bar back.

**Time bar.** A thin bar above it showing how the level's time splits between
combat, non-combat, travel and dead. It is a sampler, not a stopwatch: once a
second the addon looks at what the player is doing and adds one to exactly one
of those four counters, so the bar is always shown as **percentages of
samples**, never as durations.

**Rates.** An XP-per-hour number above the bars. Hover it for two figures:

- **This session:** the XP Ledger recorded in the current session divided by
  the session's elapsed time. Respects `/ldg rested`.
- **This level:** the game's own XP for the level divided by the level's played
  time (from the server's `/played` reply). It always includes rested XP,
  because the game's value cannot be split, and ignores `/ldg rested`.

Either shows a dash until it has at least a minute of data.

**Hover for detail.** Hovering the bars gives one tooltip: XP by source, the
rested contribution, and the activity split (percentages of samples) for the
level and for the current session.

## Installation

Copy the `Ledger/` folder from this repository into the client's AddOns folder:

```
World of Warcraft/_classic_era_/Interface/AddOns/Ledger/    (Classic Era)
World of Warcraft/_classic_beta_/Interface/AddOns/Ledger/   (WoW Forever beta)
```

The same package serves both clients (`## Interface: 11509, 16001`). Restart
the client the first time: new addon folders are only picked up at startup.

If you have the repository checked out, `./deploy.sh [classic_era|forever]`
does the copy for you; set `LEDGER_WOW_PATH` to the WoW install root (the
folder that contains `_classic_era_` / `_classic_beta_`).

**Beta note:** the WoW Forever beta ignores SavedVariables files that pre-date
the client's launch. That is client behaviour, not something the addon can fix:
on the beta your data lives for a single client session.

## Commands

`/ldg` (alias `/ledger`). Unknown subcommands print the help list.

| Command | Description |
|---|---|
| `/ldg` | Toggle the main panel |
| `/ldg help` | List all commands |
| `/ldg bar` | Show or hide the XP composition bar |
| `/ldg native` | Toggle the composition bar replacing the native XP bar |
| `/ldg time` | Show or hide the activity (time) bar |
| `/ldg rate` | Show or hide the XP/hour number |
| `/ldg rested` | Toggle whether rested XP counts in "This session" XP/hour and in the totals stored when a level closes ("This level" always includes it) |
| `/ldg reset` | Close the current session and start a new one |
| `/ldg wipe confirm` | Delete **all** saved sessions and levels for this character (irreversible) |
| `/ldg check` | Reconcile recorded XP against the real value |
| `/ldg export` | Dump the character's data (JSON/CSV) for copying |
| `/ldg debug` | Toggle the debug panel |
| `/ldg dump` | Print current state to chat |
| `/ldg log <level>` | Set log level: off, error, info, trace (`log show` dumps the buffer, `log chat` toggles the chat echo) |
| `/ldg strings` | Print the XP global strings in use, with their literal value in this client |
| `/ldg probe` | Print a compatibility snapshot of this client build |

## How it works

XP amounts always come from the delta of `UnitXP`, never from parsing chat: the
chat message is only used to determine the *source* of the gain. That keeps
totals exact even during multi-kill pulls, when chat messages and XP updates
don't arrive in lockstep.

Each number on screen has exactly one source: the XP bar and the session rate
come from Ledger's own record, the level rate from the game's API, and the time
bar from the per-second sampling. They are never mixed inside one metric.

Events are stored in a flat numeric array rather than a table per event, to
keep SavedVariables small over thousands of gains per level. Raw events are
kept for the current level; completed levels store aggregates and a
downsampled per-minute curve.

## Contributing

Issues and pull requests are welcome.

The codebase is split in two layers, and this split is load-bearing:

- `core/` — pure logic. No WoW API whatsoever. Time and state are passed in as
  parameters. Everything here runs and is tested outside the game.
- `ui/` — frames and event registration. Thin, no logic.

Run the tests with [busted](https://lunarmodules.github.io/busted/):

```bash
busted
```

Pull requests should keep the tests green and add coverage for new logic in
`core/`. Lua 5.1 only — no `goto`, no native bitwise operators, no integer
division. No external libraries.

## License

MIT. See [LICENSE](LICENSE).
