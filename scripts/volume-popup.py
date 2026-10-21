#!/usr/bin/env python3
"""Volume popup: sink slider + output picker + per-app streams, GNOME-style.

Clicking the waybar volume widget opens the panel (this script without
arguments). The XF86 volume keybinds run `volume-popup.py osd` instead: a
transient centered overlay showing the new volume that fades away after
~2s and never takes focus (see the volume-osd windowrule in
hypr/70-windows.conf), so the bound keys still work while an app or game
keeps the keyboard.

Backends: pamixer for the default sink (what the keybinds already use) and
wpctl only for what pamixer cannot do — the output list with switching and
the per-application stream volume (pamixer sees no streams, and pactl is
not on this system). The `wpctl status` tree format is owned by
WirePlumber, so it is parsed lazily: a failed or empty parse simply hides
the Output/Applications rows instead of crashing the panel.

Runs GTK3 because it is in the GNOME stack already; no extra packages.
Panel dismissal: focus leave or Escape; the wrapper volume-popup.sh also
kills it on a second click of the widget. The OSD needs no dismissal: it
is unfocused and fades on its own timer.
"""
import json
import os
import re
import subprocess
import sys

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0') # else plain import resolves Gdk 4.0
from gi.repository import Gdk, GLib, Gtk, Pango

# Theme data: the one-line theme file (~/.config/hypr/theme) names the
# active theme, whose data lives in ~/.config/hypr/themes/<name>/ —
# widgets carry no colors (the global setting is owned by the deploy).
CONF_ROOT = os.path.join(os.path.expanduser('~'), '.config', 'hypr')

def load_css():
    """Theme data of the active theme, or b'' (warn + unstyled) if absent."""
    try:
        with open(os.path.join(CONF_ROOT, 'theme')) as fh:
            theme = fh.readline().strip()
    except OSError as err:
        sys.stderr.write(f'warning: theme file missing ({err})\n'
                         'rendering unstyled\n')
        return b''
    path = os.path.join(CONF_ROOT, 'themes', theme, 'popup-style.css')
    try:
        with open(path, 'rb') as fh:
            return fh.read()
    except OSError:
        sys.stderr.write(f'warning: {path} missing, rendering unstyled\n')
        return b''


# waybar geometry: config.jsonc margin-top 6 + height 36, in logical px
BAR_BOTTOM = 42
GAP = 8

# Nerd Font (Font Awesome block): volume high, volume off (muted keeps
# the strike, same glyphs the waybar pulseaudio module uses)
GLYPH = '\uf028'
GLYPH_MUTED = '\uf026'


def run(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True)
    except FileNotFoundError:
        return None


def pamixer(*args):
    r = run('pamixer', *args)
    return r.stdout.strip() if r and r.returncode == 0 else None


# `wpctl status` builds a tree: `│` continuation strokes, section headers
# `├─ Sinks:` / `└─ Streams:`, items `* 55. Name  [vol: 0.43]` (muted items
# instead read `[MUTED]`). Sections live under the top-level `Audio` block;
# the tree layout is WirePlumber-versioned, hence the lazy parse.
ITEM_RE = re.compile(
    r'^\s*(?P<star>\*)?\s*(?P<id>\d+)\.\s+(?P<name>.+?)'
    r'(?:\s+\[(?:vol: (?P<vol>[0-9.]+)\]|(?P<muted>MUTED)\]))?\s*$')


def wpctl_nodes():
    """Audio sinks and streams of `wpctl status` as {id: row}, or empty."""
    sinks, streams = {}, {}
    out = run('wpctl', 'status')
    if out is None or out.returncode != 0: # wpctl missing or unhappy
        return sinks, streams
    in_audio = False
    section = None
    for line in out.stdout.splitlines():
        if re.fullmatch(r'\S+', line): # top-level block: Audio, Video, ...
            in_audio = line == 'Audio'
            section = None
            continue
        if not in_audio:
            continue
        head = re.search(r'[├└]─ (Sinks|Streams):$', line)
        if head:
            section = head.group(1)
            continue
        if re.search(r'[├└]─ \S+:$', line): # any other section ends ours
            section = None
            continue
        m = ITEM_RE.match(re.sub(r'[│]', ' ', line))
        if m and section:
            # streams keep channel fragments (`63. output_FR > ...	[active]`)
            # under their parent row; idle streams carry no [vol] at all —
            # only rows with a volume or a MUTED marker are controllable
            if section == 'Streams' and m['vol'] is None and not m['muted']:
                continue
            target = sinks if section == 'Sinks' else streams
            target[int(m['id'])] = {
                'name': m['name'].strip(),
                'default': m['star'] == '*',
                'vol': int(round(float(m['vol']) * 100)) if m['vol'] else None,
                'muted': m['muted'] is not None,
            }
    return sinks, streams


