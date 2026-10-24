#!/usr/bin/env bash
# Steam, with the 32-bit libraries it needs.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

dpkg --add-architecture i386
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates wget

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

wget -qO "$tmp/steam.deb" https://repo.steampowered.com/steam/archive/precise/steam_latest.deb
apt-get install -y -qq "$tmp/steam.deb"
