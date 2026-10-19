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

install_tree "${repo}/scripts"     "${conf}/hypr/scripts"     755
install_tree "${repo}/wallpapers"  "${conf}/hypr/wallpapers"  644
install_tree "${repo}/waybar"      "${conf}/waybar"           644
install_tree "${repo}/rofi"        "${conf}/rofi"             644
install_tree "${repo}/dunst"       "${conf}/dunst"            644

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