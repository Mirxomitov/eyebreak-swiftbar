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
CTL="$DIR/eyebreak-ctl.sh"

# Launch-at-login is implemented as a per-user LaunchAgent that starts SwiftBar
# (the host this plugin runs inside) at login. A file check is all the plugin
# needs to know the state — no per-second osascript, no permission prompt.
LOGIN_LABEL="com.eyebreak.swiftbar.login"
LOGIN_PLIST="$HOME/Library/LaunchAgents/$LOGIN_LABEL.plist"

WORK_MINUTES=20
BREAK_MINUTES=2
# Whether the break puts up the full-screen blocker (1) or just posts a
# notification (0). Defaults on; an upgrading user with no key set gets it.
SHOW_BLOCKER=1
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"

# Guard the timing values: a hand-edited 0, negative, or non-numeric would make
# the plugin flip phases every tick (notification + stats spam) or run the clock
# backwards. Fall back to the defaults rather than trust the file blindly.
case "$WORK_MINUTES" in ''|*[!0-9]*) WORK_MINUTES=20 ;; esac
case "$BREAK_MINUTES" in ''|*[!0-9]*) BREAK_MINUTES=2 ;; esac
[ "$WORK_MINUTES"  -ge 1 ] 2>/dev/null || WORK_MINUTES=20
[ "$BREAK_MINUTES" -ge 1 ] 2>/dev/null || BREAK_MINUTES=2

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

# Percent-encode a string for a URL query value. LC_ALL=C so the loop walks bytes,
# not characters, and emoji/multibyte encode correctly.
urlencode() {
    local LC_ALL=C
    local s=$1 i c out=
    for ((i = 0; i < ${#s}; i++)); do
        c=${s:$i:1}
        case $c in
            [a-zA-Z0-9.~_-]) out+=$c ;;
            *) out+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    printf '%s' "$out"
}

# Post a notification through SwiftBar (which holds the notification permission;
# osascript notifications post as "Script Editor" and get silently suppressed).
notify() {
    local plugin=${SWIFTBAR_PLUGIN_PATH##*/}
    plugin=${plugin:-eyebreak.1s.sh}
    open -g "swiftbar://notify?plugin=$(urlencode "$plugin")&title=$(urlencode "$1")&body=$(urlencode "$2")&silent=false" >/dev/null 2>&1
}

# Show a modal "Start Break" dialog that jumps to the front and self-dismisses
# after $3 seconds. Used as the blocker's fallback when the native helper isn't
# installed. Detached so the 1s plugin's menu-bar clock doesn't freeze behind it.
# Args go through argv, not string interpolation, so quotes in them can't break
# the AppleScript.
alert() {
    nohup osascript \
        -e 'on run {t, m, secs}' \
        -e 'tell me to activate' \
        -e 'display dialog m with title t buttons {"Start Break"} default button "Start Break" with icon caution giving up after (secs as integer)' \
        -e 'end run' \
        "$1" "$2" "$3" >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

# Put up the full-screen break blocker for the given number of seconds. Kills any
# blocker already on screen first so a manual break can't stack a second one, and
# passes the control script so an early ⌥⇧⎋ skip can end the break in the timer.
# Runs detached so the caller (the 1s plugin) returns immediately.
launch_blocker() {
    local secs=$1
    [ -x "$BLOCKER" ] || return 1
    pkill -f "$BLOCKER" 2>/dev/null || true
    nohup "$BLOCKER" --seconds "$secs" --quote "$(random_quote)" --skip-exec "$CTL" >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

# The single break-presentation path, shared by the plugin's auto flip and the
# ctl "take break now" action so both behave identically:
#   SHOW_BLOCKER=1 + blocker installed -> notification + full-screen blocker
#   SHOW_BLOCKER=1 + blocker missing   -> notification + modal dialog (still forced)
#   SHOW_BLOCKER=0                     -> notification only (genuinely "notify only")
present_break() {
    local secs=$1
    notify "👀 Eye Break" "Look at something at least 20 feet away for ${BREAK_MINUTES} minutes."
    [ "${SHOW_BLOCKER:-1}" = "1" ] || return 0
    if ! launch_blocker "$secs"; then
        alert "20-20-20 Rule" "Time for a ${BREAK_MINUTES}-minute eye break.

Look at something at least 20 feet away." $((secs - 5))
    fi
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
    local tmp="$CONFIG.tmp.$$" found=0 line trimmed
    # Rewrite line-by-line in pure bash — no sed, so values containing / & \ are
    # safe. Only an uncommented "key=" line is replaced; comments are left alone.
    while IFS= read -r line || [ -n "$line" ]; do
        trimmed=${line#"${line%%[![:space:]]*}"}
        case "$trimmed" in
            "$key="*) printf '%s=%s\n' "$key" "$value"; found=1 ;;
            *) printf '%s\n' "$line" ;;
        esac
    done <"$CONFIG" >"$tmp"
    [ "$found" = 0 ] && printf '%s=%s\n' "$key" "$value" >>"$tmp"
    mv "$tmp" "$CONFIG"
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
    # Register with the modern bootstrap API, falling back to legacy load on older
    # macOS. Either way the agent also auto-loads at the next login because it
    # lives in ~/Library/LaunchAgents with RunAtLoad, so this just makes it take
    # effect now without a re-login.
    local domain="gui/$(id -u)"
    launchctl bootout "$domain/$LOGIN_LABEL" 2>/dev/null || true
    launchctl bootstrap "$domain" "$LOGIN_PLIST" 2>/dev/null \
        || launchctl load "$LOGIN_PLIST" 2>/dev/null || true
}

# Unload and remove the launch-at-login LaunchAgent.
disable_login() {
    local domain="gui/$(id -u)"
    launchctl bootout "$domain/$LOGIN_LABEL" 2>/dev/null \
        || launchctl unload "$LOGIN_PLIST" 2>/dev/null || true
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
