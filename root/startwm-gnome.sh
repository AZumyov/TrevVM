#!/usr/bin/env bash
set -u
setterm blank 0 || true
setterm powerdown 0 || true
export XDG_CURRENT_DESKTOP=GNOME
export XDG_SESSION_TYPE=x11
service dbus start >/dev/null 2>&1 || true
exec /usr/bin/gnome-shell --x11 -r >/dev/null 2>&1
