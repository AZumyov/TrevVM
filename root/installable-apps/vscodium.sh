#!/usr/bin/env bash
# VSCodium from the official repository.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates wget gnupg

wget -qO- https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
    | gpg --dearmor --yes -o /usr/share/keyrings/vscodium-archive-keyring.gpg
chmod 0644 /usr/share/keyrings/vscodium-archive-keyring.gpg

printf 'deb [signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://download.vscodium.com/debs vscodium main\n' \
    >/etc/apt/sources.list.d/vscodium.list

apt-get update -qq
apt-get install -y -qq --no-install-recommends codium
