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
- When a break is due it puts up a **full-screen blocker** on every display: the
  primary screen shows a live countdown and a rotating quote, the others go
  solid black so a second monitor can't be used to work through the break. A
  system notification fires alongside it. If the blocker is turned off (or the
  Swift helper isn't installed) it falls back to a modal "Start Break" dialog.
- Need to bail out of a break early? Press **⌥⇧⎋** (Option+Shift+Escape) to
  dismiss the blocker immediately — deliberately awkward so you don't do it by
  reflex.
- You stay in control: **Take break now**, **End break now**, **Pause / Resume**,
  and **Reset** are all in the menu. A **Settings** submenu toggles the
  full-screen blocker and **Launch at login**, and opens the config and quotes
  files for editing.
- It quietly keeps score. A **📊 Statistics** view shows how consistent you've
  actually been: total breaks, today / last 7 / last 30 days, active days,
  current and longest streak, and estimated total eye-rest time. All of it is
  computed from a plain-text log on your own machine — nothing is uploaded.

It's intentionally small: a few shell scripts driven by SwiftBar plus one tiny
Swift helper that only runs during a break, no background app of its own, no
network access, no data collection.

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

The scripts themselves need nothing to build. The **full-screen blocker** is one
small Swift file compiled at install time, so to get it you also need a Swift
toolchain — **Xcode or the Command Line Tools** (`xcode-select --install`). It's
optional: without `swiftc` the installer skips the blocker and the break falls
back to the notification + dialog.

## Install

### With Homebrew (this repo is its own tap)

```sh
brew install --HEAD mirxomitov/eyebreak-swiftbar/eyebreak-swiftbar
eyebreak-swiftbar          # deploy the plugin + helpers into place
```

(Once a tagged release is published, `brew tap mirxomitov/eyebreak-swiftbar
<repo-url>` then `brew install eyebreak-swiftbar` works without `--HEAD`.) The
formula pulls in the SwiftBar cask, compiles the blocker, and installs an
`eyebreak-swiftbar` command that copies everything into `~/.eyebreak` and your
SwiftBar plugin folder.

### From source

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
| `lib/eyebreak-lib.sh` | `~/.eyebreak/` | Shared library: common paths, config, usage logger, state I/O, portable epoch formatter, quote loader, blocker launcher, and the settings toggles. Sourced by all three scripts. |
| `lib/eyebreak-ctl.sh` | `~/.eyebreak/` | Handles menu actions (break / work / pause / reset, plus the blocker and launch-at-login toggles). |
| `lib/eyebreak-stats.sh` | `~/.eyebreak/` | Reads the usage log and shows the statistics (stdout or a dialog). |
| `blocker/blocker.swift` | `~/.eyebreak/eyebreak-blocker` | The full-screen break blocker, compiled at install time. Blacks out every display, shows the countdown + quote, and handles the ⌥⇧⎋ skip. |
| `assets/quotes.txt` | `~/.eyebreak/quotes.txt` | The pool of break quotes, one per line. Edit freely. |

Runtime files live in `~/.eyebreak/`:

- `config` — your `WORK_MINUTES` / `BREAK_MINUTES` / `SHOW_BLOCKER`.
- `quotes.txt` — the quote pool (seeded once; your edits survive upgrades).
- `state` — current phase and countdown (managed automatically).
- `stats.csv` — append-only usage log: `iso,epoch,event` where `event` is
  `break_start`, `break_end`, or `reset`. Every statistic is derived from this
  file. It never leaves your machine.

### Configuration

Edit `~/.eyebreak/config` (or use the **Settings** submenu):

```sh
WORK_MINUTES=20   # minutes of work between breaks
BREAK_MINUTES=2   # minutes per break
SHOW_BLOCKER=1    # 1 = full-screen blocker during breaks, 0 = notify only
```

Use whole numbers. Changes apply on the next tick.

### Launch at login

The **Settings ▸ Launch at login** toggle writes a per-user LaunchAgent
(`~/Library/LaunchAgents/com.eyebreak.swiftbar.login.plist`) that starts SwiftBar
at login, so the timer is always running. Toggling it off removes the agent.

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
