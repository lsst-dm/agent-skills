#!/usr/bin/env bash
# Tests for install.sh, run against a disposable fake HOME.
set -uo pipefail

REPO_ROOT=$( cd "$(dirname "$0")/.." && pwd -P )
BASH_BIN=${BASH_BIN:-bash}
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
    "$BASH_BIN" -c 'test "$( cd "$1" && pwd -P )" = "$2"' _ \
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

# When ~/.agents appears after a skill was registered under ~/.codex, a
# later install moves the registration rather than leaving both in place.
HOME_DIR=$(fresh_home .codex)
run_install "$HOME_DIR" >/dev/null
check "codex-only install lands in .codex" \
    test -L "$HOME_DIR/.codex/skills/lsst-eups"
mkdir -p "$HOME_DIR/.agents"
OUT=$(run_install "$HOME_DIR")
check "re-install after .agents appears lands in .agents" \
    test -L "$HOME_DIR/.agents/skills/lsst-eups"
check "re-install removes the stale .codex entry" \
    test ! -e "$HOME_DIR/.codex/skills/lsst-eups"
check "the stale duplicate removal is reported" \
    assert_contains "$OUT" "stale duplicate"

# A foreign entry in the non-preferred Codex location is reported but never
# touched, and the run still succeeds.
HOME_DIR=$(fresh_home .codex)
mkdir -p "$HOME_DIR/.codex/skills/lsst-eups"
printf 'precious\n' > "$HOME_DIR/.codex/skills/lsst-eups/SKILL.md"
mkdir -p "$HOME_DIR/.agents"
OUT=$(run_install "$HOME_DIR")
check "install with a foreign duplicate still succeeds" \
    assert_status 0 env HOME="$HOME_DIR" "$INSTALL"
check "the foreign duplicate is named in a warning" \
    assert_contains "$OUT" "$HOME_DIR/.codex/skills/lsst-eups"
check "the foreign duplicate survives" \
    grep -q precious "$HOME_DIR/.codex/skills/lsst-eups/SKILL.md"
check "the preferred location is still installed" \
    test -L "$HOME_DIR/.agents/skills/lsst-eups"

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

# A pre-existing .bak is never destroyed.
HOME_DIR=$(fresh_home .claude)
mkdir -p "$HOME_DIR/.claude/skills/lsst-eups"
printf 'current\n' > "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"
mkdir -p "$HOME_DIR/.claude/skills/lsst-eups.bak"
printf 'older\n' > "$HOME_DIR/.claude/skills/lsst-eups.bak/SKILL.md"
OUT=$(run_install "$HOME_DIR" --force)
check "force refuses when a backup already exists" \
    assert_status 1 env HOME="$HOME_DIR" "$INSTALL" --force
check "existing backup is preserved" \
    grep -q older "$HOME_DIR/.claude/skills/lsst-eups.bak/SKILL.md"
check "existing directory is preserved" \
    grep -q current "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"
check "backup conflict is reported" assert_contains "$OUT" ".bak"

# A dry run must predict the refusal, not an action that cannot happen.
HOME_DIR=$(fresh_home .claude)
mkdir -p "$HOME_DIR/.claude/skills/lsst-eups" \
         "$HOME_DIR/.claude/skills/lsst-eups.bak"
printf 'current\n' > "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"
printf 'older\n' > "$HOME_DIR/.claude/skills/lsst-eups.bak/SKILL.md"
OUT=$(run_install "$HOME_DIR" --force --dry-run)
check "dry run predicts the backup conflict" assert_contains "$OUT" ".bak"
check "dry run exits non-zero on a backup conflict" \
    assert_status 1 env HOME="$HOME_DIR" "$INSTALL" --force --dry-run

# --dry-run must not move a foreign directory aside.
HOME_DIR=$(fresh_home .claude)
mkdir -p "$HOME_DIR/.claude/skills/lsst-eups"
printf 'precious\n' > "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"
run_install "$HOME_DIR" --force --dry-run >/dev/null
check "dry run with --force moves nothing" \
    test ! -e "$HOME_DIR/.claude/skills/lsst-eups.bak"
check "dry run with --force leaves the original" \
    grep -q precious "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"

# --copy produces a real directory rather than a symlink.
HOME_DIR=$(fresh_home .claude)
run_install "$HOME_DIR" --copy >/dev/null
check "copy mode creates a directory" \
    test -d "$HOME_DIR/.claude/skills/lsst-eups"
check "copy mode is not a symlink" \
    test ! -L "$HOME_DIR/.claude/skills/lsst-eups"
