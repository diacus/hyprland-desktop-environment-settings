#!/usr/bin/env python3
"""Calendar popup shown by clicking the waybar date widget.

Interim stand-in for the hover tooltip while waybar 0.15.0-1 cannot show
tooltips at all (Alexays/Waybar#4917; fixed upstream, no fixed package in
resolute yet). Renders the same 3-month board the tooltip used: it calls
datebar.sh and shows its header + calendar so both stay one source.

Runs GTK3 because it is in the GNOME stack already; no extra packages.
Dismissal: click anywhere but this popup (focus leave, Hyprland takes
focus back) or Escape. The wrapper calendar-popup.sh also kills it on a
second click of the widget.
"""
import json
import os
import re
import subprocess
import sys

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('Gdk', '3.0') # else plain import resolves Gdk 4.0
from gi.repository import Gdk, GLib, Gtk

# waybar geometry: config.jsonc margin-top 6 + height 36, in logical px
BAR_BOTTOM = 42
GAP = 8

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


def calendar_markup():
    """Reuse datebar.sh's JSON: header bold, calendar in monospace."""
    # next to this script in the deployed scripts/ dir (a symlink here)
    datebar = os.path.join(os.path.dirname(os.path.realpath(__file__)),
                           'datebar.sh')
    data = json.loads(subprocess.run(
        [datebar], capture_output=True, text=True).stdout)
    # datebar.sh only emits the assembled tooltip:
    # ...<tt><small><b>HEADER</b>\n\nCALENDAR</small></tt>... — pick it apart
    m = re.match(r'.*<tt><small><b>(.*)</b>\n\n(.*)</small></tt>',
                 data['tooltip'], re.S)
    hdr, cal = (m.group(1), m.group(2)) if m else ('', '')
    # hdr keeps datebar.sh's centering pad, calibrated in plain monospace
    # columns over the board's max width: render it in <tt> at the same
    # font size, or the scaled pad spaces shift it off-center (a size
    # override on the header is what broke centering here)
    # color comes from the theme's .popup .header rule, not markup
    return f'<b>{hdr}</b>\n\n<tt>{cal}</tt>'


class CalendarWindow(Gtk.Window):
    def __init__(self, markup):
        super().__init__()
        # app_id: Wayland derives it from GLib.set_prgname in main()
        self.set_title('calendar-popup')
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_name('calwin')
        self.get_style_context().add_class('popup')
        self.set_border_width(12) # 1em-ish inner padding (like volume-popup)
        # rounded corners need an alpha visual before anything is drawn;
        # keep the app un-paintable so GTK paints the CSS window bg (see
        # transparent_window() in volume-popup.py for why)
        visual = self.get_screen().get_rgba_visual()
        if visual and self.get_screen().is_composited():
            self.set_visual(visual)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header, board = markup.split('\n\n', 1)
        # the headline colors through the theme's .popup .header rule
        head_label = Gtk.Label()
        head_label.set_markup(header)
        head_label.set_halign(Gtk.Align.CENTER)
        head_label.get_style_context().add_class('header')
        board_label = Gtk.Label()
        board_label.set_markup(board)
        box.pack_start(head_label, False, False, 0)
        box.pack_start(board_label, False, False, 0)
        self.add(box)

        self.connect('key-press-event', self.on_key)
        self.connect('focus-out-event', lambda *_: Gtk.main_quit())
        # position only after the window is mapped and sized (Wayland
        # toplevels cannot place themselves; Hyprland moves it instead)
        GLib.timeout_add(120, self.move_under_the_bar)

    def on_key(self, _win, event):
        if Gdk.keyval_name(event.keyval) == 'Escape':
            Gtk.main_quit()
        return False

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
                        f'exact {x:.0f} {y:.0f},class:calendar-popup'])
        subprocess.run(['hyprctl', 'dispatch', 'focuswindow',
                        'class:calendar-popup'])
        return False


def main():
    GLib.set_prgname('calendar-popup')
    win = CalendarWindow(calendar_markup())
    provider = Gtk.CssProvider()
    provider.load_from_data(load_css())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win.show_all()
    win.present()
    Gtk.main()


if __name__ == '__main__':
    sys.exit(main())