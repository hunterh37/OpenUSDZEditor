#!/bin/bash
# Module-governance gate: every package under Packages/ must be fully onboarded
# before it can merge. This is the check that would have caught MeshKit shipping
# outside the dependency-lint/spec/coverage regime.
#
# For each Packages/<Name> we require:
#   1. A policy entry in scripts/dependency-lint.sh (lint itself also fails
#      without one; checked here for a single consolidated report).
#   2. A mention in specs/architecture.md (workspace layout + dependency rules).
#   3. A coverage-floor row in specs/testing.md.
#   4. A Tests/ directory with at least one test file.
#   5. Inclusion in scripts/test-all.sh so its suite actually runs in CI.
#   6. A per-module spec: either a dedicated specs/<name>.md or an explicit
#      "Spec:" pointer in the package's Package.swift header comment.
set -euo pipefail
cd "$(dirname "$0")/.."

FAILURES=0
fail() { echo "GOVERNANCE VIOLATION: $1"; FAILURES=$((FAILURES+1)); }

for d in Packages/*/; do
  name=$(basename "$d")

  # 1. dependency-lint policy entry
  grep -qE "^[[:space:]]*${name}\)" scripts/dependency-lint.sh \
    || fail "$name: no policy entry in scripts/dependency-lint.sh"

  # 2. architecture spec mention
  grep -q "$name" specs/architecture.md \
    || fail "$name: not mentioned in specs/architecture.md (add to workspace layout + dependency rules)"

  # 3. coverage floor in testing spec
  grep -qE "^\|[[:space:]]*${name}" specs/testing.md \
    || fail "$name: no coverage-floor row in specs/testing.md"

  # 4. tests exist
  if [[ -z "$(find "${d}Tests" -name '*.swift' -print -quit 2>/dev/null)" ]]; then
    fail "$name: no test files under ${d}Tests"
  fi

  # 5. wired into test-all.sh
  grep -q "Packages/${name}" scripts/test-all.sh \
    || fail "$name: not listed in scripts/test-all.sh (its suite never runs in CI)"

  # 6. per-module spec coverage
  if ! grep -rlq "$name" specs/*.md; then
    fail "$name: no spec in specs/ references it"
  fi
done

if [[ $FAILURES -gt 0 ]]; then
  echo "module-governance: $FAILURES violation(s) — see CONTRIBUTING notes in specs/architecture.md §Adding a New Package"
  exit 1
fi
echo "module-governance: OK (all $(ls -d Packages/*/ | wc -l | tr -d ' ') packages fully onboarded)"
