#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixtures embed literal backticks in markdown
# Fixture-driven tests for scripts/validate-skills.
set -uo pipefail

REPO_ROOT=$( cd "$(dirname "$0")/.." && pwd -P )
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

VALIDATE="$REPO_ROOT/scripts/validate-skills"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# new_root -- a repository root carrying the boilerplate the validator expects.
# Later tasks add checks for README.md and the agent guidance symlinks, so the
# fixtures provide them from the start and the negative cases remove them.
new_root() {
    local root
    root=$(mktemp -d "$WORK/root.XXXXXX")
    mkdir -p "$root/skills"
    printf 'Guidance for agents working in this fixture.\n' > "$root/AGENTS.md"
    ( cd "$root" && ln -s AGENTS.md CLAUDE.md && ln -s AGENTS.md GEMINI.md )
    printf '# fixture\n\n## Available skills\n\n| Skill | Description |\n|---|---|\n' \
        > "$root/README.md"
    printf '%s\n' "$root"
}

# make_skill ROOT NAME -- minimal valid skill, listed in the README; echoes its
# directory.
make_skill() {
    local root=$1 name=$2 dir="$1/skills/$2"
    mkdir -p "$dir"
    cat > "$dir/SKILL.md" <<EOF
---
name: $name
description: A fixture skill used to exercise the validator.
---

# ${name}

Body text.
EOF
    printf '| `%s` | fixture |\n' "$name" >> "$root/README.md"
    printf '%s\n' "$dir"
}

echo "== validate-skills"

# A valid skill passes.
ROOT=$(new_root); make_skill "$ROOT" good-skill >/dev/null
check "valid skill passes" assert_status 0 "$VALIDATE" --root "$ROOT"

# A skill directory with no SKILL.md fails.
ROOT=$(new_root); mkdir -p "$ROOT/skills/no-entrypoint"
check "missing SKILL.md fails" assert_status 1 "$VALIDATE" --root "$ROOT"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "missing SKILL.md is reported" assert_contains "$OUT" "SKILL.md"

# Frontmatter that does not start the file fails.
ROOT=$(new_root); DIR=$(make_skill "$ROOT" bad-front)
printf 'Leading text\n---\nname: bad-front\n---\n' > "$DIR/SKILL.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "missing frontmatter is reported" assert_contains "$OUT" "frontmatter"

# A name that does not match the directory fails.
ROOT=$(new_root); DIR=$(make_skill "$ROOT" mismatch)
perl -pi -e 's/^name: mismatch$/name: something-else/' "$DIR/SKILL.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "name/directory mismatch is reported" assert_contains "$OUT" "does not match"

# A name violating the naming convention fails.
ROOT=$(new_root); DIR=$(make_skill "$ROOT" Bad_Name)
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "invalid name convention is reported" assert_contains "$OUT" "lowercase"

# A missing description fails.
ROOT=$(new_root); DIR=$(make_skill "$ROOT" no-desc)
perl -ni -e 'print unless /^description:/' "$DIR/SKILL.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "missing description is reported" assert_contains "$OUT" "description"

# A referenced relative path that does not exist fails.
ROOT=$(new_root); DIR=$(make_skill "$ROOT" dangling)
printf 'Run `scripts/absent` to do the thing.\n' >> "$DIR/SKILL.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "dangling reference is reported" assert_contains "$OUT" "scripts/absent"

# A referenced relative path that exists passes.
ROOT=$(new_root); DIR=$(make_skill "$ROOT" resolved)
mkdir -p "$DIR/scripts"
printf '#!/bin/sh\nexit 0\n' > "$DIR/scripts/present"
chmod +x "$DIR/scripts/present"
printf 'Run `scripts/present` to do the thing.\n' >> "$DIR/SKILL.md"
check "resolved reference passes" assert_status 0 "$VALIDATE" --root "$ROOT"

# A non-executable script fails.
chmod -x "$DIR/scripts/present"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "non-executable script is reported" assert_contains "$OUT" "not executable"
chmod +x "$DIR/scripts/present"

# A shell script with a syntax error fails.
ROOT=$(new_root); DIR=$(make_skill "$ROOT" broken-sh)
mkdir -p "$DIR/scripts"
printf '#!/bin/bash\nif [ 1 = 1 ]; then\n' > "$DIR/scripts/broken"
chmod +x "$DIR/scripts/broken"
printf 'Run `scripts/broken`.\n' >> "$DIR/SKILL.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "shell syntax error is reported" assert_contains "$OUT" "syntax"

# A skill that hardcodes an agent install path fails.
ROOT=$(new_root); DIR=$(make_skill "$ROOT" hardcoded)
printf 'Invoke it as `~/.claude/skills/hardcoded/scripts/thing`.\n' >> "$DIR/SKILL.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "hardcoded agent path is reported" assert_contains "$OUT" "hardcoded install path"

# Force the PyYAML-absent path so the fallback parser is genuinely exercised.
SHIM=$(mktemp -d "$WORK/shim.XXXXXX")
printf 'raise ImportError("simulated missing PyYAML")\n' > "$SHIM/yaml.py"

ROOT=$(new_root); make_skill "$ROOT" fallback-ok >/dev/null
check "fallback parser accepts a valid skill" \
    assert_status 0 env PYTHONPATH="$SHIM" "$VALIDATE" --root "$ROOT"

# An inline comment must not become part of the value.
ROOT=$(new_root); DIR=$(make_skill "$ROOT" commented)
perl -pi -e 's/^name: commented$/name: commented # an inline comment/' \
    "$DIR/SKILL.md"
check "fallback parser strips an inline comment" \
    assert_status 0 env PYTHONPATH="$SHIM" "$VALIDATE" --root "$ROOT"

finish
