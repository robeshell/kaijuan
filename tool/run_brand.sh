#!/usr/bin/env bash
# Run the unified Kaika App.
#
# The old dual-brand split has been collapsed into a single App with two
# reader engines (page-image + reflow). This script is kept for muscle memory
# but now ignores the brand argument.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE="${2:-}"
ARGS=(run -t lib/main.dart)
if [[ -n "$DEVICE" ]]; then
  ARGS+=(-d "$DEVICE")
fi

echo "+ flutter ${ARGS[*]}"
exec flutter "${ARGS[@]}"
