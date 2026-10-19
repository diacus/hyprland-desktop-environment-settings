#!/usr/bin/env bash
# Toggle the calendar popup (click action of the waybar date widget):
# one click opens it, a second one closes it; any click elsewhere closes
# it too (the popup quits on focus loss, see calendar-popup.py).
set -euo pipefail

state=/tmp/waybar-calendar-toggle

# Anchor on the interpreter: a plain substring match would also hit any
# process merely mentioning the script name on its command line (a waybar
# on-click wrapper among them), killing that instead.
pattern='^(.*/)?python3? .*/calendar-popup\.py$'
if pgrep -f "$pattern" >/dev/null; then
    pkill -f "$pattern" || true
    date +%s%N > "$state"
    exit 0
fi

# Debounce: the popup also closes itself the moment focus leaves it, and
# a widget click briefly unfocuses first — without this check a second
# click could close it and immediately respawn a fresh one.
if [[ -f "$state" ]] && (( $(date +%s%N) - $(<"$state") < 500000000 )); then
    exit 0
fi

exec setsid -f "$HOME/.config/hypr/scripts/calendar-popup.py"