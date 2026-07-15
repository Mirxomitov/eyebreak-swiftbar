#!/bin/bash
# Shared library for the eye-break timer, sourced by the plugin, the control
# script, and the stats reporter. Holds everything the three scripts would
# otherwise duplicate: common paths, config defaults, a portable epoch
# formatter, the usage logger, and state serialization.

DIR="$HOME/.eyebreak"
STATE="$DIR/state"
CONFIG="$DIR/config"
STATS="$DIR/stats.csv"

WORK_MINUTES=20
BREAK_MINUTES=2
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && . "$CONFIG"

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
