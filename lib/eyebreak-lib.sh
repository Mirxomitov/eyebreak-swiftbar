#!/bin/bash
# Shared library for the eye-break timer, sourced by the plugin, the control
# script, and the stats reporter. Holds everything the three scripts would
# otherwise duplicate: common paths, config defaults, a portable epoch
# formatter, the usage logger, and state serialization.

DIR="$HOME/.eyebreak"
STATE="$DIR/state"
CONFIG="$DIR/config"
STATS="$DIR/stats.csv"
QUOTES="$DIR/quotes.txt"
BLOCKER="$DIR/eyebreak-blocker"

# Launch-at-login is implemented as a per-user LaunchAgent that starts SwiftBar
# (the host this plugin runs inside) at login. A file check is all the plugin
# needs to know the state — no per-second osascript, no permission prompt.
LOGIN_LABEL="com.eyebreak.swiftbar.login"
LOGIN_PLIST="$HOME/Library/LaunchAgents/$LOGIN_LABEL.plist"

WORK_MINUTES=20
BREAK_MINUTES=2
# Whether the break puts up the full-screen blocker. Off falls back to the
# notification + dialog only, so the blocker is strictly opt-in on upgrade.
SHOW_BLOCKER=1
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"

# Pick a random usable line from the quotes file (skipping blanks and #comments).
# Falls back to a sensible default if the file is missing or empty, so callers can
# always interpolate the result without guarding it.
random_quote() {
    local fallback="Look at something at least 20 feet away for a full 20 seconds."
    [ -f "$QUOTES" ] || { printf '%s' "$fallback"; return; }
    local quote
    quote=$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$QUOTES" | sort -R | head -1)
    printf '%s' "${quote:-$fallback}"
}

# Put up the full-screen break blocker for the given number of seconds, if it is
# both enabled and installed. Runs detached so the caller (the 1s plugin) returns
# immediately instead of blocking the menu-bar clock for the whole break.
launch_blocker() {
    local secs=$1
    [ "${SHOW_BLOCKER:-1}" = "1" ] || return 0
    [ -x "$BLOCKER" ] || return 0
    nohup "$BLOCKER" --seconds "$secs" --quote "$(random_quote)" >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

# Portable epoch formatter. BSD date (macOS) formats an epoch with `-r`; GNU
# coreutils date (Homebrew gnubin in PATH, Linux) uses `-d @<epoch>`. Detect
# once at source time so callers never touch date's incompatible flags.
if date --version >/dev/null 2>&1; then
    fmt_epoch() { date -d "@$1" "+$2"; } # GNU
else
    fmt_epoch() { date -r "$1" "+$2"; }  # BSD
fi

# Append-only usage log, one row per event (break_start | break_end | reset).
# $1 = event name, $2 = epoch. Every statistic is derived from this file, so it
# must capture both the plugin's auto flips and eyebreak-ctl.sh's manual actions.
log_event() {
    [ -f "$STATS" ] || printf 'iso,epoch,event\n' >"$STATS"
    printf '%s,%s,%s\n' "$(fmt_epoch "$2" '%Y-%m-%dT%H:%M:%S')" "$2" "$1" >>"$STATS"
}

# Set a KEY=VALUE in the config file, replacing an existing line or appending a
# new one. Used by the menu toggles so a setting change survives restarts without
# the user hand-editing the file. Creates the config if it does not exist yet.
set_config() {
    local key=$1 value=$2
    [ -f "$CONFIG" ] || touch "$CONFIG"
    if grep -q "^[[:space:]]*${key}=" "$CONFIG"; then
        # In-place edit via a temp file so it works the same on BSD and GNU sed.
        local tmp="$CONFIG.tmp.$$"
        sed "s/^[[:space:]]*${key}=.*/${key}=${value}/" "$CONFIG" >"$tmp" && mv "$tmp" "$CONFIG"
    else
        printf '%s=%s\n' "$key" "$value" >>"$CONFIG"
    fi
}

# Write and load the launch-at-login LaunchAgent (starts SwiftBar at login).
enable_login() {
    local swiftbar
    swiftbar=$(swiftbar_app_path)
    mkdir -p "$(dirname "$LOGIN_PLIST")"
    cat >"$LOGIN_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LOGIN_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$swiftbar</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
    launchctl unload "$LOGIN_PLIST" 2>/dev/null || true
    launchctl load "$LOGIN_PLIST" 2>/dev/null || true
}

# Unload and remove the launch-at-login LaunchAgent.
disable_login() {
    launchctl unload "$LOGIN_PLIST" 2>/dev/null || true
    rm -f "$LOGIN_PLIST"
}

# Best-effort path to the SwiftBar app so `open -a` resolves it at login even if
# it is not in the default /Applications location.
swiftbar_app_path() {
    if [ -d "/Applications/SwiftBar.app" ]; then
        printf '%s' "/Applications/SwiftBar.app"
    elif [ -d "$HOME/Applications/SwiftBar.app" ]; then
        printf '%s' "$HOME/Applications/SwiftBar.app"
    else
        # Fall back to the bundle id; `open -a SwiftBar` still resolves it.
        printf '%s' "SwiftBar"
    fi
}

# Serialize timer state. Reads phase/phase_end/breaks/start_time/paused/
# paused_remaining from the caller's scope (sourced functions see caller vars).
write_state() {
    cat >"$STATE" <<EOF
phase=$phase
phase_end=$phase_end
breaks=$breaks
start_time=$start_time
paused=$paused
paused_remaining=$paused_remaining
EOF
}
