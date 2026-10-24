#!/usr/bin/env bash
# Google Chrome from Google's signed repository.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates wget gnupg

install -d -m 0755 /etc/apt/keyrings
wget -qO- https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor --yes -o /etc/apt/keyrings/google-chrome.gpg
chmod 0644 /etc/apt/keyrings/google-chrome.gpg

printf 'deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main\n' \
    >/etc/apt/sources.list.d/google-chrome.list

apt-get update -qq
apt-get install -y -qq --no-install-recommends google-chrome-stable
