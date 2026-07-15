#!/bin/bash
# <xbar.title>20-20-20 Eye Break</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.desc>Menu bar 20-20-20 eye break timer.</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

DIR="$HOME/.eyebreak"
STATE="$DIR/state"
CONFIG="$DIR/config"
CTL="$DIR/eyebreak-ctl.sh"
STATS="$DIR/stats.csv"
STATS_SCRIPT="$DIR/eyebreak-stats.sh"

WORK_MINUTES=20
BREAK_MINUTES=2
[ -f "$CONFIG" ] && . "$CONFIG"

now=$(date +%s)

# shellcheck disable=SC1090
[ -f "$STATE" ] && . "$STATE"

phase=${phase:-work}
phase_end=${phase_end:-$((now + WORK_MINUTES * 60))}
breaks=${breaks:-0}
start_time=${start_time:-$now}
paused=${paused:-0}
paused_remaining=${paused_remaining:-0}

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

urlencode() {
    # LC_ALL=C so the loop walks bytes, not characters, and emoji encode correctly.
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

notify() {
    # osascript notifications post as "Script Editor", which is not authorized to
    # notify, and `display notification` still exits 0 when suppressed. Route through
    # SwiftBar instead, which holds the notification permission.
    local plugin=${SWIFTBAR_PLUGIN_PATH##*/}
    plugin=${plugin:-eyebreak.1s.sh}
    open -g "swiftbar://notify?plugin=$(urlencode "$plugin")&title=$(urlencode "$1")&body=$(urlencode "$2")&silent=false" >/dev/null 2>&1
}

alert() {
    # A banner slides away and gets missed, so the break also gets a modal dialog.
    # Detached: `display dialog` blocks until clicked, and SwiftBar re-runs this
    # plugin every second — inline, the menu bar clock would freeze behind it.
    # `tell me to activate` pulls the dialog in front of the frontmost app.
    # Args go through argv, not string interpolation, so quotes in them can't break
    # the AppleScript. It self-dismisses just before the break ends.
    nohup osascript \
        -e 'on run {t, m, secs}' \
        -e 'tell me to activate' \
        -e 'display dialog m with title t buttons {"Start Break"} default button "Start Break" with icon caution giving up after (secs as integer)' \
        -e 'end run' \
        "$1" "$2" "$3" >/dev/null 2>&1 &
    disown 2>/dev/null
}

log_event() {
    # Append-only usage log, one row per event. The reporter derives every stat
    # from this file, so it must capture both auto flips (here) and manual actions
    # (eyebreak-ctl.sh). `date -r "$now"` formats from the epoch we already hold,
    # keeping the row's clock consistent with the state clock.
    [ -f "$STATS" ] || printf 'iso,epoch,event\n' >"$STATS"
    printf '%s,%s,%s\n' "$(date -r "$now" '+%Y-%m-%dT%H:%M:%S')" "$now" "$1" >>"$STATS"
}

# Without this the seeded phase_end above is recomputed every run and the clock never moves.
[ -f "$STATE" ] || write_state

if [ "$paused" = "1" ]; then
    remaining=$paused_remaining
else
    remaining=$((phase_end - now))

    if [ "$remaining" -le 0 ]; then
        # Serialize the phase flip so a slow run can't double-fire it.
        if mkdir "$DIR/.lock" 2>/dev/null; then
            trap 'rmdir "$DIR/.lock" 2>/dev/null' EXIT
            if [ "$phase" = "work" ]; then
                phase=break
                phase_end=$((now + BREAK_MINUTES * 60))
                write_state
                log_event break_start
                notify "👀 Eye Break" "Look at something at least 20 feet away for ${BREAK_MINUTES} minutes."
                alert "20-20-20 Rule" "Time for a ${BREAK_MINUTES}-minute eye break.

Look at something at least 20 feet away." $((BREAK_MINUTES * 60 - 5))
            else
                breaks=$((breaks + 1))
                phase=work
                phase_end=$((now + WORK_MINUTES * 60))
                write_state
                log_event break_end
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
