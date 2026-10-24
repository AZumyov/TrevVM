#!/usr/bin/env bash
# Official Minecraft launcher.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends default-jre ca-certificates wget

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

wget -qO "$tmp/Minecraft.deb" https://launcher.mojang.com/download/Minecraft.deb
apt-get install -y -qq "$tmp/Minecraft.deb"
