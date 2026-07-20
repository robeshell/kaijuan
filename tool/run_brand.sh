#!/usr/bin/env bash
# Run a brand shell. Usage:
#   tool/run_brand.sh comic [device]
#   tool/run_brand.sh book macos
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BRAND="${1:-}"
DEVICE="${2:-}"
if [[ "$BRAND" != "comic" && "$BRAND" != "book" ]]; then
  echo "Usage: $0 comic|book [device]"
  exit 1
fi

ENTRY="lib/main_${BRAND}.dart"
ARGS=(run --flavor "$BRAND" -t "$ENTRY")
if [[ -n "$DEVICE" ]]; then
  ARGS+=(-d "$DEVICE")
fi

echo "+ flutter ${ARGS[*]}"
exec flutter "${ARGS[@]}"
