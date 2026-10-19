# Progress report — Hyprland desktop environment

- Date: 2026-10-16, 10:52
- Status: draft configuration complete and validated; not yet deployed or committed
- Host: MacBook Pro 13" 2017 · Ubuntu 26.04.1 · Hyprland 0.53.3 · Waybar 0.15 · rofi 2.0

## What has been done

### 1. Package inventory (complete)

Audited the system against the Hyprland ecosystem and produced a package list;
the user then installed everything:

- **Installed before**: `hyprland`, `kitty`, `pavucontrol`, `wl-clipboard`,
  `libnotify-bin` (notify-send), `xdg-desktop-portal-hyprland`,
  `xdg-desktop-portal-gtk`, `nm-connection-editor`, `btop`, `fastfetch`.
- **Installed this session**: `hyprlock`, `hypridle`, `hyprpaper`,
  `hyprpolkitagent`, `waybar`, `dunst`, `rofi`, `grim`, `slurp`,
  `brightnessctl`, `playerctl`, `pamixer`, `blueman`,
  `network-manager-gnome` (nm-applet), `qt6ct`.
- **Deliberately skipped**: `wofi` (rofi is better maintained), `mako`
  (dunst fits better), `swww`/`swappy`/`wlogout` (not in Ubuntu repos; hyprpaper
  and rofi cover the need). `grimblast` is not packaged in Ubuntu — a local
  script fills its role instead.

### 2. Repository layout (created this session)

```
hypr/          compositor + companion daemons
├── hyprland.conf       entry point; sources the modules below in order
├── 00-variables.conf   programs ($terminal, $menu…), Nord colour palette
├── 10-monitors.conf    wildcard monitor rule + persistent workspaces 1-6
├── 20-env.conf         environment variables (portals, Qt theming, Wayland)
├── 30-input.conf       keyboard + MacBook trackpad (natural scroll, clickfinger)
├── 40-looknfeel.conf   gaps, borders, Nord colours, dwindle layout, animations
├── 50-keybinds.conf    every keybinding (see README table)
├── 60-autostart.conf   waybar, dunst, hyprpaper, hypridle, polkitagent,
│                       nm-applet, blueman-applet, wl-paste clipboard sync
├── 70-windows.conf     window rules (Hyprland 0.53 named-block syntax)
├── hyprlock.conf       lock screen: blurred screenshot + clock + input field
├── hypridle.conf       ladder: dim 3 min → DPMS off 5 min → suspend 15 min
└── hyprpaper.conf      wallpaper

waybar/        config.jsonc + Nord stylesheet
rofi/          config.rasi + nord.rasi theme (drun / run / window modes)
dunst/         dunstrc with Nord urgency colours
scripts/       screenshot.sh (area/full/window → clipboard + notify)
               mediabar.sh (waybar media widget data)
               live-test.sh (nested test with isolated throwaway HOME)
               setup-symlinks.sh (idempotent deploy into ~/.config, backs up once)
wallpapers/    nord-gradient.png (generated placeholder; replace at will)
README.org     layout map, deploy steps, nested-session testing, keybindings (orgmode)
```

### 3. Requirements coverage

| Requirement | Implementation |
| --- | --- |
| Application launcher | rofi drun on Super+D |
| Terminal / arbitrary program | Super+Return / Super+R (rofi run mode) |
| Battery, network, sound, bluetooth | waybar modules with Nord states |
| Keyboard layout selector | `hyprland/language` module, click cycles layout |
| Autostart apps | `60-autostart.conf` exec-once block |
| Virtual desktops | workspaces 1-10, persistent 1-6, swipe gesture |
| Clock and calendar | waybar clock with popup calendar tooltip |
| Notifications | dunst (Nord-themed) + libnotify already present |
| Access to running apps | rofi window mode on Super+Tab + waybar window title |
| Nordic look and feel | Nord palette carried through all four config families |
| No GNOME defaults | kitty, rofi, dunst, pamixer…; nautilus kept (see open items) |

### 4. Validation performed

- Shell scripts pass `bash -n`; screenshot, media and deploy scripts executable.
- `waybar` JSON parses (JSONC comments stripped for the check).
- `dunst` `dunstrc` parses with **no warnings** (fixed legacy `offset`/`height`
  syntax; `gap` → `gap_size`; dropped invented icon paths in favour of
  `icon_theme = Nordzy`).
