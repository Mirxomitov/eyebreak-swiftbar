#!/bin/bash
# Control actions for the eye-break menu bar timer.
# Usage: eyebreak-ctl.sh <break|work|pause|reset>

# Shared paths, config, log_event, and write_state come from the lib.
LIB="$HOME/.eyebreak/eyebreak-lib.sh"
if [ ! -f "$LIB" ]; then
    echo "eyebreak library missing at $LIB — run install.sh" >&2
    exit 1
fi
# shellcheck disable=SC1090
. "$LIB"

now=$(date +%s)

# shellcheck disable=SC1090
[ -f "$STATE" ] && . "$STATE"

breaks=${breaks:-0}
start_time=${start_time:-$now}
paused=${paused:-0}
phase=${phase:-work}

case "$1" in
break)
    phase=break
    phase_end=$((now + BREAK_MINUTES * 60))
    paused=0
    paused_remaining=0
    log_event break_start "$now"
    # A manually taken break gets the same blocker the auto flip uses.
    launch_blocker $((BREAK_MINUTES * 60))
    ;;
work)
    # Ending a break early still counts it as taken.
    if [ "$phase" = "break" ]; then
        breaks=$((breaks + 1))
        log_event break_end "$now"
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
    log_event reset "$now"
    ;;
# Settings toggles below don't touch timer state, so they act and exit before the
# write_state at the bottom (which would otherwise re-serialize the timer).
blocker-on)
    set_config SHOW_BLOCKER 1
    exit 0
    ;;
blocker-off)
    set_config SHOW_BLOCKER 0
    exit 0
    ;;
login-enable)
    enable_login
    exit 0
    ;;
login-disable)
    disable_login
    exit 0
    ;;
*)
    echo "usage: $0 <break|work|pause|reset|blocker-on|blocker-off|login-enable|login-disable>" >&2
    exit 1
    ;;
esac

write_state
