#!/usr/bin/env bash
# Waybar session widget: emits JSON for the custom/power module.
# jq builds the JSON so quoting cannot corrupt the payload.
set -euo pipefail

jq -cn --arg tooltip 'Session menu (Super+Shift+E)' \
    '{text: "⏻", class: "power", tooltip: $tooltip}'