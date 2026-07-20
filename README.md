# Eyebreak

A native macOS menu-bar app that helps you follow the **20-20-20 rule** to prevent
digital eye strain: every **20 minutes**, look at something **20 feet** away for
**20 seconds**.

## Features

- **Menu-bar timer** — a live countdown sits in your menu bar (`👀 19:12` until
  the next break, `☕` while you're on one).
- **Full-screen break blocker** — when a break is due, every display blacks out;
  the primary one shows a live countdown and a rotating quote, so a second monitor
  can't be used to work through the break.
- **⌥⇧⎋ to skip** — press Option+Shift+Escape to end a break early (deliberately
  awkward, so you don't do it by reflex).
- **Pause / Resume / Reset**, **Take break now**, **End break now** — all in the
  menu.
- **Statistics** — total breaks, today / last 7 / last 30 days, active days,
  current and longest streak, and estimated eye-rest time, computed from a
  plain-text log on your own machine. Nothing is uploaded.
- **Launch at login** via `brew services`.

Self-contained: one small Swift menu-bar app, no background helpers, no network
access, no data collection.

## Requirements

- macOS 13 or later
- Xcode or the Command Line Tools (`xcode-select --install`) — the app is compiled
  from source at install time, which is what lets it run without code-signing.

## Install

```sh
brew install mirxomitov/tap/eyebreak
brew services start eyebreak      # run it now and at every login
```

Look for the 👀 icon in your menu bar. `brew services` manages the launch-at-login
agent; `brew services stop eyebreak` disables it. Prefer no auto-start? Skip the
second line and just run `eyebreak`.

### Build from source

```sh
git clone https://github.com/Mirxomitov/eyebreak.git
cd eyebreak
native/build.sh            # produces native/build/Eyebreak.app
open native/build/Eyebreak.app
```

## Usage

Click the 👀 menu-bar icon for the menu:

- **Take break now** / **End break now**
- **Pause** / **Resume**, **Reset timer**
- **Statistics…**
- **Settings** — toggle the full-screen blocker, edit the config and quotes files

During a break the screen blocks; press **⌥⇧⎋** to skip.

## Configuration

State lives in `~/.eyebreak`:

- `config` — `WORK_MINUTES`, `BREAK_SECONDS` (short break length in seconds),
  `BREAKS_UNTIL_LONG` and `LONG_BREAK_MINUTES` (Pomodoro: after this many short
  breaks, take one longer break), `SHOW_BLOCKER` (`1` = full-screen blocker,
  `0` = notification only). Edit via **Settings ▸ Edit config…**.
- `quotes.txt` — the break-quote pool, one per line (seeded on first run).
- `stats.csv` — append-only usage log (`iso,epoch,event`); every statistic is
  derived from it. It never leaves your machine.

## Uninstall

```sh
brew services stop eyebreak
brew uninstall eyebreak
rm -rf ~/.eyebreak          # optional: also delete config + history
```

## License

[MIT](LICENSE)
