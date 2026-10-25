#!/usr/bin/env bash
# ARAKIEL InfoCat v2 development launcher.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$root/infocat.py" "$@"
