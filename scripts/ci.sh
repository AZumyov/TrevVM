#!/usr/bin/env bash
#
# Run every check CI runs, locally. Requires shellcheck and pytest.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"

echo "== shellcheck"
shellcheck -x install.sh trevvm.sh root/*.sh root/installable-apps/*.sh

echo "== python"
PY="${PYTHON:-python3}"
if [ -x .venv/bin/python ]; then
    PY=".venv/bin/python"
elif [ -x .venv/Scripts/python.exe ]; then
    PY=".venv/Scripts/python.exe"
fi
"$PY" -m compileall -q installer.py tests
"$PY" -m pytest -q

if command -v hadolint >/dev/null 2>&1; then
    echo "== hadolint"
    hadolint Dockerfile
fi

echo "== installer dry run"
./install.sh --dry-run >/dev/null

echo "all checks passed"
