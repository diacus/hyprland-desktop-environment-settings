#!/usr/bin/env bash
# Waybar media widget: emits JSON for the custom/media module.
# jq builds the JSON so titles containing quotes/emoji cannot corrupt it.
set -euo pipefail

status="$(playerctl status 2>/dev/null || true)"
if [[ -z "${status}" ]]; then
    echo '{"text": "", "class": ""}'
    exit 0
fi

if [[ "${status}" == "Playing" ]]; then
    icon="▶"
else
    icon="⏸"
fi

title="$(playerctl metadata -f '{{artist}} – {{title}}' 2>/dev/null || true)"
jq -cn --arg icon "${icon}" --arg title "${title}" --arg class "$(echo "${status}" | tr '[:upper:]' '[:lower:]')" \
    '{text: ($icon + " " + $title), class: $class}'