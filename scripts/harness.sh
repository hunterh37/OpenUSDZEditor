#!/bin/bash
# Runs every editor-harness scenario headlessly (no window, no focus steal) and
# fails on the first red one. Screenshots + transcripts land in .harness-out/.
#
# Usage: scripts/harness.sh [scenario.json ...]     (default: all scenarios)
# Requires: a Python with usd-core importable (same dependency as the app's Open).
set -euo pipefail
cd "$(dirname "$0")/.."

BIN=Tools/EditorHarness/.build/debug/editor-harness

if ! python3 -c 'import pxr' 2>/dev/null; then
  echo "harness: skipped — no usd-core in python3 (pip install usd-core)" >&2
  exit 0
fi

echo "──── build: editor-harness"
(cd Tools/EditorHarness && swift build)

SCENARIOS=("$@")
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  SCENARIOS=(Tools/EditorHarness/Scenarios/*.json)
fi

for scenario in "${SCENARIOS[@]}"; do
  echo "──── harness: $scenario"
  "$BIN" run "$scenario" --out .harness-out
done

echo "All scenarios green. Output: .harness-out/"
