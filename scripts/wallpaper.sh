#!/usr/bin/env bash
# Applies the session wallpaper through hyprpaper's IPC.
# The image comes from HYPRLAND_WALLPAPER_PATH, set per machine in
# ~/.config/hypr/local.conf; the Nord gradient is the fallback default.
# Started right after the hyprpaper daemon in 60-autostart.conf, and safe to
# re-run to change the wallpaper live (hyprctl hyprpaper is a hot swap).
set -euo pipefail

wp="${HYPRLAND_WALLPAPER_PATH:-}"
# fall back to the machine's local.conf (env vars apply at session start
# only; this lets local.conf changes take effect on a plain re-run)
if [[ -z "${wp}" && -f "${HOME}/.config/hypr/local.conf" ]]; then
    line="$(grep -E '^[[:space:]]*env = HYPRLAND_WALLPAPER_PATH,' "${HOME}/.config/hypr/local.conf" | head -1)"
    wp="${line#*,}"
fi
wp="${wp:-${HOME}/.config/hypr/wallpapers/nord-gradient.png}"
# local.conf holds hyprlang-style paths: expand a leading ~ like hyprlang does
wp="${wp/#\~/${HOME}}"
[[ -f "${wp}" ]] || { echo "wallpaper missing: ${wp}" >&2; exit 1; }

# wait for the daemon's socket (hyprpaper starts just before us)
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
# shells without the compositor env (manual runs): discover the newest
# instance and export what hyprctl needs
[[ -z "${sig}" ]] && {
    sig="$(ls -t "${XDG_RUNTIME_DIR}/hypr" 2>/dev/null | head -1)"
    export HYPRLAND_INSTANCE_SIGNATURE="${sig}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
}
for _ in $(seq 1 50); do
    if [[ -n "${sig}" && -S "${XDG_RUNTIME_DIR}/hypr/${sig}/.hyprpaper.sock" ]]; then
        break
    fi
    sleep 0.2
done

# empty monitor = every output
hyprctl hyprpaper wallpaper ",${wp},cover"