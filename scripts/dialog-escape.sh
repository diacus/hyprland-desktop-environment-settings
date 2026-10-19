#!/usr/bin/env bash
# Close the focused utility dialog on ESC (bound as a non-consuming
# Escape bind in 50-keybinds.conf). Windows without one close elsewhere:
# GtkDialog windows (nm-connection-editor, zenity) self-close on
# Escape, rofi exits on it, the calendar popup handles it in
# calendar-popup.py; the ones below present plain GtkApplicationWindow
# (blueman is GTK3, pavucontrol 6.x GTK4) and get no Escape binding.
#
# The bind is non-consuming: ESC still reaches the focused client, and
# this runs alongside it. The class check therefore must pass a window
# that actually has focus — no class: regex on closewindow, which would
# close a dialog sitting in the background while some other app gets ESC.
set -euo pipefail

IFS='|' read -r class address <<< "$(hyprctl -j activewindow 2>/dev/null |
    jq -r '(.class // "") + "|" + (.address // "")')"

case $class in
    org.pulseaudio.pavucontrol|pavucontrol|blueman-manager|blueman-adapters)
        hyprctl dispatch closewindow "address:$address" >/dev/null
        ;;
esac