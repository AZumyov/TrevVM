#!/usr/bin/env bash
#
# Configure the desktop environment inside the image.
# Reads /options.json (written by installer.py) and installs exactly one DE.

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

OPTIONS_FILE=/options.json
STARTWM_DIR=/defaults
APT_OPTS=(-y --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

log()  { printf '[trevvm-de] %s\n' "$*"; }
warn() { printf '[trevvm-de] warning: %s\n' "$*" >&2; }

apt_update() {
    local attempt
    for attempt in 1 2 3; do
        if apt-get update -qq; then
            return 0
        fi
        warn "apt-get update failed (attempt ${attempt}/3)"
        sleep $((attempt * 2))
    done
    return 1
}

apt_install() {
    local attempt
    for attempt in 1 2; do
        if apt-get install "${APT_OPTS[@]}" "$@"; then
            return 0
        fi
        warn "apt-get install failed (attempt ${attempt}/2): $*"
        apt-get -f install -y -qq || true
        sleep 2
    done
    return 1
}

normalize_de() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        *cinnamon*)        printf 'cinnamon' ;;
        *xfce*)            printf 'xfce' ;;
        *lxqt*)            printf 'lxqt' ;;
        *kde*|*plasma*)    printf 'kde' ;;
        *gnome*)           printf 'gnome' ;;
        *i3*)              printf 'i3' ;;
        *)                 printf '' ;;
    esac
}

install_startwm() {
    local script="/startwm-$1.sh"
    if [ ! -f "$script" ]; then
        warn "missing $script"
        return 1
    fi
    install -m 0755 "$script" "$STARTWM_DIR/startwm.sh"
    log "session: $script"
}

rc_append() {
    local line="$1" file
    for file in "${HOME}/.bashrc" /config/.bashrc; do
        [ -e "$file" ] || touch "$file" 2>/dev/null || continue
        grep -qxF -- "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >>"$file"
    done
}

install_kde() {
    apt_install firefox dolphin gwenview kde-config-gtk-style kdialog kfind khotkeys \
        kio-extras knewstuff-dialog konsole ksystemstats kwin-addons kwin-x11 \
        kwrite plasma-desktop plasma-workspace qml-module-qt-labs-platform systemsettings
    local taskbar=/usr/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/config/main.xml
    if [ -f "$taskbar" ]; then
        sed -i 's/applications:org.kde.discover.desktop,/applications:org.kde.konsole.desktop,/g' "$taskbar"
    fi
    install_startwm kde
}

install_xfce() {
    apt_install firefox mousepad xfce4-terminal xfce4 xubuntu-default-settings xubuntu-icon-theme
    rm -f /etc/xdg/autostart/xscreensaver.desktop
    install_startwm xfce
}

install_i3() {
    apt_install firefox i3 i3-wm stterm
    if [ -x /usr/bin/st ]; then
        update-alternatives --set x-terminal-emulator /usr/bin/st || warn "could not set st as the terminal"
    fi
    install_startwm i3
}

install_gnome() {
    apt_install firefox gnome-shell gnome-shell-common gnome-shell-extensions gnome-session \
        gnome-terminal gnome-control-center gnome-tweaks gnome-text-editor gnome-calculator \
        gnome-menus gnome-accessibility-themes gnome-themes-extra gnome-user-docs \
        gnome-video-effects yaru-theme-gtk yaru-theme-icon yaru-theme-sound \
        language-pack-en-base mesa-utils xterm dbus-x11 dconf-cli

    if [ -f /jammy.dconf.conf ]; then
        if command -v dbus-launch >/dev/null 2>&1; then
            eval "$(dbus-launch --sh-syntax)"
        fi
        dconf load / </jammy.dconf.conf || warn "dconf load failed"
    fi

    # GNOME's login1 integration does not work in this container.
    while IFS= read -r -d '' file; do
        mv "$file" "$file.back" 2>/dev/null || true
    done < <(find /usr -type f -iname '*login1*' -print0 2>/dev/null)

    rc_append 'sudo chmod u+s /usr/lib/dbus-1.0/dbus-daemon-launch-helper'
    rc_append 'export XDG_CURRENT_DESKTOP=GNOME'

    if [ -f /usr/share/applications/gnome-sound-panel.desktop ]; then
        mv /usr/share/applications/gnome-sound-panel.desktop \
           /usr/share/applications/gnome-sound-panel.desktop.back
    fi

    apt-get remove -y gnome-power-manager gnome-bluetooth gpaste mailnag \
        gnome-shell-mailnag gnome-shell-pomodoro gnome-shell-pomodoro-data >/dev/null 2>&1 || true

    install_startwm gnome
}

install_cinnamon() {
    apt_install firefox cinnamon
    install_startwm cinnamon
}

install_lxqt() {
    apt_install firefox lxqt
    install_startwm lxqt
}

main() {
    if [ ! -r "$OPTIONS_FILE" ]; then
        printf 'error: %s is missing\n' "$OPTIONS_FILE" >&2
        exit 1
    fi

    local raw_de de
    raw_de="$(jq -r '.DE // ""' "$OPTIONS_FILE" 2>/dev/null || true)"
    de="$(normalize_de "$raw_de")"
    if [ -z "$de" ]; then
        warn "unknown desktop '${raw_de:-<empty>}', using cinnamon"
        de="cinnamon"
    fi
    log "desktop: $de"

    apt_update

    case "$de" in
        kde)      install_kde ;;
        xfce)     install_xfce ;;
        i3)       install_i3 ;;
        gnome)    install_gnome ;;
        cinnamon) install_cinnamon ;;
        lxqt)     install_lxqt ;;
        *)        printf 'error: unsupported desktop %s\n' "$de" >&2; exit 1 ;;
    esac

    if [ ! -x "$STARTWM_DIR/startwm.sh" ]; then
        printf 'error: no startwm.sh was configured\n' >&2
        exit 1
    fi
    chmod +x "$STARTWM_DIR/startwm.sh"

    rm -f /startwm-*.sh /jammy.dconf.conf /install-de.sh
    log "desktop ready"
}

main "$@"
