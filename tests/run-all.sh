#!/usr/bin/env bash
# Run the skill validator and every test script.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

status=0

echo "== validate-skills"
./scripts/validate-skills || status=1

for test_script in tests/test-*.sh; do
    [ -f "$test_script" ] || continue
    bash "$test_script" || status=1
done

exit "$status"
