#!/usr/bin/env bash
# Session menu (rofi dmenu): lock, logout, suspend, reboot, power off.
#   Used by the waybar session widget and the session keybind.
#   Dismissing the menu or the confirm prompt does nothing.
#
#   Icons are Nerd Font glyphs rendered as text (the all-the-icons trick).
#   Image icons are not usable here: rofi 2.0's async icon fetcher on
#   Wayland silently drops most icon paints in dmenu mode (upstream
#   #2322/#2165), while glyphs are laid out synchronously with the text.
#   Needs a Nerd Font installed (the font family is joined after the UI
#   font below so missing fonts fall back gracefully to name-only rows).
set -euo pipefail

labels=( 'Lock screen' 'Logout' 'Suspend' 'Reboot' 'Power off' )
# Nerd Font (Font Awesome block): lock, sign-out, moon, refresh, power
glyphs=( $'\uf023' $'\uf08b' $'\uf186' $'\uf021' $'\uf011' )
# systemctl verb for the destructive rows: "power off" is not a verb.
verbs=( '' '' '' reboot poweroff )

# Geometry mirrors the apps menu: rofi reserves a 1em icon slot + 14px
# spacing before row texts; here the glyph plays the icon, so it is inset
# 7px into the text widget (image icons carry ~4-6px transparent margins)
# and the label follows after 2 en + 1 thin space (~17.6px ~ the spacing
# minus the ink), landing both on the columns the other menus use.
gap=$'\u2002\u2002\u2009'
menu=''
for i in "${!labels[@]}"; do
    menu+="${glyphs[i]}${gap}${labels[i]}\n"
done

# The row font falls back to a Nerd Font just for the glyphs (rofi picks
# the fallback per codepoint; the UI font stays first). With show-icons on,
# dmenu rows reserve the (image) icon slot even with none set — that reads
# as a blank column next to the glyph, so the icon widget is dropped here
# and the glyph takes its place. The dispatch uses the row index
# (-format i), so the glyphs never leak into the choices.
iconfont='* { font: "Ubuntu Sans,Hasklug Nerd Font 11"; } element { children: [element-text]; } element-text { padding: 0px 0px 0px 7px; }'

choice="$(printf '%b' "${menu}" \
    | rofi -dmenu -i -p 'Session' -format i -theme-str "${iconfont}")" \
    || exit 0 # dismissed

# Destructive rows confirm through a GTK question dialog (zenity), the same
# box GNOME's own power-off prompt uses: a title, an explanatory message and
# explicit [Cancel] [Action] buttons. Escape or closing the dialog cancels,
# and so does any dismissal, like the rofi menus above.
confirm() {
    local title=$1 text=$2 action=$3
    zenity --question --title "${title}" --text "${text}" \
        --ok-label "${action}" --cancel-label 'Cancel' --no-wrap
}

case "${choice}" in
    0) exec hyprlock ;;
    1) exec hyprctl dispatch exit ;;
    2) exec systemctl suspend ;;
    3 | 4)
        # Destructive and reachable by keybind: confirm first.
        if ! confirm "${labels[choice]^}" \
            "Are you sure you want to ${labels[choice],} now?" \
            "${labels[choice]^}"; then
            exit 0
        fi
        exec systemctl "${verbs[choice]}"
        ;;
esac