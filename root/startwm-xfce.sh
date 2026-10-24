#!/usr/bin/env bash
set -u
setterm blank 0 || true
setterm powerdown 0 || true
xfwm_config="${HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
if [ -f "$xfwm_config" ]; then
    sed -i \
        '/use_compositing/c <property name="use_compositing" type="bool" value="false"/>' \
        "$xfwm_config"
fi
exec /usr/bin/xfce4-session >/dev/null 2>&1
