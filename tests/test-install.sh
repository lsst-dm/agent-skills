#!/usr/bin/env bash
# Tests for install.sh, run against a disposable fake HOME.
set -uo pipefail

REPO_ROOT=$( cd "$(dirname "$0")/.." && pwd -P )
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

INSTALL="$REPO_ROOT/install.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# fresh_home AGENT... -- new HOME with the given agent directories present
fresh_home() {
    local home agent
    home=$(mktemp -d "$WORK/home.XXXXXX")
    for agent in "$@"; do
        mkdir -p "$home/$agent"
    done
    printf '%s\n' "$home"
}

run_install() {
    local home=$1
    shift
    HOME="$home" "$INSTALL" "$@" 2>&1
}

echo "== install.sh"

# Auto-detection installs only for agents that are present.
HOME_DIR=$(fresh_home .claude)
run_install "$HOME_DIR" >/dev/null
check "claude target created" test -L "$HOME_DIR/.claude/skills/lsst-eups"
check "codex target not created" test ! -e "$HOME_DIR/.codex/skills/lsst-eups"
check "gemini target not created" test ! -e "$HOME_DIR/.gemini/config/skills/lsst-eups"

# The symlink points at this repository.
# shellcheck disable=SC2016  # $1/$2 below are for the nested bash -c, not this shell
check "symlink resolves into the repository" \
    bash -c 'test "$( cd "$1" && pwd -P )" = "$2"' _ \
    "$HOME_DIR/.claude/skills/lsst-eups" "$REPO_ROOT/skills/lsst-eups"

# Re-running is idempotent.
check "re-install succeeds" assert_status 0 env HOME="$HOME_DIR" "$INSTALL"

# Codex prefers ~/.agents over ~/.codex when both exist.
HOME_DIR=$(fresh_home .agents .codex)
run_install "$HOME_DIR" >/dev/null
check "codex prefers .agents" test -L "$HOME_DIR/.agents/skills/lsst-eups"
check "codex does not also use .codex" test ! -e "$HOME_DIR/.codex/skills/lsst-eups"

# Codex falls back to ~/.codex when ~/.agents is absent.
HOME_DIR=$(fresh_home .codex)
run_install "$HOME_DIR" >/dev/null
check "codex falls back to .codex" test -L "$HOME_DIR/.codex/skills/lsst-eups"

# Antigravity uses the location all variants read.
HOME_DIR=$(fresh_home .gemini)
run_install "$HOME_DIR" >/dev/null
check "gemini target created" test -L "$HOME_DIR/.gemini/config/skills/lsst-eups"

# An existing real directory is never destroyed without --force.
HOME_DIR=$(fresh_home .claude)
mkdir -p "$HOME_DIR/.claude/skills/lsst-eups"
printf 'precious\n' > "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"
OUT=$(run_install "$HOME_DIR")
check "conflict exits non-zero" assert_status 1 env HOME="$HOME_DIR" "$INSTALL"
check "conflict is reported" assert_contains "$OUT" "--force"
check "existing directory untouched" \
    grep -q precious "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"

# --force moves the existing directory aside.
run_install "$HOME_DIR" --force >/dev/null
check "forced install replaces the directory" \
    test -L "$HOME_DIR/.claude/skills/lsst-eups"
check "forced install keeps a backup" \
    grep -q precious "$HOME_DIR/.claude/skills/lsst-eups.bak/SKILL.md"

# --copy produces a real directory rather than a symlink.
HOME_DIR=$(fresh_home .claude)
run_install "$HOME_DIR" --copy >/dev/null
check "copy mode creates a directory" \
    test -d "$HOME_DIR/.claude/skills/lsst-eups"
check "copy mode is not a symlink" \
    test ! -L "$HOME_DIR/.claude/skills/lsst-eups"
check "copy mode copies the script" \
    test -x "$HOME_DIR/.claude/skills/lsst-eups/scripts/lsst-run"

# --dry-run changes nothing.
HOME_DIR=$(fresh_home .claude)
OUT=$(run_install "$HOME_DIR" --dry-run)
check "dry run reports the action" assert_contains "$OUT" "lsst-eups"
check "dry run installs nothing" test ! -e "$HOME_DIR/.claude/skills/lsst-eups"

# An unknown skill name is rejected.
HOME_DIR=$(fresh_home .claude)
OUT=$(run_install "$HOME_DIR" no-such-skill)
check "unknown skill exits non-zero" \
    assert_status 1 env HOME="$HOME_DIR" "$INSTALL" no-such-skill
check "unknown skill is reported" assert_contains "$OUT" "no-such-skill"

# --uninstall removes an installed symlink.
HOME_DIR=$(fresh_home .claude)
run_install "$HOME_DIR" >/dev/null
run_install "$HOME_DIR" --uninstall >/dev/null
check "uninstall removes the link" test ! -e "$HOME_DIR/.claude/skills/lsst-eups"

# --uninstall leaves a foreign directory alone.
HOME_DIR=$(fresh_home .claude)
mkdir -p "$HOME_DIR/.claude/skills/lsst-eups"
printf 'precious\n' > "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"
run_install "$HOME_DIR" --uninstall >/dev/null
check "uninstall spares a foreign directory" \
    grep -q precious "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"

finish
