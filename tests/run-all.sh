#!/usr/bin/env bash
# Run the skill validator and every test script.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# The interpreter used for each test file. Override it to check the bash 3.2
# floor that macOS ships: BASH_BIN=/bin/bash ./tests/run-all.sh
BASH_BIN=${BASH_BIN:-bash}
export BASH_BIN

status=0

echo "== validate-skills"
./scripts/validate-skills || status=1

for test_script in tests/test-*.sh; do
    [ -f "$test_script" ] || continue
    "$BASH_BIN" "$test_script" || status=1
done

exit "$status"
