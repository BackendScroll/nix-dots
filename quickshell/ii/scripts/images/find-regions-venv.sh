#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${ILLOGICAL_IMPULSE_PYTHON:-}"

if [[ -z "$PYTHON" ]] && command -v python3 >/dev/null 2>&1; then
    PYTHON="$(command -v python3)"
fi

# Content-region hints are optional. Always emit valid JSON so their failure
# cannot break the actual screenshot selector.
if [[ -z "$PYTHON" ]] || ! "$PYTHON" -c 'import cv2, numpy' >/dev/null 2>&1; then
    printf '[]\n'
    exit 0
fi

if ! "$PYTHON" "$SCRIPT_DIR/find_regions.py" "$@"; then
    printf '[]\n'
fi
