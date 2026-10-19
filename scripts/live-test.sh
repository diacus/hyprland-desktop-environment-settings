#!/usr/bin/env bash
# live-test.sh - run the desktop inside the current session with an isolated HOME
#
# Creates a throwaway directory, installs the settings into a fake HOME the
# same way a real deployment does, and launches Hyprland with HOME and the
# XDG dirs pointing at it. The real ~/.config is never touched, and the
# throwaway tree is deleted when the test session ends.
#
#   usage: live-test.sh [--keep] [hyprland args]
#     --keep   do not delete the tree on exit (path is printed at startup)
#   Quick config check without launching: Hyprland --verify-config -c FILE
#
# The installed settings are a /snapshot/ taken at launch: files edited in
# this repo while the test runs do not propagate; rerun for a fresh copy.
set -euo pipefail

keep=false
hypr_args=()
for arg in "$@"; do
    case "${arg}" in
        -h|--help)
            sed -n '2,11p' "${0}" && exit 0 ;;
        --keep)
            keep=true ;;
        *)
            hypr_args+=("${arg}") ;;
    esac
done

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/hyprlive-XXXXXX")"

cleanup() {
    # If we were interrupted mid-run, take the nested compositor with us.
    kill "${child:-}" 2>/dev/null || true
    if "${keep}"; then
        echo "kept test home: ${tmp}"
    else
        chmod -R u+w "${tmp}" 2>/dev/null
        rm -rf "${tmp}"
    fi
}
trap cleanup EXIT INT TERM

# Standard dirs the desktop tools expect in a home
fake_home="${tmp}/home"
mkdir -p "${fake_home}/.config" \
         "${fake_home}/Pictures/Screenshots" \
         "${fake_home}/.cache" \
         "${fake_home}/.local/share"

# Install the settings into the fake home, exactly the way a real deployment
# does. Without this Hyprland silently generates a stock config and the test
# proves nothing.
env HOME="${fake_home}" bash "${repo}/scripts/install.sh" >/dev/null

echo "isolated home: ${fake_home}"
if "${keep}"; then
    echo "real home is untouched; the test tree is kept on exit"
else
    echo "real home is untouched; the test tree is removed on exit"
fi

# HOME drives path expansion inside the compositor config (~ = fake home here);
# the XDG dirs are overridden too in case the ambient session exports them.
export HOME="${fake_home}"
export XDG_CONFIG_HOME="${fake_home}/.config"
export XDG_DATA_HOME="${fake_home}/.local/share"
export XDG_STATE_HOME="${fake_home}/.local/state"
export XDG_CACHE_HOME="${fake_home}/.cache"
export XDG_PICTURES_DIR="${fake_home}/Pictures"

# Lint first: a config error aborts with no window flashing. An explicit
# --verify-config request is answered in the foreground, keeping the output
# on the terminal instead of leaving it in the throwaway log (and in verify
# mode no session starts, so there is nothing to run afterwards).
config="${fake_home}/.config/hypr/hyprland.conf"
if [[ " ${hypr_args[*]:-} " == *" --verify-config "* ]]; then
    Hyprland "${hypr_args[@]}"
    exit $?
elif ! Hyprland --verify-config --config "${config}" >/dev/null 2>&1; then
    echo "config errors — aborting before launch:"
    Hyprland --verify-config --config "${config}" 2>&1 | grep -vE '^\s*(\[.*\]:)? *\[?[0-9;]*m?DEBUG'
    exit 1
fi
# Console output goes to a log inside the tree (its own runtime log dies with
# the instance, and a clean exit deletes it).
Hyprland "${hypr_args[@]}" >"${tmp}/hyprland.log" 2>&1 &
child=$!
child_rc=0
printf 'live log: %s\n' "${tmp}/hyprland.log"
wait "${child}" || child_rc=$?
if (( child_rc != 0 )); then
    echo "Hyprland exited with rc=${child_rc}; last 30 log lines:"
    tail -n 30 "${tmp}/hyprland.log"
    if ! "${keep}"; then
        cp "${tmp}/hyprland.log" /tmp/hyprlive-last.log
        echo "full log kept at /tmp/hyprlive-last.log"
    fi
fi
exit "${child_rc}"