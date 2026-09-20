# Ledger

A leveling analytics addon for World of Warcraft Classic Era.

Ledger records every experience gain and shows you what your current level is
actually made of: where the XP came from, how long it took, and how much of
your time went into fighting versus everything else.

## What it does

**Composition bar.** A segmented bar above the native XP bar, scaled to the
same width. Each segment is a chunk of XP, coloured by source — kills, quest
turn-ins, exploration. Rested bonus is shown as a lighter shade within each
segment. Because it shares the native bar's scale, a mismatch between the two
is immediately visible.

**Time bar.** A parallel bar showing the proportional split of the level's
time: combat versus non-combat versus dead. Non-combat is reclassified
retroactively once you've been out of combat past a configurable threshold.

**Rates.** XP per hour for the current level, with rested bonus optionally
excluded — useful when comparing farming spots, since rested skews the number
for however long it lasts.

**Hover for detail.** Both bars have tooltips with the full breakdown:
per-source totals and percentages, rested contribution, time split, and an
estimate of time to next level.

## Installation

Download the latest release and extract it into:

```
World of Warcraft/_classic_era_/Interface/AddOns/Ledger/
```

Restart the client — new addon folders are only picked up at startup.

## Commands

| Command | Description |
|---|---|
| `/ldg` | Toggle the main frame |
| `/ldg help` | List all commands |
| `/ldg bar` | Toggle the XP composition bar |
| `/ldg time` | Toggle the time breakdown bar |
| `/ldg rested` | Toggle whether rested XP counts toward rates |
| `/ldg reset` | Close the current session and start a new one |
| `/ldg check` | Reconcile recorded XP against actual XP |
| `/ldg export` | Dump the database for copying |
| `/ldg debug` | Toggle the debug panel |
| `/ldg dump` | Print current state to chat |
| `/ldg log <level>` | Set log level: off, error, info, trace |

## How it works

XP amounts always come from the delta of `UnitXP`, never from parsing chat —
the chat message is only used to determine the *source* of the gain. That
keeps totals exact even during multi-kill pulls, when chat messages and XP
updates don't arrive in lockstep.

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