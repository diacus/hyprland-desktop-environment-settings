#!/usr/bin/env bash
# Install the configuration from this repo into ~/.config as regular files.
# The deployed settings are real copies, valid whatever happens to the
# repository: moving or renaming the checkout, or deleting it, leaves the
# desktop working.
#
# Idempotent: unchanged files are skipped, changed ones are replaced; a
# foreign file met at a target is backed up once (name.rp-original) and never
# overwritten twice. Old symlink-style deployments are upgraded in place.
#
# install(1) sets the modes: 644 for config and data, 755 for the scripts,
# which hyprland binds and waybar exec by direct path. The repo keeps the
# scripts non-executable; run this file as:
#
#     bash scripts/install.sh
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
conf="${HOME}/.config"

back_up() {
    local dst="${1}"
    local bak="${dst}.rp-original"
    if [[ -e "${bak}" || -L "${bak}" ]]; then
        mv "${dst}" "${bak}-${RANDOM}"
    else
        mv "${dst}" "${bak}"
    fi
    mkdir -p "$(dirname "${dst}")"
}

# do src and dst resolve to identical content? (works for files and trees;
# mismatched kinds simply compare as different)
same_content() {
    local src="${1}" dst="${2}"
    if [[ -d "${src}" && -d "${dst}" ]]; then
        diff -r -q "${src}" "${dst}" >/dev/null 2>&1
    elif [[ -f "${src}" && -f "${dst}" ]]; then
        cmp -s "${src}" "${dst}"
    else
        return 1
    fi
}

# make room at dst for a fresh copy of src: absent -> nothing; symlink -> an
# old-style deployment worth nothing beyond its content; a real file or tree
# that differs is preserved once, afterwards it is our own install.
# Returns 0 when dst already matches and no install is needed, 1 when dst
# was cleared and the copy must go in.
clear() {
    local dst="${1}" src="${2}"
    if [[ ! -e "${dst}" && ! -L "${dst}" ]]; then
        return 1  # nothing there yet: a copy must go in
    fi
    if [[ -L "${dst}" ]]; then
        if same_content "${src}" "${dst}" 2>/dev/null; then
            rm -f "${dst}"
        else
            back_up "${dst}"
        fi
    elif same_content "${src}" "${dst}"; then
        return 0  # already up to date, skip the churn
    elif [[ -e "${dst}.rp-original" || -L "${dst}.rp-original" ]]; then
        rm -rf "${dst}"  # our previous install, already backed up once
    else
        back_up "${dst}"
    fi
    return 1
}

# copy one file (install(1) sets the mode)
install_file() {
    local mode="${1}" src="${2}" dst="${3}"
    if clear "${dst}" "${src}"; then
        echo "current   ${dst}"
    else
        install -D -m "${mode}" "${src}" "${dst}"
        echo "installed ${dst}"
    fi
}

# copy a whole tree, file by file, mapping repo-relative paths across
install_tree() {
    local src="${1}" dst="${2}" mode="${3}" f rel
    if clear "${dst}" "${src}"; then
        echo "current   tree ${dst}"
        return 0
    fi
    while IFS= read -r -d '' f; do
        rel="${f#"${src}"/}"
        install -D -m "${mode}" "${f}" "${dst}/${rel}"
    done < <(find "${src}" -type f -print0)
    echo "installed tree ${dst}"
}

for f in hypr/*.conf; do
    install_file 644 "${repo}/${f}" "${conf}/${f}"
done

# Theme: the one-line `theme` file at the repo root names the active
# theme; its data lives in themes/<name>/ (popup-style.css, waybar.css,
# rofi.rasi). The tree and the marker deploy under ~/.config/hypr so the
# scripts resolve the theme at runtime; the per-daemon data slots (read
# by consumers with a fixed filename) get a copy of the active theme.
# Switching theme: edit `theme`, rerun this script.
active="$(head -n1 "${repo}/theme" | tr -d '[:space:]')"
[[ -n "${active}" && -d "${repo}/themes/${active}" ]] || {
    echo "error: repo theme '${active:-<empty>}' has no themes/${active}/ data" >&2
    exit 1
}

install_file 644 "${repo}/theme" "${conf}/hypr/theme"
install_tree "${repo}/themes" "${conf}/hypr/themes" 644

install_tree "${repo}/scripts"    "${conf}/hypr/scripts"    755
install_tree "${repo}/wallpapers" "${conf}/hypr/wallpapers" 644
# migration (2026-10-21): popup theme data moved from the scripts dir to
# themes/ (this previously-deployed sibling is stale now)
rm -f "${conf}/hypr/scripts/popup-style.css"
install_tree "${repo}/dunst"      "${conf}/dunst"           644

# waybar and rofi deploy FILE-BY-FILE (not as trees): their deployed dirs
# also carry the theme slots below, and a whole-tree clear() would move
# the dir aside (and rm -rf + recopy it) on every run the moment the slot
# files make it differ from the repo tree
for f in waybar/*; do
    install_file 644 "${repo}/${f}" "${conf}/${f}"
done
for f in rofi/*; do
    install_file 644 "${repo}/${f}" "${conf}/${f}"
done

# the per-daemon theme slots, copies of the active theme (the consumer
# reads a fixed filename); a theme switch replaces the slot content on
# the next deploy (backed up once as *.rp-original, like any file change)
install_file 644 "${repo}/themes/${active}/waybar.css" "${conf}/waybar/style.css"
install_file 644 "${repo}/themes/${active}/rofi.rasi"  "${conf}/rofi/theme.rasi"

# the per-machine settings file: created once from a template, never touched
# again (it is host data, not repo data)
local_conf="${conf}/hypr/local.conf"
if [[ ! -e "${local_conf}" ]]; then
    cat > "${local_conf}" <<'EOF'
# Per-machine Hyprland settings - this file is host data, not managed by the
# repo after creation. The wallpaper path used by the session:
#env = HYPRLAND_WALLPAPER_PATH,/path/to/your/wallpaper.jpg
EOF
    echo "created template ${local_conf}"
fi

echo "done. Log out of the current session and pick the Hyprland one."