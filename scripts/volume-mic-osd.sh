#!/usr/bin/env bash
# Mic mute indicator for the mic-mute keybind: pamixer has just toggled
# the default source; read the resulting state and bubble it up as a
# notification (a GTK OSD would need focus rules for a source that has no
# slider — GNOME reports mic mute as a notification too).
set -euo pipefail

notify() {
    if command -v dunstify >/dev/null 2>&1; then dunstify "$@"; else notify-send "$@"; fi
}

[[ ${1:-} == toggle ]] || { echo "usage: volume-mic-osd.sh toggle" >&2; exit 2; }

command -v pamixer >/dev/null 2>&1 || exit 0

state="$(pamixer --default-source --get-mute 2>/dev/null)" || exit 0
if [[ $state == true ]]; then
    notify -t 1500 --icon microphone-sensitivity-muted 'Microphone muted'
else
    notify -t 1500 --icon microphone 'Microphone live'
fi