- `rofi` config and theme parse (fixed the deprecated `theme:` key → `@theme "nord"`).
- `hypridle` registers all three timeout listeners correctly (compositor
  binding error is expected while running under GNOME).
- Cross-check: every file referenced by `source =`, every script referenced by
  binds, and every binary invoked by the configs is present on the system.
- `live-test.sh` dry-verified with a stub `Hyprland`: HOME/XDG dirs point at
  the throwaway tree, the repo copy is laid out at the right path shape
  (all 8 sourced `source =` files resolve), argv passthrough works, and the
  tree is removed on exit by default (`--keep` preserves it for post-mortem).
- First nested live-test attempt failed: `70-windows.conf` used two rule keys
  absent from Hyprland 0.53 (`match:size`, `ontop`); size matching is an open
  upstream feature request (hyprwm/Hyprland#13106). The offending block was
  removed; `Hyprland --verify-config` now reports *config ok*.
- `live-test.sh` gains a `--verify-config` pre-launch lint (fails fast without
  flashing a window) and log capture: nested run output goes to a log inside
  the tree; on failure the tail is printed and a copy kept in
  `/tmp/hyprlive-last.log` (Hyprland's runtime log dies with the instance).
- Live-test round 2: the "missing packages" popups diagnosed via the runtime
  log (`debug { disable_logs = false }` was needed — Hyprland silences its
  own log by default). Root cause: `hyprland-dialog`, part of
  `hyprland-qtutils`, absent from PATH; Hyprland pops a notification per
  ANR-manager attempt. Fix: add `hyprland-qtutils` to the apt list (0.1.5 in
  Ubuntu repos). Separately, waybar crashed at startup on `//` comments in
  `style.css` (GTK CSS forbids them) — converted to `/* */`; verified live by
  launching waybar against the still-open nested instance (layer surface
  attached, all modules loaded).
- Live-test round 3: remaining popup "started without start-hyprland…"
  silenced with `misc:disable_watchdog_warning = true` (correct for nested
  debug runs; a real GDM session goes through start-hyprland). Probe instance
  confirmed: watchdog popup gone, no `hyprland-dialog` errors, waybar layer
  surface created. Nested test environment is now clean.
- Live-test gap found and fixed: the throwaway home never had the config
  installed, so Hyprland silently *generated a stock config* and the
  `--verify-config` run (whose verdict went to the deleted log) validated
  Hyprland's defaults, not this repo. `live-test.sh` now installs the config
  into the fake home by reusing `setup-symlinks.sh` under HOME=fake, and
  passes `--verify-config` through in the foreground so the verdict lands on
  the terminal. All three paths (verify, launch, lint-abort) stub-tested.

## Open items

1. **Deployment not run** — `scripts/setup-symlinks.sh` has not been executed;
   `~/.config` still holds only Ubuntu's autogenerated `hyprland.conf`.
2. **File manager** — `$fileManager = nautilus` (a GNOME app; the only option
   installed). Suggested alternative: `sudo apt install thunar` and change the
   single variable in `hypr/00-variables.conf`.
3. **Missing package** — ~~`hyprland-qtutils`~~ resolved during live testing
   (user installed it; the nested probe shows zero `hyprland-dialog` errors).
3. **Monitor pinning** — ~~wildcard monitor rule~~ resolved in the first real
   session: output is `eDP-1` (Apple Color LCD); pinned as
   `monitor = eDP-1, 2560x1600, 0x0, 1.67` with the wildcard as fallback.
   Rationale: Hyprland's `auto` scale initially picked 2.00 → a 1280x800
   logical desktop that read as "low resolution"; 1.67 restores the GNOME
   density. Applied live via the config auto-reload.
4. **Wallpaper** — currently the generated Nord gradient; drop any picture
   into `wallpapers/` and update `hyprpaper.conf` to taste.
5. **Everything uncommitted** — following the project restriction, no commits
   have been made; the user will commit.

## Suggested next steps

1. `scripts/live-test.sh` from a GNOME terminal: run the isolated nested test
   before any real deployment; watch out for the Super-key caveat (README).
2. Optionally deploy to the real home with `scripts/setup-symlinks.sh`, log
   out of GNOME, pick the Hyprland session.
3. Sanity-check in the first session: waybar renders, `hyprctl monitors` to pin
   the display, screenshot script and lock/unlock round-trip.
4. Pin the monitor, swap the wallpaper, decide on thunar.
5. Commit in two chunks:
   - `Add Hyprland compositor config with Nord palette`
   - `Add waybar, rofi, dunst support files and deploy script`