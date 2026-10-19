# AI assisted Hyperland configuration

This folder hosts the developed desktop environment built around Hyprland,
written in a reproducible way. Quoting Hyprland wiki itself: *Hyprland is not
meant to be a full and user-friendly Desktop Environment. In a nutshell, it's
a set of tools to allow you to create your own Desktop Environment.*

## Current state of the environment

A working, Nord-themed first draft exists and runs in a real session:

- `hypr/` compositor and companion daemons (`hyprland.conf` entry point,
  ordered modules `00-` to `70-`, plus `hyprlock`/`hypridle`/`hyprpaper`)
- `waybar/` top bar (workspaces, window title, clock, media, tray, layout
  selector, volume, bluetooth, network, battery)
- `rofi/` launcher (Super+D), window switcher (Super+Tab) and run mode
- `dunst/` notifications
- `scripts/` screenshot helper, waybar widget data scripts, deploy and
  live-test harnesses
- `docs/` progress reports (timestamped)
- `README.org` user-facing map, keybindings and deploy steps

Covered requirements: application launcher, terminal/arbitrary-program
shortcuts, status widgets (battery, network, sound, bluetooth, keyboard
layout, autostart, virtual desktops, clock+calendar, notifications), running
application access (rofi window mode + bar). Suggestions for more widgets or
apps go through the user before implementation.

## Deployment and testing

- Install to the real home: `bash scripts/install.sh` (copies into
  `~/.config`; idempotent, backs up foreign files once; repo scripts stay
  non-executable — `install(1)` sets modes on the deployed copies)
- Live test **without logging out** of the current session:
  `bash scripts/live-test.sh` runs a nested Hyprland with an isolated
  throwaway HOME; a real GDM login goes through `start-hyprland`
- Validate any config instantly: `Hyprland --verify-config --config FILE`

## Known quirks (do not rediscover these)

- hyprpaper on this system is the rewritten 0.8.x (hyprtoolkit daemon): use
  `wallpaper { monitor/path/fit_mode }` blocks; the old `preload =` /
  `wallpaper = ,path` lines fail *silently* (daemon exits after banner).
  Hot-reload: `hyprctl hyprpaper wallpaper '<monitor>,<path>,<fit_mode>'`;
  a config change otherwise needs a daemon restart

- Theming is **shared with GNOME through dconf** and served to GTK apps by
  the xdg-desktop-portal inside Hyprland sessions. Never write
  dconf/gsettings or ~/.config/gtk-*/settings.ini from here; theming for the
  session comes from the portal plus session-scoped env (20-env.conf)

- waybar's strftime `clock` module errors on this build with extended
  `%-tokens` (`chrono format error`) — the date widget is a scripted
  `custom` module instead
- GTK CSS forbids `//` comments in stylesheets; only `/* */`
- Apple SPI keyboard needs
  `/etc/libinput/local-overrides.quirks` (`AttrKeyboardIntegration=internal`)
  or disable-while-typing parses but does nothing
- `hyprland-qtutils` provides `hyprland-dialog` (ANRManager); without it two
  startup notifications appear per session
- On the HiDPI panel (eDP-1, 2560x1600), scale is pinned to 1.67 and XWayland
  apps render 1:1 (`xwayland.force_zero_scaling`); X11 app builds look
  pixelated — prefer native Wayland builds
- Window-rule `match:` class patterns match the *whole* class string, and GTK4
  apps report a flatpak-style app-id (pavucontrol 6.x =
  `org.pulseaudio.pavucontrol`); rules with `$`-anchored bare names silently
  miss them — check `hyprctl clients` for the real class when a dialog tiles
- Submaps are not a context for scoped keybinds on 0.53: keys without a bind
  in the active submap do NOT fall back to the default map, they pass to the
  client (KeybindManager skips binds of other submaps). Per-context behavior
  goes through the non-consuming bind flag (`bindn = , KEY, ...`): the key
  both dispatches and still reaches the focused app

## Default applications

Alternatives to GNOME programs are preferred for defaults; suggest packages
as needed, the user takes care of installing them.

## Portability rule

This project is **system-agnostic**: it is a Hyprland settings project on a
Wayland compositor, and that is the only fixed condition. It must deploy on
any machine that has Hyprland, whatever the OS. When work touches the
config, keep it free of absolute repo paths (deployed config refers only to
`~/.config/hypr`) and distro-specific assumptions; name packages per
distribution rather than assuming one.

## System details (example host snapshot, not a requirement)

```
OS: Ubuntu 26.04.1 LTS (Resolute Raccoon) x86_64
Host: MacBook Pro (13-inch, 2017, Two Thunderbolt 3 ports) (1.0)
Kernel: Linux 7.0.0-38-generic
Display (Color LCD): 2560x1600 @ 1.67x in 13", 60 Hz [Built-in]
WM: Hyprland 0.53.3 (Wayland)
Theme: Yaru [GTK3]
Icons: Yaru [GTK3]
Cursor: Adwaita
Terminal: emacs-pgtk
```

## General guidelines
- suggest commit messages, they should be one-liners under 76 characters

## Strong restrictions

Do not commit any change. User will do

## References

- [Start Here - Hyprland configuration](https://wiki.hypr.land/Configuring/Start/)
- [Hyprland Installation](https://wiki.hypr.land/Getting-Started/Installation/)
- Window rules live under *Configuring* — the wiki URL for that page has been
  unstable (404 at times), so start from the index and navigate
