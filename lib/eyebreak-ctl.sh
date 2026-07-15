#!/bin/bash
# Control actions for the eye-break menu bar timer.
# Usage: eyebreak-ctl.sh <break|work|pause|reset>

STATE="$HOME/.eyebreak/state"
CONFIG="$HOME/.eyebreak/config"
STATS="$HOME/.eyebreak/stats.csv"

WORK_MINUTES=20
BREAK_MINUTES=2
[ -f "$CONFIG" ] && . "$CONFIG"

now=$(date +%s)

# shellcheck disable=SC1090
[ -f "$STATE" ] && . "$STATE"

breaks=${breaks:-0}
start_time=${start_time:-$now}
paused=${paused:-0}
phase=${phase:-work}

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

log_event() {
    # Mirror of the plugin's logger so manual "Take/End break now" and "Reset"
    # land in the same append-only usage log the auto flips write to.
    [ -f "$STATS" ] || printf 'iso,epoch,event\n' >"$STATS"
    printf '%s,%s,%s\n' "$(date -r "$now" '+%Y-%m-%dT%H:%M:%S')" "$now" "$1" >>"$STATS"
}

case "$1" in
break)
    phase=break
    phase_end=$((now + BREAK_MINUTES * 60))
    paused=0
    paused_remaining=0
    log_event break_start
    ;;
work)
    # Ending a break early still counts it as taken.
    if [ "$phase" = "break" ]; then
        breaks=$((breaks + 1))
        log_event break_end
    fi
    phase=work
    phase_end=$((now + WORK_MINUTES * 60))
    paused=0
    paused_remaining=0
    ;;
pause)
    if [ "$paused" = "1" ]; then
        phase_end=$((now + paused_remaining))
        paused=0
        paused_remaining=0
    else
        paused_remaining=$((phase_end - now))
        [ "$paused_remaining" -lt 0 ] && paused_remaining=0
        paused=1
    fi
    ;;
reset)
    phase=work
    phase_end=$((now + WORK_MINUTES * 60))
    breaks=0
    start_time=$now
    paused=0
    paused_remaining=0
    log_event reset
    ;;
*)
    echo "usage: $0 <break|work|pause|reset>" >&2
    exit 1
    ;;
esac

write_state