def transparent_window(window):
    """Rounded corners need an alpha visual before anything is drawn.

    Do NOT set_app_paintable: that tells GTK the app paints the window
    background itself, and with no draw handler the CSS background is
    silently skipped — the window renders fully transparent (this is how
    the first volume panel/calendar looked, see the 2026-10-21 report).
    With the visual alone, GTK paints the CSS background over it.
    """
    screen = window.get_screen()
    visual = screen.get_rgba_visual()
    if visual and screen.is_composited():
        window.set_visual(visual)


class VolPanel(Gtk.Window):
    def __init__(self):
        super().__init__()
        # app_id: Wayland derives it from GLib.set_prgname in main()
        self.set_title('volume-popup')
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_size_request(320, -1)
        self.set_name('volpwin')
        self.get_style_context().add_class('popup')
        # 1em-ish inner padding (GtkWindow ignores CSS padding for child
        # allocation; the GTK border-width mechanism always applies
        self.set_border_width(12)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        transparent_window(self)

        self.muted = False
        self.updating = False       # set while pushing polled values into widgets
        self.combo_updating = False # set while rebuilding the output combo
        self.sink_ids = []          # sink id per combo row
        self.sink_key = None        # (default, ids, names) snapshot; rebuild on change
        self.stream_rows = {}       # stream id -> {'adj': .., 'mute': .., 'updating': ..}

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)

        hdr = Gtk.Box(spacing=6)
        self.icon = Gtk.Label(label=GLYPH)
        self.icon.get_style_context().add_class('glyph')
        title = Gtk.Label(label='Volume')
        self.pct = Gtk.Label()
        hdr.pack_start(self.icon, False, False, 0)
        hdr.pack_start(title, False, False, 0)
        hdr.pack_end(self.pct, False, False, 0)
        box.pack_start(hdr, False, False, 0)

        self.adjust = Gtk.Adjustment(value=0, lower=0, upper=100, step_increment=5,
                                     page_increment=10, page_size=0)
        self.scale = Gtk.Scale.new(Gtk.Orientation.HORIZONTAL, self.adjust)
        self.scale.set_draw_value(False)
        box.pack_start(self.scale, False, False, 0)

        self.mute = Gtk.CheckButton(label='Mute')
        box.pack_start(self.mute, False, False, 0)

        self.out_row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        out_label = Gtk.Label(label='Output')
        out_label.get_style_context().add_class('section')
        out_label.set_halign(Gtk.Align.START)
        self.out = Gtk.ComboBoxText()
        self.out_row.pack_start(out_label, False, False, 0)
        self.out_row.pack_start(self.out, False, False, 0)
        box.pack_start(self.out_row, False, False, 0)

        self.apps_row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        apps_label = Gtk.Label(label='Applications')
        apps_label.get_style_context().add_class('section')
        apps_label.set_halign(Gtk.Align.START)
        self.apps_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.apps_row.pack_start(apps_label, False, False, 0)
        self.apps_row.pack_start(self.apps_box, False, False, 0)
        box.pack_start(self.apps_row, False, False, 0)

        self.add(box)

        self.adjust.connect('value-changed', self.on_volume)
        self.mute.connect('toggled', self.on_mute)
        self.out.connect('changed', self.on_output)
        self.connect('key-press-event', self.on_key)
        self.connect('focus-out-event', self.on_focus_out)
        # position only after the window is mapped and sized (Wayland
        # toplevels cannot place themselves; Hyprland moves it instead)
        GLib.timeout_add(120, self.move_under_the_bar)
        self.poll()
        GLib.timeout_add(1000, self.poll) # streams come and go; keep up

    def on_key(self, _win, event):
        if Gdk.keyval_name(event.keyval) == 'Escape':
            Gtk.main_quit()
        return False

    def on_focus_out(self, _win, _event):
        # the combo popup holds a grab in a separate window; wait with the
        # quit until it is closed (polling refreshes everything after)
        if self.out.get_property('popup-shown'):
            return True
        Gtk.main_quit()
        return True

    def move_under_the_bar(self):
        width, _height = self.get_size()
        if width < 2:
            return True # not realized and sized yet; retry
        mons = json.loads(subprocess.run(
            ['hyprctl', '-j', 'monitors'], capture_output=True,
            text=True).stdout)
        mon = next((m for m in mons if m.get('focused')), mons[0])
        # movewindowpixel works in layout (logical) px: hyprctl reports
        # the mode size, divide by the scale it also reports
        x = mon['x'] + (mon['width'] / mon['scale'] - width) / 2
        y = mon['y'] + BAR_BOTTOM + GAP
        subprocess.run(['hyprctl', 'dispatch', 'movewindowpixel',
                        f'exact {x:.0f} {y:.0f},class:volume-popup'])
        subprocess.run(['hyprctl', 'dispatch', 'focuswindow',
                        'class:volume-popup'])
        return False

    # --- default sink (pamixer) ------------------------------------------

    def on_volume(self, adj):
        if self.updating:
            return
        vol = int(round(adj.get_value()))
        self.pct.set_text(f'{vol}%')
        if self.muted:
            # a drag means intent to hear something: unmute while at it
            pamixer('-u')
            self.muted = False
            self.updating = True
            self.mute.set_active(False)
            self.updating = False
        pamixer('--set-volume', str(vol))

    def on_mute(self, btn):
        if self.updating:
            return
        pamixer('-m' if btn.get_active() else '-u')
        self.refresh_state()

    def refresh_state(self):
        vol = pamixer('--get-volume')
        mute = pamixer('--get-mute')
        if vol is None:
            return
        self.muted = mute == 'true'
        n = int(vol)
        self.updating = True
        if not self.scale.get_state_flags() & Gtk.StateFlags.ACTIVE:
            self.adjust.set_value(n) # never snap back under the user's drag
        self.mute.set_active(self.muted)
        self.updating = False
        self.pct.set_text('muted' if self.muted else f'{n}%')
        ctx = self.icon.get_style_context()
        self.icon.set_text(GLYPH_MUTED if self.muted else GLYPH)
        if self.muted:
            ctx.add_class('muted')
        else:
            ctx.remove_class('muted')

    # --- output picker (wpctl) -------------------------------------------

    def refresh_outputs(self, sinks):
        default = next((i for i, s in sinks.items() if s['default']), None)
        key = (default, tuple(sorted((i, s['name']) for i, s in sinks.items())))
        # rebuild only on a real change and never under an open dropdown
        if key == self.sink_key or self.out.get_property('popup-shown'):
            return
        self.sink_key = key
        self.sink_ids = []
        self.combo_updating = True
        self.out.remove_all()
        for sid, row in sorted(sinks.items(), key=lambda kv: kv[1]['name'].lower()):
            # ● marks the sink that would catch the default routing
            self.out.append_text(('● ' if row['default'] else '   ') + row['name'])
            self.sink_ids.append(sid)
        if default is not None and default in self.sink_ids:
            self.out.set_active(self.sink_ids.index(default))
        self.combo_updating = False
        self.out_row.set_visible(bool(sinks))

    def on_output(self, combo):
        if self.combo_updating:
            return
        idx = combo.get_active()
        if 0 <= idx < len(self.sink_ids):
            run('wpctl', 'set-default', str(self.sink_ids[idx]))

    # --- per-app streams (wpctl) -----------------------------------------

    def refresh_streams(self, streams):
        if set(streams) == set(self.stream_rows):
            # same apps as last tick: only push fresh values in
            for sid, row in streams.items():
                w = self.stream_rows[sid]
                if row['vol'] is not None \
                        and not w['scale'].get_state_flags() & Gtk.StateFlags.ACTIVE:
                    w['updating'] = True
                    w['adj'].set_value(row['vol'])
                    w['updating'] = False
                w['updating'] = True
                w['mute'].set_active(row['muted'])
                w['updating'] = False
            return
        for child in self.apps_box.get_children():
            self.apps_box.remove(child)
        self.stream_rows = {}
        for sid, row in sorted(streams.items(), key=lambda kv: kv[1]['name'].lower()):
            label = Gtk.Label(label=row['name'] or f'stream {sid}')
            label.set_halign(Gtk.Align.START)
            label.set_ellipsize(Pango.EllipsizeMode.END)
            label.set_max_width_chars(18)
            start = 0 if row['muted'] else (row['vol'] or 0)
            adj = Gtk.Adjustment(value=start, lower=0, upper=100, step_increment=5,
                                 page_increment=10, page_size=0)
            scale = Gtk.Scale.new(Gtk.Orientation.HORIZONTAL, adj)
            scale.set_draw_value(False)
            scale.set_size_request(120, -1)
            mute = Gtk.CheckButton()
            mute.set_tooltip_text('Mute')
            mute.set_active(row['muted'])
            state = {'adj': adj, 'scale': scale, 'mute': mute, 'updating': False}
            adj.connect('value-changed', self.on_stream_volume, sid, state)
            mute.connect('toggled', self.on_stream_mute, sid, state)
            srow = Gtk.Box(spacing=6)
            srow.pack_start(label, False, False, 0)
            srow.pack_start(scale, True, True, 0)
            srow.pack_start(mute, False, False, 0)
            self.apps_box.pack_start(srow, False, False, 0)
            self.stream_rows[sid] = state
        self.apps_row.set_visible(bool(streams))
        self.apps_box.show_all()

    def on_stream_volume(self, adj, sid, state):
        if state['updating']:
            return
        run('wpctl', 'set-volume', str(sid), f'{int(round(adj.get_value()))}%')

    def on_stream_mute(self, _btn, sid, state):
        if state['updating']:
            return
        run('wpctl', 'set-mute', str(sid), 'toggle')

    # --- poll loop ---------------------------------------------------------

    def poll(self):
        self.refresh_state()
        sinks, streams = wpctl_nodes()
        self.refresh_outputs(sinks)
        self.refresh_streams(streams)
        return True # keep ticking


