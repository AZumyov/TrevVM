#!/usr/bin/env bash
# WineHQ staging, including 32-bit support for Windows installers.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

dpkg --add-architecture i386
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates wget gnupg

install -d -m 0755 /etc/apt/keyrings
wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
wget -qO /etc/apt/sources.list.d/winehq-jammy.sources \
    https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources

apt-get update -qq
apt-get install -y --install-recommends winehq-staging
