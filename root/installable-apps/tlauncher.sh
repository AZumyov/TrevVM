#!/usr/bin/env bash
# Third-party Minecraft launcher (TLauncher).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends openjdk-17-jre ca-certificates wget

install -d -m 0755 /opt/tlauncher
wget -qO /opt/tlauncher/TLauncher.jar \
    https://repo.tlauncher.org/update/lch/starter-core-1.11-v10.jar

icon_line=""
if wget -qO /opt/tlauncher/TLauncher_icon.png \
    https://cdn.icon-icons.com/icons2/2699/PNG/512/minecraft_logo_icon_168974.png; then
    icon_line="Icon=/opt/tlauncher/TLauncher_icon.png"
fi

cat >/usr/share/applications/tlauncher.desktop <<EOF
[Desktop Entry]
Name=TLauncher
Comment=Minecraft launcher
Exec=java -jar /opt/tlauncher/TLauncher.jar
${icon_line}
Terminal=false
Type=Application
Categories=Game;
EOF
chmod 0644 /usr/share/applications/tlauncher.desktop
