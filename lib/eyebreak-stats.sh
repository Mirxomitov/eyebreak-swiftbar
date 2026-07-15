#!/bin/bash
# Report usage statistics for the 20-20-20 eye-break timer.
# Reads the append-only log at ~/.eyebreak/stats.csv (written by the SwiftBar
# plugin and eyebreak-ctl.sh) and prints a summary.
#
# Usage:
#   eyebreak-stats.sh            print the report to stdout
#   eyebreak-stats.sh --dialog   show the report in a macOS dialog (menu-bar use)
#   eyebreak-stats.sh --csv      print the raw log path and open it

DIR="$HOME/.eyebreak"
STATS="$DIR/stats.csv"
CONFIG="$DIR/config"

BREAK_MINUTES=2
[ -f "$CONFIG" ] && . "$CONFIG"

if [ ! -s "$STATS" ] || [ "$(grep -c break_end "$STATS" 2>/dev/null)" = "0" ]; then
    report="No completed breaks recorded yet.

Take a break from the menu bar and check back — stats accumulate in
$STATS"
    if [ "$1" = "--dialog" ]; then
        osascript \
            -e 'on run {t, m}' -e 'tell me to activate' \
            -e 'display dialog m with title t buttons {"OK"} default button "OK"' \
            -e 'end run' "📊 Eye Break Stats" "$report" >/dev/null 2>&1
    else
        printf '%s\n' "$report"
    fi
    exit 0
fi

# Day boundaries as epochs, so "today / last 7 / last 30" are calendar-accurate.
today_mid=$(date -v0H -v0M -v0S '+%s')
week_start=$((today_mid - 6 * 86400))   # today + previous 6 days
month_start=$((today_mid - 29 * 86400)) # today + previous 29 days

# One awk pass over the log. Emits:
#   SUMMARY total today week month paired paired_secs unpaired first_epoch last_epoch
#   DAY <yyyy-mm-dd> <break_end count that day>
agg=$(awk -F, -v tmid="$today_mid" -v wk="$week_start" -v mo="$month_start" '
    NR == 1 && $1 == "iso" { next }        # skip header
    {
        ev = $3; ep = $2 + 0; day = substr($1, 1, 10)
    }
    ev == "break_start" { pend = ep; next }
    ev == "reset"       { pend = 0;  next }
    ev == "break_end" {
        total++
        dcount[day]++
        if (ep >= tmid) today++
        if (ep >= wk)   week++
        if (ep >= mo)   month++
        if (first == 0 || ep < first) first = ep
        if (ep > last) last = ep
        if (pend > 0) { paired++; psecs += (ep - pend); pend = 0 }
        else unpaired++
        next
    }
    END {
        printf "SUMMARY %d %d %d %d %d %d %d %d %d\n", \
            total, today, week, month, paired, psecs, unpaired, first, last
        for (d in dcount) printf "DAY %s %d\n", d, dcount[d]
    }
' "$STATS")

read -r _ total today week month paired psecs unpaired first_epoch last_epoch \
    <<<"$(printf '%s\n' "$agg" | grep '^SUMMARY ')"

days_list=$(printf '%s\n' "$agg" | awk '/^DAY /{print $2}' | sort)
active_days=$(printf '%s\n' "$days_list" | grep -c .)

# Estimated eye-rest time: measured seconds for paired start/end events, plus the
# nominal break length for any break_end we could not pair (e.g. plugin was not
# running at the matching start).
rest_secs=$((psecs + unpaired * BREAK_MINUTES * 60))
rest_h=$((rest_secs / 3600))
rest_m=$(((rest_secs % 3600) / 60))

# Average breaks per active day, one decimal, without bc.
if [ "$active_days" -gt 0 ]; then
    avg=$(awk -v t="$total" -v d="$active_days" 'BEGIN { printf "%.1f", t / d }')
else
    avg="0.0"
fi

# Current streak: consecutive days with >=1 break, counting back from today
# (or from yesterday if nothing yet today, so a morning check does not read 0).
has_day() { printf '%s\n' "$days_list" | grep -qx "$1"; }

cur=0
d=$(date '+%Y-%m-%d')
has_day "$d" || d=$(date -v-1d '+%Y-%m-%d')
while has_day "$d"; do
    cur=$((cur + 1))
    d=$(date -j -v-1d -f '%Y-%m-%d' "$d" '+%Y-%m-%d')
done

# Longest streak: walk sorted distinct days, extend the run while each day is
# exactly one day after the previous.
longest=$(printf '%s\n' "$days_list" | awk '
    NR == 1 { run = 1; prev = $0; best = 1; next }
    {
        cmd = "date -j -v+1d -f %Y-%m-%d " prev " +%Y-%m-%d"
        cmd | getline nextday; close(cmd)
        if ($0 == nextday) run++; else run = 1
        if (run > best) best = run
        prev = $0
    }
    END { print best + 0 }
')

first_str=$(date -r "$first_epoch" '+%a %b %-d, %Y')
last_str=$(date -r "$last_epoch" '+%a %b %-d, %Y %H:%M')

report=$(cat <<EOF
📊 Eye Break — Usage Stats

Total breaks taken : $total
   Today           : $today
   Last 7 days     : $week
   Last 30 days    : $month

Active days        : $active_days
Avg / active day   : $avg
Current streak     : $cur day(s)
Longest streak     : $longest day(s)

Eye-rest time      : ${rest_h}h ${rest_m}m (est.)

First break        : $first_str
Last break         : $last_str
EOF
)

case "$1" in
    --dialog)
        # Args go through argv (t, m, p) so the report text and path can't break
        # the AppleScript. "Reveal log" opens the CSV's folder in Finder.
        osascript \
            -e 'on run {t, m, p}' -e 'tell me to activate' \
            -e 'set r to display dialog m with title t buttons {"Reveal log", "OK"} default button "OK"' \
            -e 'if button returned of r is "Reveal log" then do shell script "open -R " & quoted form of p' \
            -e 'end run' "📊 Eye Break Stats" "$report" "$STATS" >/dev/null 2>&1
        ;;
    --csv)
        printf '%s\n' "$STATS"
        open -R "$STATS"
        ;;
    *)
        printf '%s\n' "$report"
        ;;
esac
