# eyebreak-swiftbar

A menu-bar **20-20-20 eye-break timer** for macOS, built as a [SwiftBar](https://swiftbar.app) plugin.

## What it is

If you work at a screen all day, your eyes rarely refocus — and that sustained
near-focus is a big driver of digital eye strain, dryness, and headaches. The
optometrist-recommended countermeasure is the **20-20-20 rule**: every **20
minutes**, look at something at least **20 feet** away for **20 seconds** (this
app uses a slightly longer 2-minute break by default).

**eyebreak-swiftbar** lives in your menu bar and runs that rule for you:

- A live countdown sits in the menu bar — `👀 19:12` until your next break,
  switching to `☕` while you're on one.
- When a break is due it gets your attention **twice**: a system notification
  *and* a modal "Start Break" dialog that jumps to the front of whatever you're
  doing and dismisses itself when the break ends. (A banner alone is too easy to
  swipe away and ignore — the whole point is that you actually look away.)
- You stay in control: **Take break now**, **End break now**, **Pause / Resume**,
  and **Reset** are all in the menu.
- It quietly keeps score. A **📊 Statistics** view shows how consistent you've
  actually been: total breaks, today / last 7 / last 30 days, active days,
  current and longest streak, and estimated total eye-rest time. All of it is
  computed from a plain-text log on your own machine — nothing is uploaded.

It's intentionally small: a few shell scripts driven by SwiftBar, no background
app of its own, no network access, no data collection.

## Prerequisites

You need to install **two** things before this tool:

1. **macOS.** The scripts target macOS (AppleScript notifications/dialogs). They
   run under the system `bash`/`zsh` — nothing to install there.
2. **[SwiftBar](https://swiftbar.app)** — the menu-bar host that runs the plugin.
   Install it with Homebrew:

   ```sh
   brew install --cask swiftbar
   ```

   (or download it from [swiftbar.app](https://swiftbar.app) / the
   [releases page](https://github.com/swiftbar/SwiftBar/releases)).

   On first launch SwiftBar asks you to pick a **plugin folder** — the default
   `~/SwiftBar/Plugins` is fine. It will also ask for **notification
   permission**; grant it, or break alerts won't show.

That's the whole dependency list. There is no Xcode, no runtime, and no package
to build — the tool itself is just scripts.

## Install

```sh
git clone https://github.com/Mirxomitov/eyebreak-swiftbar.git
cd eyebreak-swiftbar
./install.sh
```

Then open SwiftBar (or choose **Refresh All** from its menu) to load the plugin,
and grant it notification permission when prompted.

If your SwiftBar plugin folder isn't the default `~/SwiftBar/Plugins`:

```sh
SWIFTBAR_PLUGIN_DIR="$HOME/path/to/plugins" ./install.sh
```

The installer copies the plugin into your SwiftBar plugin folder and the shared
library plus helpers into `~/.eyebreak/`, and seeds a default config the first
time (re-running it upgrades the code but keeps your settings and history).

## How it works

| Path | Installs to | Role |
| --- | --- | --- |
| `plugin/eyebreak.1s.sh` | `~/SwiftBar/Plugins/` | The SwiftBar plugin. Runs once per second, renders the menu bar, and flips work↔break phases. |
| `lib/eyebreak-lib.sh` | `~/.eyebreak/` | Shared library: common paths, config, usage logger, state I/O, and a portable epoch formatter. Sourced by all three scripts. |
| `lib/eyebreak-ctl.sh` | `~/.eyebreak/` | Handles menu actions (break / work / pause / reset). |
| `lib/eyebreak-stats.sh` | `~/.eyebreak/` | Reads the usage log and shows the statistics (stdout or a dialog). |

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

## Notes & limitations

- macOS only (uses AppleScript for notifications and dialogs). The date math is
  written to work with both the system BSD `date` and GNU coreutils `date`, so
  the helpers behave the same whichever is first in your `PATH`.
- "Current streak" counts back from today, falling back to yesterday if you
  haven't taken a break yet today — so early in the day it shows the streak you
  are about to continue rather than 0.

## License

[MIT](LICENSE)
