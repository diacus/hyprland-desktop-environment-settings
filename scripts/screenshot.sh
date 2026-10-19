#!/usr/bin/env bash
# Screenshot helper for Hyprland (grim + slurp + wl-clipboard + notify)
#   usage: screenshot.sh [area|full|window]
#   area (default) - select a region with slurp
#   full           - all monitors
#   window         - the currently focused window
set -euo pipefail

mode="${1:-area}"
shot_dir="${HOME}/Pictures/Screenshots"
file="${shot_dir}/shot-$(date +%Y%m%d-%H%M%S).png"
mkdir -p "${shot_dir}"

case "${mode}" in
    area)
        box="$(slurp)" || exit 0 # cancelled by user
        grim -g "${box}" "${file}"
        ;;
    full)
        grim "${file}"
        ;;
    window)
        box="$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')"
        grim -g "${box}" "${file}"
        ;;
    *)
        echo "usage: ${0##*/} [area|full|window]" >&2
        exit 1
        ;;
esac

wl-copy < "${file}"
notify-send -i "${file}" "Screenshot" "${mode} -> $(basename "${file}") (copied)"