#!/usr/bin/env bash
# ILLOGICAL_IMPULSE_PYTHON is a Nix-built interpreter that already carries every
# dependency, so there is no virtualenv to activate.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${ILLOGICAL_IMPULSE_PYTHON:-python3}" "$SCRIPT_DIR/least_busy_region.py" "$@"
