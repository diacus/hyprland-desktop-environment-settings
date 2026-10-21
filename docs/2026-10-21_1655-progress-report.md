# Progress report — Hyprland desktop environment

- Date: 2026-10-21, 16:55
- Status: quick-settings widgets for volume / Wi-Fi / Bluetooth complete and
  smoke-tested; not deployed or committed
- Host: MacBook Pro 13" 2017 · Ubuntu 26.04.1 · Hyprland 0.53.3 · Waybar 0.15 · rofi 2.0

## What has been done

### 1. Widget popups replace GUI-app launches

The waybar `pulseaudio`, `network` and `bluetooth` widgets only launched full
editors (`pavucontrol`, `nm-connection-editor`, `blueman-manager`) on click,
and the XF86 volume keys changed sound with no feedback. Now, after a refactor
plan agreed with the user:

- **Volume** (click) → GTK3 panel under the bar (`scripts/volume-popup.py`,
  cloned from `calendar-popup.py`): default-sink slider + mute (pamixer — what
  the keybinds already use), output picker and per-app stream sliders/mute
  (wpctl; pamixer sees no streams and cannot switch defaults, pactl is absent).
  One-second poll keeps sliders in sync; `wpctl status` is parsed lazily and
  hides the Output/Applications sections on failure. Right-click still opens
  pavucontrol.
- **Volume OSD** (XF86 keys) → the same script with `osd`: transient centered
  overlay (`volume-popup.py osd`, wrapper `volume-popup.sh osd` respawned per
  keypress), fades after 2 s. Window rule `volume-osd` is `no_focus` so keys
  keep repeating while a game holds the keyboard; mic mute gets a dunstify
  indicator (`volume-mic-osd.sh`).
- **Wi-Fi** (click) → rofi dmenu (`scripts/network-menu.sh`): radio toggle,
  visible networks (signal-sorted, deduped per SSID by strongest), lock/check
  Nerd Font glyph rows dispatched by index (powermenu.sh recipe), connect with
  masked `rofi -dmenu -password` prompt (3 tries), saved networks submenu,
  nm-connection-editor one row away. Device is derived from `nmcli` (removes
  the hardcoded `wlp2s0` from waybar's module too). Right-click still opens
  nm-connection-editor.
- **Bluetooth** (click) → rofi dmenu (`scripts/bluetooth-menu.sh`): power
  toggle with the `rfkill unblock` chain before `bluetoothctl power on`
  (a soft-blocked controller ignores bluetoothctl alone; this host's hci0 is
  rfkill-blocked), connected/paired device connect-disconnect rows, 8 s
  discovery round + pair/trust/connect, blueman manager as a row. All
  bluetoothctl calls are single-shot non-interactive. Right-click keeps blueman.

### 2. Config plumbing

- `waybar/config.jsonc`: three `on-click` swaps + `on-click-right` fallbacks.
- `hypr/00-variables.conf`: `$volumePopup`, `$volumeOsd`.
- `hypr/50-keybinds.conf`: volume (+ALT) binds chain the OSD; mic mute chains
  the mic indicator.
- `hypr/70-windows.conf`: `volume-popup` (focusable, like calendar-popup) and
  `volume-osd` (`no_focus`, `center`, `pin`) rules; no `match:size` (still not
  available in 0.53).
- `README.org`: new scripts in the layout tree, `wireplumber` in Packages
  (provides `wpctl`), keybinding table mentions the OSD and widget popups.

## Verified this session

- `Hyprland --verify-config` → config ok; waybar JSONC parses; `bash -n` and
  `py_compile` clean on all new scripts.
- `wpctl status` parser pinned against live output (idle streams and channel
  fragments of stream rows are dropped; `[MUTED]` handled).
- Both menus exercised through a rofi shim (capture + dismiss): network rows
  match `nmcli device wifi list` (dedup, signal sort, in-use check glyph,
  Wi-Fi-off minimal menu); powered-on bluetooth rows align types/devs arrays
  (bug found and fixed there: `bt_devices` kept the MAC column).
- OSD/panel ran in the live session without crashing (self-fade + focus-close
  path not interactively exercised); pamixer ±5% roundtrip verified against
  `wpctl`.

## Known quirks added

- `devs` arrays in the bluetooth menu reserve an empty slot per non-device row
  so `${devs[choice]}` stays index-aligned with `${types[choice]}`.
- The wifi password transits briefly as an `nmcli` argument (`ps`); accepted
  for a single-user session, stderr never echoed.
- rofi `-password` masks input but keeps the same dmenu theme/font quirks as
  the other menus (Nerd Font glyphs as text, upstream icon-drop bug).

## Next

Deploy (`bash scripts/install.sh`), then interactively: slider drags, output
switch, connect to a secured AP, bluetooth power-on/pair round, and OSD during
keyed repeats with focus kept in an app.

## Addendum (same day, after deploy)

The user reported the volume panel (and calendar popup) rendering nearly
transparent over the blurred backdrop. Screenshot inspection showed the CSS
window background was never painted: `set_app_paintable(True)` tells GTK the
app draws the window itself, and with no draw handler the CSS background is
silently skipped — only child widgets are visible over a fully transparent
window. Fix: keep the RGBA visual (rounded corners) but do not set
app-paintable, and match rofi's exact window color (`#2e3440F0` =
`rgba(46, 52, 64, 0.94)`); applied to volume-popup.py (panel + OSD) and
calendar-popup.py, verified with before/after screenshots in the live
session.

Theming made theme-agnostic afterwards: a one-line `theme` file at the repo
root names the active theme (`nord`), whose data lives in `themes/nord/` —
`popup-style.css` (GTK popups; the calendar headline accent also moved there
from a hardcoded markup span), `waybar.css` (was `waybar/style.css`) and
`rofi.rasi` (was `rofi/nord.rasi`; `rofi/config.rasi` now says
`@theme "theme"`). The deploy copies the tree to `~/.config/hypr/themes/`,
leaves the `theme` marker for the runtime-resolving widget scripts, and
copies the active theme into the fixed per-daemon slots (waybar, rofi)
AFTER the config trees (a whole-tree clear() rm -rf's its destination when
it was backed up before, which had erased an earlier slot file — slots go
last; and waybar/rofi now deploy file-by-file so the slot files never make
a tree diff trigger a dir backup). Widget code carries no colors; popups
unstyled + warn when theme data is missing. Verified: installs fully
idempotent (21/21 "current"), popups and `rofi -dump-theme` resolve the
theme, panel/calendar screenshots unchanged.