#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixtures pass literal $VARS to nested shells
# Tests for skills/lsst-eups/scripts/lsst-run.
# Cases needing a real stack skip themselves when no environment is active.
set -uo pipefail

REPO_ROOT=$( cd "$(dirname "$0")/.." && pwd -P )
BASH_BIN=${BASH_BIN:-bash}
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

TMPFILE=$(mktemp)
OUT=$("$LSST_RUN" -l "$TMPFILE" -- true 2>&1)
check "-l on a file says it is not a directory" \
    assert_contains "$OUT" "not a directory"
check "-l on a file exits non-zero" \
    assert_status 1 "$LSST_RUN" -l "$TMPFILE" -- true
rm -f "$TMPFILE"

OUT=$(run_unactivated -t current -- true 2>&1)
check "a movable tag is refused" assert_contains "$OUT" "immutable"

if [ -z "${EUPS_PATH:-}" ] || [ -z "${LSST_CONDA_ENV_NAME:-}" ]; then
    echo "  skip: no active LSST environment; stack-dependent checks skipped"
    finish
    exit
fi

OUT=$("$LSST_RUN" --list-tags 2>&1)
check "--list-tags lists at least one build tag" \
    "$BASH_BIN" -c "printf '%s\n' \"\$1\" | grep -qE '^b[0-9]+$'" _ "$OUT"

OUT=$("$LSST_RUN" -t b1 -- true 2>&1)
check "invalid tag is rejected" assert_contains "$OUT" "b1"
check "invalid tag exits non-zero" assert_status 1 "$LSST_RUN" -t b1 -- true

OUT=$("$LSST_RUN" -l /nonexistent/clone -- true 2>&1)
check "missing -l path is rejected" assert_contains "$OUT" "not found"
check "missing -l path exits non-zero" \
    assert_status 1 "$LSST_RUN" -l /nonexistent/clone -- true

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/lsst-run"

OUT=$("$LSST_RUN" -- python -c 'import lsst.daf.butler; print("import-ok")' 2>&1)
check "command runs against lsst_distrib" assert_contains "$OUT" "import-ok"

check "snapshot was cached" "$BASH_BIN" -c 'ls "$1"/env-*.sh >/dev/null 2>&1' _ "$CACHE_DIR"

# The snapshot must not leak the launching shell's local setups. lsst_build is
# set up by envconfig in an lsstsw tree, so assert on a marker we control.
OUT=$(SETUP_FAKE_MARKER=leaked "$LSST_RUN" -- \
    sh -c 'echo "marker=[${SETUP_FAKE_MARKER:-}]"' 2>&1)
check "launching shell setup vars do not leak" \
    assert_contains "$OUT" "marker=[]"

OUT=$(TERM=xterm-256color "$LSST_RUN" -- sh -c 'echo "term=[${TERM:-}]"' 2>&1)
check "TERM is carried into the command" \
    assert_contains "$OUT" "term=[xterm-256color]"

OUT=$(LC_ALL=en_US.UTF-8 "$LSST_RUN" -- sh -c 'echo "lc=[${LC_ALL:-}]"' 2>&1)
check "LC_ALL is carried into the command" \
    assert_contains "$OUT" "lc=[en_US.UTF-8]"

EMPTY_CLONE=$(mktemp -d)
check "the no-command form still validates local clones" \
    assert_status 1 "$LSST_RUN" -l "$EMPTY_CLONE"
rmdir "$EMPTY_CLONE"

OUT=$("$LSST_RUN" -- sh -c 'echo "tag=$SETUP_LSST_DISTRIB"' 2>&1)
check "lsst_distrib is set up in the snapshot" assert_contains "$OUT" "lsst_distrib"

# A second call must reuse the cached snapshot rather than rebuilding it.
OUT=$("$LSST_RUN" -- true 2>&1)
check "warm call does not rebuild the snapshot" \
    assert_not_contains "$OUT" "building environment"

finish
