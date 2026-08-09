# shellcheck shell=bash
# Assertion helpers for the agent-skills test scripts.
# Source this from a test script, then call check/finish.

TESTS_RUN=0
TESTS_FAILED=0

check() {
    # check DESCRIPTION COMMAND...
    local desc=$1
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    if "$@"; then
        echo "  ok: $desc"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $desc" >&2
    fi
}

assert_status() {
    # assert_status EXPECTED COMMAND...
    local expected=$1 actual=0
    shift
    "$@" >/dev/null 2>&1 || actual=$?
    if [ "$actual" != "$expected" ]; then
        echo "    expected exit status $expected, got $actual" >&2
        return 1
    fi
}

assert_contains() {
    # assert_contains HAYSTACK NEEDLE
    case "$1" in
        *"$2"*) return 0 ;;
    esac
    echo "    expected output to contain: $2" >&2
    echo "    actual output: $1" >&2
    return 1
}

assert_not_contains() {
    # assert_not_contains HAYSTACK NEEDLE
    case "$1" in
        *"$2"*)
            echo "    expected output NOT to contain: $2" >&2
            return 1
            ;;
    esac
    return 0
}

finish() {
    echo "$TESTS_RUN checks, $TESTS_FAILED failed"
    [ "$TESTS_FAILED" -eq 0 ]
}
