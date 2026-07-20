# Changelog

All notable changes to Eyebreak are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-07-20

### Added
- **Pomodoro long breaks.** Every `LONG_BREAK_EVERY`-th break (default 4) is a
  longer `LONG_BREAK_MINUTES` break (default 5) instead of a short one — the
  classic long break after four work sessions — with its own 🌴 menu-bar icon,
  a "Long break" blocker title, and a matching pre-break notification.
  **Take break now** always triggers a short break and doesn't consume the cycle.
- **Native Settings window.** A new **Settings…** menu item opens a real
  window with sliders (work interval, short break, long-break-every, long
  break) and a full-screen-blocker checkbox. Every reachable value is valid,
  so the config can no longer be broken by mistyping. Changes apply live and
  persist to `~/.eyebreak/config`.

### Changed
- **Short breaks are now measured in seconds** (`BREAK_SECONDS`, default 20 —
  the classic 20-20-20 glance-away) instead of minutes.
- **Trimmed the menu bar menu** to just actions: Take/End break, Pause/Resume,
  Reset timer, Statistics…, Settings…, Edit quotes…, Quit. The greyed-out
  status/stat header lines were removed (the icon already shows the phase),
  and the standalone "Full-screen blocker" toggle now lives in Settings.

### Config
New `~/.eyebreak/config` keys:

```
WORK_MINUTES=20
BREAK_SECONDS=20
LONG_BREAK_EVERY=4
LONG_BREAK_MINUTES=5
SHOW_BLOCKER=1
```

An older `BREAK_MINUTES` value is still honored (read as minutes) for
backward compatibility.

## [1.3.0]

- Menu-bar 20-20-20 eye-break timer with full-screen break blocker, rotating
  quotes, ⌥⇧⎋ to skip, pause/resume/reset, statistics, and launch-at-login via
  `brew services`.
