# eyebreak-swiftbar

A menu-bar **20-20-20 eye-break timer** for macOS, built as a [SwiftBar](https://swiftbar.app) plugin.

Every 20 minutes it reminds you to look at something at least 20 feet away for
2 minutes — the [20-20-20 rule](https://www.aao.org/eye-health/tips-prevention/computer-usage)
for reducing digital eye strain. It nags you with both a notification **and** a
click-to-dismiss dialog (a banner alone is too easy to miss), and it keeps a
private usage log so you can see how consistently you actually take your breaks.

## Features

- **Menu-bar countdown** — live `👀 mm:ss` until the next break, `☕` during one.
- **Two-layer reminder** — a SwiftBar notification plus a modal "Start Break"
  dialog that comes to the front and self-dismisses when the break ends.
- **Manual controls** — Take break now, End break now, Pause/Resume, Reset.
- **Usage statistics** — total breaks, today / last 7 / last 30 days, active
  days, current & longest streak, and estimated eye-rest time, from a "📊
  Statistics…" menu item. Data lives in an append-only CSV you own.
- **Configurable** — work/break durations via `~/.eyebreak/config`.

## Install

Requires [SwiftBar](https://swiftbar.app) (`brew install --cask swiftbar`).

```sh
git clone https://github.com/Mirxomitov/eyebreak-swiftbar.git
cd eyebreak-swiftbar
./install.sh
```

Then open SwiftBar (or **Refresh All** from its menu) and grant it notification
permission when prompted.

If your SwiftBar plugin folder isn't the default `~/SwiftBar/Plugins`:

```sh
SWIFTBAR_PLUGIN_DIR="$HOME/path/to/plugins" ./install.sh
```

## How it works

| Path | Role |
| --- | --- |
| `plugin/eyebreak.1s.sh` | The SwiftBar plugin. Runs once per second, renders the menu bar, and flips work↔break phases. Installs to `~/SwiftBar/Plugins/`. |
| `lib/eyebreak-ctl.sh` | Handles menu actions (break / work / pause / reset). Installs to `~/.eyebreak/`. |
| `lib/eyebreak-stats.sh` | Reads the usage log and shows the statistics (stdout or a dialog). Installs to `~/.eyebreak/`. |

Runtime files live in `~/.eyebreak/`:

- `config` — your `WORK_MINUTES` / `BREAK_MINUTES`.
- `state` — current phase and countdown (managed automatically).
- `stats.csv` — append-only usage log: `iso,epoch,event` where `event` is
  `break_start`, `break_end`, or `reset`. Every statistic is derived from this
  file. It never leaves your machine.

### Configuration

Edit `~/.eyebreak/config`:

```sh
WORK_MINUTES=20   # minutes of work between breaks
BREAK_MINUTES=2   # minutes per break
```

Use whole numbers. Changes apply on the next tick.

### Viewing stats from the terminal

```sh
~/.eyebreak/eyebreak-stats.sh          # print the report
~/.eyebreak/eyebreak-stats.sh --csv    # print the log path and reveal it in Finder
```

## Requirements & limitations

- **macOS only.** The scripts rely on BSD `date` (`-v`, `-j -f`, `-r`). If you
  have GNU coreutils' `date` earlier in your `PATH` (e.g. Homebrew `gnubin`),
  the date math will misbehave — SwiftBar itself runs with the system `PATH`,
  so this only affects running the helpers by hand in such a shell.
- Week/month buckets are computed from fixed 86400-second offsets, so a break
  logged within an hour of a DST transition can land in an adjacent bucket.
- "Current streak" counts back from today, falling back to yesterday if you
  haven't taken a break yet today, so it can show a streak that ended yesterday.

## License

[MIT](LICENSE)
