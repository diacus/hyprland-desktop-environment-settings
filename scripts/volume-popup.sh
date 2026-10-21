#!/usr/bin/env bash
# Toggle the volume popup (click action of the waybar volume widget):
# one click opens it, a second one closes it; any click elsewhere closes
# it too (the popup quits on focus loss, see volume-popup.py).
#
# With `osd` as the argument it is not a toggle: the XF86 volume keybinds
# spawn a fresh OSD each time, so it re-reads the just-applied volume and
# restarts its fade timer (see volume-popup.py).
set -euo pipefail

state=/tmp/waybar-volume-toggle

# Anchor on the interpreter: a plain substring match would also hit any
# process merely mentioning the script name on its command line (a waybar
# on-click wrapper among them), killing that instead. Without the $ the
# pattern also matches the OSD's `... volume-popup.py osd` command line.
pattern='^(.*/)?python3? .*/volume-popup\.py'
if [[ "${1:-}" == osd ]]; then
    # Rapid key repeats would stack OSDs: kill any live one first and let
    # it exit before a new one takes its place.
    pkill -f "$pattern" || true
    sleep 0.1
    exec setsid -f "$HOME/.config/hypr/scripts/volume-popup.py" osd
fi

if pgrep -f "${pattern}$" >/dev/null; then
    pkill -f "${pattern}$" || true
    date +%s%N > "$state"
    exit 0
fi

# Debounce: the popup also closes itself the moment focus leaves it, and
# a widget click briefly unfocuses first — without this check a second
# click could close it and immediately respawn a fresh one.
if [[ -f "$state" ]] && (( $(date +%s%N) - $(<"$state") < 500000000 )); then
    exit 0
fi

exec setsid -f "$HOME/.config/hypr/scripts/volume-popup.py"