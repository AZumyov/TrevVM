#!/usr/bin/env bash
# Discord from the official .deb endpoint.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends libatomic1 ca-certificates wget

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

wget -qO "$tmp/discord.deb" "https://discord.com/api/download?platform=linux&format=deb"
apt-get install -y -qq "$tmp/discord.deb"
