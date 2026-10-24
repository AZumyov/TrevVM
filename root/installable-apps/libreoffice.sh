#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    libreoffice-writer libreoffice-calc libreoffice-math \
    libreoffice-impress libreoffice-base
