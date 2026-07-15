#!/bin/bash
# Report usage statistics for the 20-20-20 eye-break timer.
# Reads the append-only log at ~/.eyebreak/stats.csv (written by the SwiftBar
# plugin and eyebreak-ctl.sh) and prints a summary.
#
# Usage:
#   eyebreak-stats.sh            print the report to stdout
#   eyebreak-stats.sh --dialog   show the report in a macOS dialog (menu-bar use)
#   eyebreak-stats.sh --csv      print the raw log path and reveal it in Finder

# Shared paths, config, and the portable fmt_epoch helper come from the lib.
LIB="$HOME/.eyebreak/eyebreak-lib.sh"
if [ ! -f "$LIB" ]; then
    echo "eyebreak library missing at $LIB — run install.sh" >&2
    exit 1
fi
# shellcheck disable=SC1090
. "$LIB"

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

# One awk pass. All day math is done on Julian day numbers derived from each
# row's calendar date, so it needs no external `date` calls and is immune to
# timezone/DST drift (consecutive calendar days always differ by exactly 1).
# Emits one whitespace-separated line:
#   total today week month active_days paired paired_secs unpaired first last cur longest
read -r total today week month active_days paired psecs unpaired first_epoch last_epoch cur longest \
    <<<"$(awk -F, -v today="$(date '+%Y-%m-%d')" '
    function jdn(s,   y, m, d, a, yy, mm) {
        y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
        a = int((14 - m) / 12); yy = y + 4800 - a; mm = m + 12 * a - 3
        return d + int((153 * mm + 2) / 5) + 365 * yy \
            + int(yy / 4) - int(yy / 100) + int(yy / 400) - 32045
    }
    BEGIN { tj = jdn(today) }
    NR == 1 && $1 == "iso" { next }
    { ev = $3; ep = $2 + 0; dj = jdn(substr($1, 1, 10)) }
    ev == "break_start" { pend = ep; next }
    ev == "reset"       { pend = 0;  next }
    ev == "break_end" {
        total++
        if (!(dj in seen)) {
            seen[dj] = 1; active++
            if (minj == 0 || dj < minj) minj = dj
            if (dj > maxj) maxj = dj
        }
        if (dj == tj)     today_c++
        if (dj > tj - 7)  week_c++
        if (dj > tj - 30) month_c++
        if (first == 0 || ep < first) first = ep
        if (ep > last) last = ep
        if (pend > 0) { paired++; psecs += (ep - pend); pend = 0 }
        else unpaired++
        next
    }
    END {
        # Current streak: count back from today, or from yesterday if nothing yet
        # today, so a morning check does not read 0.
        k = tj; if (!(k in seen)) k = tj - 1
        cur = 0; while (k in seen) { cur++; k-- }
        # Longest streak: scan the whole active range once, tracking run length.
        best = 0; run = 0
        for (k = minj; k <= maxj; k++) {
            if (k in seen) { run++; if (run > best) best = run } else run = 0
        }
        printf "%d %d %d %d %d %d %d %d %d %d %d %d\n", \
            total, today_c, week_c, month_c, active, \
            paired, psecs, unpaired, first, last, cur, best
    }
' "$STATS")"

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

first_str=$(fmt_epoch "$first_epoch" '%a %b %-d, %Y')
last_str=$(fmt_epoch "$last_epoch" '%a %b %-d, %Y %H:%M')

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