check "copy mode copies the script" \
    test -x "$HOME_DIR/.claude/skills/lsst-eups/scripts/lsst-run"

# Copy mode is idempotent and refreshes without needing --force.
HOME_DIR=$(fresh_home .claude)
run_install "$HOME_DIR" --copy >/dev/null
printf 'stale\n' >> "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"
OUT=$(run_install "$HOME_DIR" --copy)
check "copy re-run succeeds without --force" \
    assert_status 0 env HOME="$HOME_DIR" "$INSTALL" --copy
# shellcheck disable=SC2016  # $1 below is for the nested bash -c, not this shell
check "copy re-run refreshes the content" \
    "$BASH_BIN" -c '! grep -q stale "$1"' _ \
    "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"
check "copy re-run creates no backup" \
    test ! -e "$HOME_DIR/.claude/skills/lsst-eups.bak"

# A deliberate install mode is not silently undone by a later default run.
HOME_DIR=$(fresh_home .claude)
run_install "$HOME_DIR" --copy >/dev/null
OUT=$(run_install "$HOME_DIR")
check "a mode switch requires --force" \
    assert_status 1 env HOME="$HOME_DIR" "$INSTALL"
check "the mode switch conflict is reported" assert_contains "$OUT" "--force"
check "the copy survives a refused mode switch" \
    test ! -L "$HOME_DIR/.claude/skills/lsst-eups"
check "a forced mode switch succeeds" \
    assert_status 0 env HOME="$HOME_DIR" "$INSTALL" --force
check "a forced mode switch produces a symlink" \
    test -L "$HOME_DIR/.claude/skills/lsst-eups"
check "a forced mode switch creates no backup" \
    test ! -e "$HOME_DIR/.claude/skills/lsst-eups.bak"

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

# An unknown option is rejected.
HOME_DIR=$(fresh_home .claude)
check "unknown option exits non-zero" \
    assert_status 1 env HOME="$HOME_DIR" "$INSTALL" --nonsense

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

# A backup left by --force is not removed by --uninstall, so its location has
# to be reported rather than left for the user to stumble on.
HOME_DIR=$(fresh_home .claude)
mkdir -p "$HOME_DIR/.claude/skills/lsst-eups"
printf 'precious\n' > "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"
run_install "$HOME_DIR" --force >/dev/null
OUT=$(run_install "$HOME_DIR" --uninstall)
check "uninstall reports a remaining backup" assert_contains "$OUT" ".bak"
check "the backup itself survives uninstall" \
    grep -q precious "$HOME_DIR/.claude/skills/lsst-eups.bak/SKILL.md"

# Replacing an entry this installer made discards any edits inside it, so the
# real run has to say so rather than only the dry run.
HOME_DIR=$(fresh_home .claude)
run_install "$HOME_DIR" --copy >/dev/null
OUT=$(run_install "$HOME_DIR" --copy)
check "a real run reports replacing its own entry" \
    assert_contains "$OUT" "replaced"

# --help describes the tool, so it must work before HOME matters.
OUT=$(HOME='' "$INSTALL" --help 2>&1)
check "--help works without HOME" assert_status 0 env HOME= "$INSTALL" --help
check "--help still prints usage" assert_contains "$OUT" "Usage:"
check "an install without HOME is refused" \
    assert_status 1 env HOME= "$INSTALL" --claude

# With no backup present there is nothing to mention.
HOME_DIR=$(fresh_home .claude)
run_install "$HOME_DIR" >/dev/null
OUT=$(run_install "$HOME_DIR" --uninstall)
check "uninstall stays quiet when no backup exists" \
    assert_not_contains "$OUT" ".bak"

# A refused uninstall reports failure.
HOME_DIR=$(fresh_home .claude)
mkdir -p "$HOME_DIR/.claude/skills/lsst-eups"
printf 'precious\n' > "$HOME_DIR/.claude/skills/lsst-eups/SKILL.md"
check "refused uninstall exits non-zero" \
    assert_status 1 env HOME="$HOME_DIR" "$INSTALL" --uninstall

# An absolute shebang keeps the installer on the system bash, which is the
# 3.2 floor on macOS. `env bash` would pick up whatever is first on PATH and
# silently exempt this script from the floor.
# shellcheck disable=SC2016  # $1 below is for the nested bash -c, not this shell
check "the installer names its interpreter absolutely" \
    bash -c '[ "$(head -1 "$1")" = "#!/bin/bash" ]' _ "$INSTALL"

finish
