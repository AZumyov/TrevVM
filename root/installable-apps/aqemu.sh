#!/usr/bin/env bash
# AQEMU (Qt front end for QEMU).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

apt-get update -qq
apt-get install -y -qq --no-install-recommends aqemu
install -Dm644 "$here/aqemu.desktop" /usr/share/applications/aqemu.desktop
