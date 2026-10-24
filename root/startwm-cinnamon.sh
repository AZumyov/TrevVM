#!/usr/bin/env bash
set -u
setterm blank 0 || true
setterm powerdown 0 || true
exec /usr/bin/cinnamon-session >/dev/null 2>&1
