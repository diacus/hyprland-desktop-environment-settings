#!/usr/bin/env bash
# Wi-Fi menu (rofi dmenu): the click action of the waybar network widget.
# Toggle the radio, (dis)connect, connect with a password prompt, saved
# networks, and the full connection editor one click away.
#
# Backend is nmcli; the Wi-Fi device is derived, never hardcoded, so the
# menu works on any host with a Wi-Fi interface (the p2p-dev-* pseudo
# device is wifi-p2p type and filtered out like network-manager does).
# NM rate-limits scans, so the menu always opens from the cached list and
# fires a rescan in the background for the next time it is opened.
#
#   Icons are Nerd Font glyphs rendered as text and dispatched by row
#   index — see scripts/powermenu.sh for the full rationale (rofi 2.0 on
#   Wayland silently drops image icons in dmenu mode).
set -euo pipefail

for dep in nmcli rofi; do
    command -v "$dep" >/dev/null 2>&1 || exit 0
done
command -v dunstify >/dev/null 2>&1 && notify=dunstify || notify=notify-send

# Geometry and font mirror the apps menu: rofi reserves a 1em icon slot;
# here the glyph plays the icon, inset 7px into the text widget, and the
# label follows after 2 en + 1 thin space (~17.6px). The row font falls
# back to a Nerd Font just for the glyphs (per-codepoint fallback).
gap=$'   '
iconfont='* { font: "Ubuntu Sans,Hasklug Nerd Font 11"; } element { children: [element-text]; } element-text { padding: 0px 0px 0px 7px; }'

DEV="$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
    | awk -F: '$2=="wifi" {print $1; exit}')"
if [[ -z "$DEV" ]]; then
    "$notify" -t 2500 'Wi-Fi' 'No Wi-Fi device found'
    exit 0
fi

# nmcli -t splits fields on ':' and escapes colons inside fields as '\:';
# split on unescaped ones, one field per line.
cols() {
    local row=$1 cur='' ch
    for ((i = 0; i < ${#row}; i++)); do
        ch="${row:i:1}"
        if [[ $ch == '\' && ${row:$((i + 1)):1} == ":" ]]; then
            cur+=':'; ((i++))
        elif [[ $ch == ":" ]]; then
            printf '%s\n' "$cur"; cur=''
        else
            cur+="$ch"
        fi
    done
    printf '%s\n' "$cur"
}

# Networks as "signal<TAB>ssid<TAB>security<TAB>in-use", sorted by signal,
# deduped by SSID keeping the strongest (the same AP usually shows twice,
# 2.4 and 5 GHz bands), hidden APs (empty SSID) dropped.
networks() {
    nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list ifname "$DEV" \
        2>/dev/null |
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        mapfile -t f < <(cols "$row")
        [[ ${#f[@]} == 4 && -n "${f[1]}" ]] || continue
        printf '%s\t%s\t%s\t%s\n' "${f[2]}" "${f[1]}" "${f[3]}" "${f[0]}"
    done \
    | sort -t $'\t' -k1,1rn \
    | sort -s -t $'\t' -k2,2 -u \
    | sort -t $'\t' -k1,1rn
}

radio="$(nmcli radio wifi 2>/dev/null)" # enabled / disabled

types=() labels=() glyphs=() net_ssid=() net_sec=() net_inuse=()
if [[ "$radio" == enabled ]]; then
    glyphs+=($''); labels+=('Disable Wi-Fi'); types+=(toggle)
    # background rescan: benefits the next open of this menu
    nmcli device wifi rescan >/dev/null 2>&1 &
    {
        mapfile -t nets < <(networks)
        for row in "${nets[@]}"; do
            IFS=$'\t' read -r sig ssid sec inuse <<<"$row"
            if [[ "$inuse" == '*' ]]; then
                glyphs+=($'') # check: currently connected
            elif [[ -n "$sec" ]]; then
                glyphs+=($'') # lock
            else
                glyphs+=($'') # unlock: open network
            fi
            labels+=("${ssid}   ${sig}%")
            types+=(net)
            net_ssid+=("$ssid"); net_sec+=("$sec")
        done
    }
else
    glyphs+=($''); labels+=('Enable Wi-Fi'); types+=(toggle)
fi
glyphs+=($''); labels+=('Saved networks…'); types+=(saved)
glyphs+=($''); labels+=('Connection editor…'); types+=(editor)

menu=''
for i in "${!labels[@]}"; do
    menu+="${glyphs[i]}${gap}${labels[i]}\n"
done

choice="$(printf '%b' "${menu}" \
    | rofi -dmenu -i -p 'Wi-Fi' -format i -theme-str "${iconfont}")" \
    || exit 0 # dismissed

case "${types[choice]}" in
    toggle) nmcli radio wifi "$([[ "$radio" == enabled ]] && echo off || echo on)" ;;
    editor) setsid -f nm-connection-editor ;;
    saved)
        mapfile -t names < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null \
            | awk -F: '$2=="802-11-wireless" {print $1}' | sort -f)
        if [[ ${#names[@]} == 0 ]]; then exit 0; fi
        m=''
        for name in "${names[@]}"; do
            m+=$''"${gap}${name}\n"
        done
        pick="$(printf '%b' "${m}" \
            | rofi -dmenu -i -p 'Saved networks' -format i -theme-str "${iconfont}")" \
            || exit 0
        # NM can wait a long time on an out-of-range profile; cap it
        if ! timeout 15 nmcli connection up "${names[pick]}" >/dev/null 2>&1; then
            "$notify" -u critical -t 5000 'Wi-Fi' \
                "Could not connect to ${names[pick]}"
        fi
        ;;
    net)
        ssid=${net_ssid[choice]} sec=${net_sec[choice]}
        # A saved profile connects by name, covering open and
        # password-backed connections alike.
        if nmcli -t -f NAME connection show | grep -Fxq -- "$ssid"; then
            if ! nmcli connection up "$ssid" >/dev/null 2>&1; then
                "$notify" -u critical -t 5000 'Wi-Fi' \
                    "Could not connect to ${ssid}"
            fi
            exit 0
        fi
        # New network: an open one joins directly, a secured one asks for
        # the password first, masked, and re-prompts on failure.
        if [[ -z "$sec" ]]; then
            if ! nmcli device wifi connect "$ssid" ifname "$DEV" >/dev/null 2>&1; then
                "$notify" -u critical -t 5000 'Wi-Fi' \
                    "Could not connect to ${ssid}"
            fi
            exit 0
        fi
        note=''
        for _ in 1 2 3; do
            pw="$(printf '' | rofi -dmenu -password \
                -p "Wi-Fi · ${ssid}${note:+ · ${note}}" -theme-str "${iconfont}")" \
                || exit 0
            # the password briefly transits as an nmcli argument (ps) —
            # accepted for a single-user session, same as nmcli's own
            # helpers; stderr is never echoed wholesale
            if nmcli device wifi connect "$ssid" password "$pw" \
                    ifname "$DEV" >/dev/null 2>&1; then
                exit 0
            fi
            note='wrong password, try again'
        done
        "$notify" -u critical -t 5000 'Wi-Fi' "Could not connect to ${ssid}"
        ;;
esac