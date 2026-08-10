#!/usr/bin/env bash
# Tests for skills/lsst-eups/scripts/lsst-run.
# Cases needing a real stack skip themselves when no environment is active.
set -uo pipefail

REPO_ROOT=$( cd "$(dirname "$0")/.." && pwd -P )
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

LSST_RUN="$REPO_ROOT/skills/lsst-eups/scripts/lsst-run"

echo "== lsst-run"

# Runs lsst-run with no active environment regardless of the caller's shell.
run_unactivated() {
    env -u EUPS_PATH -u EUPS_DIR -u LSST_CONDA_ENV_NAME -u LSSTSW \
        "$LSST_RUN" "$@" 2>&1
}

OUT=$(run_unactivated -- true)
check "unactivated environment fails" \
    assert_status 1 env -u EUPS_PATH -u EUPS_DIR -u LSST_CONDA_ENV_NAME \
    "$LSST_RUN" -- true
check "unactivated error names envconfig" assert_contains "$OUT" "envconfig"
check "unactivated error names loadLSST" assert_contains "$OUT" "loadLSST"

OUT=$(run_unactivated --bogus-option -- true)
check "unknown option is rejected" assert_contains "$OUT" "unknown option"

OUT=$(run_unactivated -t 2>&1)
check "missing -t argument is rejected" assert_contains "$OUT" "requires"

OUT=$(run_unactivated -l 2>&1)
check "missing -l argument is rejected" assert_contains "$OUT" "requires"

if [ -z "${EUPS_PATH:-}" ] || [ -z "${LSST_CONDA_ENV_NAME:-}" ]; then
    echo "  skip: no active LSST environment; stack-dependent checks skipped"
    finish
    exit
fi

OUT=$("$LSST_RUN" --list-tags 2>&1)
check "--list-tags lists at least one build tag" \
    bash -c "printf '%s\n' \"\$1\" | grep -qE '^b[0-9]+$'" _ "$OUT"

OUT=$("$LSST_RUN" -t b1 -- true 2>&1)
check "invalid tag is rejected" assert_contains "$OUT" "b1"

OUT=$("$LSST_RUN" -l /nonexistent/clone -- true 2>&1)
check "missing -l path is rejected" assert_contains "$OUT" "not found"

finish
