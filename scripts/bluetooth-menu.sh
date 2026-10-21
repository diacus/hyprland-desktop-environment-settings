#!/usr/bin/env bash
# Bluetooth menu (rofi dmenu): the click action of the waybar bluetooth
# widget. Toggle the adapter power, connect/disconnect paired devices,
# pair new ones after a discovery round, and the full blueman manager one
# click away.
#
# Every bluetoothctl action is a single non-interactive invocation; there
# is no REPL plumbing. Only pin entry or passkey confirmations on the
# device side would need a window — those pairs go through blueman.
#
# Power on may need two steps: a soft-blocked controller (rfkill, common
# on this laptop) stays down no matter what bluetoothctl does, so the
# unblock is chained first. /dev/rfkill is only writable by its group;
# when it is not, power toggling still goes through bluetoothctl alone.
#
#   Icons are Nerd Font glyphs rendered as text and dispatched by row
#   index — see scripts/powermenu.sh for the full rationale (rofi 2.0 on
#   Wayland silently drops image icons in dmenu mode).
set -euo pipefail

for dep in bluetoothctl rofi; do
    command -v "$dep" >/dev/null 2>&1 || exit 0
done
command -v dunstify >/dev/null 2>&1 && notify=dunstify || notify=notify-send

gap=$'   '
iconfont='* { font: "Ubuntu Sans,Hasklug Nerd Font 11"; } element { children: [element-text]; } element-text { padding: 0px 0px 0px 7px; }'

# Device MAC and alias one per line ("Device F4:4E:FC:62:9A:51 Alias").
bt_devices() { bluetoothctl devices "$@" 2>/dev/null | grep '^Device ' | cut -d' ' -f2-; }
dev_mac()  { echo "${1%% *}"; }
dev_name() { echo "${1#* }"; }
dev_connected() {
    bluetoothctl info "$(dev_mac "$1")" 2>/dev/null | grep -q 'Connected: yes'
}

[[ -n "$(bluetoothctl list 2>/dev/null)" ]] || {
    "$notify" -t 2500 'Bluetooth' 'No Bluetooth controller found'
    exit 0
}

powered="$(bluetoothctl show 2>/dev/null | awk '/^[[:space:]]*Powered:/ {print $2}')" || true
rfkill_ok=false
[[ -w /dev/rfkill ]] && rfkill_ok=true

types=() labels=() glyphs=() devs=()
glyphs+=($''); labels+=("$([[ "$powered" == yes ]] && echo 'Disable Bluetooth' || echo 'Enable Bluetooth')"); types+=(toggle); devs+=('')

# connected first, then the rest of the paired devices
if [[ "$powered" == yes ]]; then
    {
        {
            mapfile -t conns < <(bt_devices Connected)
            for dev in "${conns[@]}"; do
                glyphs+=($''); labels+=("$(dev_name "$dev")   disconnect"); types+=(disconnect)
                devs+=("$dev")
            done
        }
        {
            mapfile -t paired < <(bt_devices Paired)
            for dev in "${paired[@]}"; do
                dev_connected "$dev" && continue # already listed above
                glyphs+=($''); labels+=("$(dev_name "$dev")   connect"); types+=(connect)
                devs+=("$dev")
            done
        }
    }
    glyphs+=($''); labels+=('Pair new device…'); types+=(pair); devs+=('')
fi
glyphs+=($''); labels+=('Bluetooth manager…'); types+=(editor); devs+=('')

menu=''
for i in "${!labels[@]}"; do
    menu+="${glyphs[i]}${gap}${labels[i]}\n"
done

choice="$(printf '%b' "${menu}" \
    | rofi -dmenu -i -p 'Bluetooth' -format i -theme-str "${iconfont}")" \
    || exit 0 # dismissed

case "${types[choice]}" in
    toggle)
        if [[ "$powered" == yes ]]; then
            bluetoothctl power off >/dev/null 2>&1
            if "$rfkill_ok"; then rfkill block bluetooth 2>/dev/null || true; fi
        else
            # a soft-blocked controller ignores bluetoothctl: unblock first
            if "$rfkill_ok"; then rfkill unblock bluetooth 2>/dev/null || true; fi
            sleep 1
            bluetoothctl power on >/dev/null 2>&1 \
                || "$notify" -t 2500 'Bluetooth' 'Could not power on the adapter'
        fi
        ;;
    disconnect)
        mac=$(dev_mac "${devs[choice]}")
        timeout 10 bluetoothctl disconnect "$mac" >/dev/null 2>&1 \
            || "$notify" -t 2500 'Bluetooth' 'Disconnect failed'
        ;;
    connect)
        mac=$(dev_mac "${devs[choice]}")
        timeout 15 bluetoothctl connect "$mac" >/dev/null 2>&1 \
            || "$notify" -u critical -t 4000 'Bluetooth' \
                "Could not connect to $(dev_name "${devs[choice]}") — is it on?"
        ;;
    pair)
        # discover for a bounded round, then show what was found; a pair
        # with PIN/passkey confirmation needs an agent window and belongs
        # in blueman instead
        setsid -f bluetoothctl scan on >/dev/null 2>&1
        sleep 8
        # kill the scan; this script's own command line never matches
        pkill -f 'bluetoothctl scan on' >/dev/null 2>&1 || true
        {
            mapfile -t found < <(bt_devices)
            mapfile -t paired < <(bt_devices Paired)
            menu=''
            for dev in "${found[@]}"; do
                # keep already-paired devices out of the pairing round
                for p in "${paired[@]}"; do
                    [[ "$(dev_mac "$dev")" == "$(dev_mac "$p")" ]] && continue 2
                done
                menu+=$''"${gap}$(dev_name "$dev")\n"
            done
        }
        if [[ -z "${menu:-}" ]]; then exit 0; fi
        pick="$(printf '%b' "${menu}" \
            | rofi -dmenu -i -p 'Pair new device' -format i -theme-str "${iconfont}")" \
            || exit 0
        mapfile -t found < <(bt_devices)
        macs=()
        for dev in "${found[@]}"; do
            for p in "${paired[@]}"; do
                [[ "$(dev_mac "$dev")" == "$(dev_mac "$p")" ]] && continue 2
            done
            macs+=("$(dev_mac "$dev")")
        done
        mac=${macs[pick]}
        if timeout 30 bluetoothctl pair "$mac" >/dev/null 2>&1 \
                && bluetoothctl trust "$mac" >/dev/null 2>&1; then
            timeout 15 bluetoothctl connect "$mac" >/dev/null 2>&1 \
                || "$notify" -t 3000 'Bluetooth' 'Paired; connect failed — is it in range?'
        else
            "$notify" -u critical -t 4000 'Bluetooth' \
                'Pairing failed — PIN-confirmed devices go through blueman'
        fi
        ;;
    editor) setsid -f blueman-manager ;;
esac