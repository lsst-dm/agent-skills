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

# The braced ${HOME} spelling is caught too.
ROOT=$(new_root); DIR=$(make_skill "$ROOT" hardcoded-braced)
printf 'Invoke it as `${HOME}/.codex/skills/hardcoded-braced/scripts/thing`.\n' \
    >> "$DIR/SKILL.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "braced HOME agent path is reported" \
    assert_contains "$OUT" "hardcoded install path"

# An absolute home directory spelled out in full is caught too.
ROOT=$(new_root); DIR=$(make_skill "$ROOT" hardcoded-absolute)
printf 'Invoke it as `/Users/someone/.claude/skills/hardcoded-absolute/scripts/thing`.\n' \
    >> "$DIR/SKILL.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "absolute agent path is reported" \
    assert_contains "$OUT" "hardcoded install path"

# A skill may carry per-agent metadata. No agent but Codex reads
# agents/openai.yaml, so the validator is the only thing standing between it
# and silent drift from the skill it describes.
write_openai_yaml() {
    # write_openai_yaml DIR PROMPT_NAME [OMIT_FIELD]
    local dir=$1 prompt_name=$2 omit=${3:-}
    mkdir -p "$dir/agents"
    {
        printf 'interface:\n'
        [ "$omit" = display_name ] || printf '  display_name: "A Skill"\n'
        [ "$omit" = short_description ] || \
            printf '  short_description: "Does a thing"\n'
        printf '  default_prompt: "Use $%s to do the thing."\n' "$prompt_name"
    } > "$dir/agents/openai.yaml"
}

ROOT=$(new_root); DIR=$(make_skill "$ROOT" metadata-ok)
write_openai_yaml "$DIR" metadata-ok
check "valid agent metadata passes" assert_status 0 "$VALIDATE" --root "$ROOT"

ROOT=$(new_root); DIR=$(make_skill "$ROOT" metadata-drift)
write_openai_yaml "$DIR" some-other-name
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "a default prompt naming another skill is reported" \
    assert_contains "$OUT" "some-other-name"

ROOT=$(new_root); DIR=$(make_skill "$ROOT" metadata-empty)
write_openai_yaml "$DIR" metadata-empty short_description
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "missing metadata field is reported" \
    assert_contains "$OUT" "short_description"

ROOT=$(new_root); DIR=$(make_skill "$ROOT" metadata-broken)
mkdir -p "$DIR/agents"
printf 'interface:\n  display_name: "unclosed\n   bad: [\n' \
    > "$DIR/agents/openai.yaml"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "unparsable agent metadata is reported" \
    assert_contains "$OUT" "openai.yaml"

# The README skills table must list exactly the skills that exist.
ROOT=$(new_root); make_skill "$ROOT" listed >/dev/null
check "listed skill passes" assert_status 0 "$VALIDATE" --root "$ROOT"

perl -ni -e 'print unless /`listed`/' "$ROOT/README.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "unlisted skill is reported" assert_contains "$OUT" "not listed in README"

ROOT=$(new_root); make_skill "$ROOT" listed >/dev/null
printf '| `ghost` | nonexistent |\n' >> "$ROOT/README.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "README naming a missing skill is reported" assert_contains "$OUT" "ghost"

# The agent guidance aliases must be symlinks to the canonical AGENTS.md.
ROOT=$(new_root); make_skill "$ROOT" guided >/dev/null
check "symlinked aliases pass" assert_status 0 "$VALIDATE" --root "$ROOT"

rm "$ROOT/GEMINI.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "missing alias is reported" assert_contains "$OUT" "GEMINI.md"

printf 'a divergent copy\n' > "$ROOT/GEMINI.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "copied alias is reported" assert_contains "$OUT" "not a copy"

rm -f "$ROOT/AGENTS.md"
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "missing AGENTS.md is reported" assert_contains "$OUT" "AGENTS.md"

# An equivalent spelling of the same target is still correct.
ROOT=$(new_root); make_skill "$ROOT" equivalent-link >/dev/null
rm "$ROOT/GEMINI.md"
( cd "$ROOT" && ln -s ./AGENTS.md GEMINI.md )
check "an equivalent symlink target passes" \
    assert_status 0 "$VALIDATE" --root "$ROOT"

# A link to some other file is not an alias.
ROOT=$(new_root); make_skill "$ROOT" wrong-link >/dev/null
rm "$ROOT/GEMINI.md"
( cd "$ROOT" && ln -s README.md GEMINI.md )
OUT=$("$VALIDATE" --root "$ROOT" 2>&1) || true
check "a symlink to another file is reported" \
    assert_contains "$OUT" "expected AGENTS.md"

finish
