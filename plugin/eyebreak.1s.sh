#!/bin/bash
# <xbar.title>20-20-20 Eye Break</xbar.title>
# <xbar.version>v1.2.0</xbar.version>
# <xbar.desc>Menu bar 20-20-20 eye break timer.</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

# Shared paths, config, log_event, write_state, fmt_epoch all live in the lib.
LIB="$HOME/.eyebreak/eyebreak-lib.sh"
if [ ! -f "$LIB" ]; then
    # Surface a clear menu-bar error instead of a silently broken plugin.
    echo "👀 ⚠️"
    echo "---"
    echo "eyebreak library missing at $LIB"
    echo "Run install.sh from the eyebreak-swiftbar repo"
    exit 0
fi
# shellcheck disable=SC1090
. "$LIB"

CTL="$DIR/eyebreak-ctl.sh"
STATS_SCRIPT="$DIR/eyebreak-stats.sh"

now=$(date +%s)

# shellcheck disable=SC1090
[ -f "$STATE" ] && . "$STATE"

phase=${phase:-work}
phase_end=${phase_end:-$((now + WORK_MINUTES * 60))}
breaks=${breaks:-0}
start_time=${start_time:-$now}
paused=${paused:-0}
paused_remaining=${paused_remaining:-0}

# Without this the seeded phase_end above is recomputed every run and the clock never moves.
[ -f "$STATE" ] || write_state

if [ "$paused" = "1" ]; then
    remaining=$paused_remaining
else
    remaining=$((phase_end - now))

    if [ "$remaining" -le 0 ]; then
        # A run that grabbed the lock and was then SIGKILLed (e.g. SwiftBar's
        # background-run timeout) never runs its EXIT trap, so a stale .lock would
        # otherwise wedge the phase machine forever. Clear it if it's older than a
        # few seconds — a real flip holds the lock for a fraction of one tick.
        if [ -d "$DIR/.lock" ]; then
            lock_mtime=$(stat -f %m "$DIR/.lock" 2>/dev/null || stat -c %Y "$DIR/.lock" 2>/dev/null || echo "$now")
            [ $((now - lock_mtime)) -ge 5 ] && rmdir "$DIR/.lock" 2>/dev/null
        fi
        # Serialize the phase flip so a slow run can't double-fire it.
        if mkdir "$DIR/.lock" 2>/dev/null; then
            trap 'rmdir "$DIR/.lock" 2>/dev/null' EXIT
            if [ "$phase" = "work" ]; then
                phase=break
                phase_end=$((now + BREAK_MINUTES * 60))
                write_state
                log_event break_start "$now"
                # One shared path decides notification + blocker-or-dialog-or-
                # nothing based on SHOW_BLOCKER; the manual break in ctl uses it too.
                present_break $((BREAK_MINUTES * 60))
            else
                breaks=$((breaks + 1))
                phase=work
                phase_end=$((now + WORK_MINUTES * 60))
                write_state
                log_event break_end "$now"
                notify "✅ Eye Break Complete" "Break finished. Back to work!"
            fi
        fi
        remaining=$((phase_end - now))
        [ "$remaining" -lt 0 ] && remaining=0
    fi
fi

elapsed=$((now - start_time))
clock=$(printf "%02d:%02d" $((remaining / 60)) $((remaining % 60)))
elapsed_clock=$(printf "%02d:%02d" $((elapsed / 3600)) $(((elapsed % 3600) / 60)))

if [ "$paused" = "1" ]; then
    icon="⏸"
    label="Paused"
elif [ "$phase" = "break" ]; then
    icon="☕"
    label="Break ends in"
else
    icon="👀"
    label="Next break in"
fi

echo "$icon $clock | font=Menlo size=13"
echo "---"
echo "$label $clock | font=Menlo"
echo "Completed breaks: $breaks"
echo "Session elapsed: $elapsed_clock"
echo "---"

if [ "$phase" = "break" ]; then
    echo "End break now | bash=$CTL param1=work terminal=false refresh=true"
else
    echo "Take break now | bash=$CTL param1=break terminal=false refresh=true"
fi

if [ "$paused" = "1" ]; then
    echo "Resume | bash=$CTL param1=pause terminal=false refresh=true"
else
    echo "Pause | bash=$CTL param1=pause terminal=false refresh=true"
fi

echo "Reset timer | bash=$CTL param1=reset terminal=false refresh=true"
echo "---"
echo "📊 Statistics… | bash=$STATS_SCRIPT param1=--dialog terminal=false"
echo "---"

# Settings submenu — SwiftBar renders leading tabs as nesting.
echo "Settings"

if [ "${SHOW_BLOCKER:-1}" = "1" ]; then
    echo "--✓ Full-screen blocker | bash=$CTL param1=blocker-off terminal=false refresh=true"
else
    echo "--Full-screen blocker | bash=$CTL param1=blocker-on terminal=false refresh=true"
fi
if [ ! -x "$BLOCKER" ]; then
    echo "--⚠ Blocker not installed — re-run install.sh | color=orange"
fi

if [ -f "$LOGIN_PLIST" ]; then
    echo "--✓ Launch at login | bash=$CTL param1=login-disable terminal=false refresh=true"
else
    echo "--Launch at login | bash=$CTL param1=login-enable terminal=false refresh=true"
fi

echo "--Edit config… | bash=/usr/bin/open param1=-t param2=$CONFIG terminal=false"
echo "--Edit quotes… | bash=/usr/bin/open param1=-t param2=$QUOTES terminal=false"