class VolOsd(Gtk.Window):
    """Transient keyboard feedback: glyph + progress bar, fades after 2s."""

    def __init__(self):
        super().__init__()
        self.set_title('volume-osd')
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_name('voosd')
        self.get_style_context().add_class('popup')
        self.set_border_width(14)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        transparent_window(self)

        vol = pamixer('--get-volume')
        mute = pamixer('--get-mute') == 'true'
        n = int(vol) if vol else 0

        box = Gtk.Box(spacing=10)
        icon = Gtk.Label(label=GLYPH_MUTED if mute else GLYPH)
        icon.get_style_context().add_class('glyph')
        if mute:
            icon.get_style_context().add_class('muted')
        self.bar = Gtk.ProgressBar()
        self.bar.set_show_text(False)
        self.bar.set_size_request(160, -1)
        self.bar.set_fraction(n / 100)
        self.pct = Gtk.Label(label='muted' if mute else f'{n}%')
        box.pack_start(icon, False, False, 0)
        box.pack_start(self.bar, False, False, 0)
        box.pack_start(self.pct, False, False, 0)
        self.add(box)

        # fade in, then hold for 2s and quit; each key repeat respawns the
        # window (volume-popup.sh osd), which restarts this whole cycle
        self.fade = 0.0
        self.opacity = 0.0 # property, not the deprecated Gtk.Window.set_opacity
        GLib.timeout_add(15, self.fade_in)

    def fade_in(self):
        self.fade = min(1.0, self.fade + 0.1)
        self.opacity = self.fade
        if self.fade < 1.0:
            return True # next step
        GLib.timeout_add_seconds(2, Gtk.main_quit)
        return False


def main():
    if run('pamixer', '--get-volume') is None:
        sys.stderr.write('volume-popup: pamixer (pipewire-pulse) not found\n')
        return 1
    osd = len(sys.argv) > 1 and sys.argv[1] == 'osd'
    GLib.set_prgname('volume-osd' if osd else 'volume-popup')
    win = VolOsd() if osd else VolPanel()
    provider = Gtk.CssProvider()
    provider.load_from_data(load_css())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win.show_all()
    win.present()
    Gtk.main()
    return 0


if __name__ == '__main__':
    sys.exit(main())