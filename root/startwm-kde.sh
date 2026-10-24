#!/usr/bin/env bash
set -u
if [ ! -f "$HOME/.config/kwinrc" ]; then
    kwriteconfig5 --file "$HOME/.config/kwinrc" --group Compositing --key Enabled false || true
fi
if [ ! -f "$HOME/.config/kscreenlockerrc" ]; then
    kwriteconfig5 --file "$HOME/.config/kscreenlockerrc" --group Daemon --key Autolock false || true
fi
setterm blank 0 || true
setterm powerdown 0 || true
exec /usr/bin/dbus-launch /usr/bin/startplasma-x11 >/dev/null 2>&1
