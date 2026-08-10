# agent-skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `lsst-dm/agent-skills` repository so a DM team member can clone it, run `./install.sh`, and have the team's skills available in Claude Code, Codex, and Antigravity from a single canonical copy per skill.

**Architecture:** Each skill is one directory under `skills/` containing `SKILL.md` plus optional `scripts/`, `references/`, `assets/`, and agent-specific additive metadata. `install.sh` symlinks (or copies) whole skill directories into each agent's discovery location. `scripts/validate-skills` enforces the layout and portability rules and runs in CI. `lsst-eups` is the single proof-of-concept skill.

**Tech Stack:** Bash 3.2, python3 standard library, GitHub Actions, shellcheck.

**Design document:** `docs/design/2026-08-09-agent-skills-design.md`

## Global Constraints

- **Bash 3.2 compatibility.** macOS ships `GNU bash 3.2.57`. No associative arrays (`declare -A`), no `${var,,}`, no `mapfile`. Under `set -u`, expand possibly-empty arrays as `${arr[@]+"${arr[@]}"}`.
- **No GNU-only tool flags.** Do not use `readlink -f`, `sort -V`, or `sed -i` without a suffix. Resolve directories with `( cd "$d" && pwd -P )`. Sort build tags numerically by stripping the leading `b`.
- **Hashing must degrade.** `shasum` lives in the conda environment and `sha256sum` is not universal. Try `shasum -a 256`, then `sha256sum`, then fail with a clear message.
- **python3 standard library only.** No `pip install` is ever required. PyYAML is used when importable and a minimal parser is used otherwise.
- **Skills must not hardcode their installed path.** That path differs per agent and per install mode.
- **shellcheck clean.** All shell scripts pass `shellcheck` with no warnings.
- **Markdown prose is one sentence per line.** American English spelling.
- **Never push to the remote.** Commit locally only; the user pushes.
- Work happens on branch `u/timj/initial-seed` in `/Users/timj/work/lsstsw/build/llm-dm-skills` (the checkout directory name does not matter and nothing may depend on it).

---

## File Structure

| File | Responsibility |
|------|----------------|
| `.gitignore` | Keep machine-local agent settings and build noise out of the repository. |
| `docs/spec.md` | The original brief, kept for provenance. |
| `skills/lsst-eups/SKILL.md` | Agent-neutral instructions for the EUPS stack skill. |
| `skills/lsst-eups/scripts/lsst-run` | Runs a command inside a pristine, cached EUPS environment. |
| `skills/lsst-eups/agents/openai.yaml` | Codex-only display metadata; ignored by other agents. |
| `scripts/validate-skills` | Enforces skill layout, frontmatter, and portability rules. |
| `install.sh` | Installs skills into each agent's discovery location. |
| `tests/lib.sh` | Assertion helpers shared by all test scripts. |
| `tests/run-all.sh` | Runs the validator and every `tests/test-*.sh`. |
| `tests/test-validate-skills.sh` | Fixture-driven tests for the validator. |
| `tests/test-lsst-run.sh` | Tests for `lsst-run`; stack-dependent cases self-skip. |
| `tests/test-install.sh` | Tests for `install.sh` against a fake `HOME`. |
| `README.md` | What the repository is, quick start, skills list, portability, security. |
| `CONTRIBUTING.md` | How to add a skill and run checks locally. |
| `AGENTS.md` | Instructions for an agent working in this repository; the canonical copy. |
| `CLAUDE.md`, `GEMINI.md` | Symlinks to `AGENTS.md` so each agent finds the same guidance. |
| `.github/workflows/ci.yml` | Runs the validator and tests on push and pull request. |

---

### Task 1: Repository hygiene

**Files:**
- Create: `.gitignore`
- Move: `spec.md` → `docs/spec.md`

`.claude/settings.local.json` is already excluded here by a personal global gitignore, but that only protects one machine, so the repository carries its own rule for everyone else.

**Interfaces:**
- Consumes: nothing.
- Produces: `docs/spec.md` exists; the working tree is clean apart from files this plan creates.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
# Machine-local agent settings
.claude/settings.local.json

# Editor and OS noise
.DS_Store
*.swp

# Python bytecode from validator runs
__pycache__/
*.pyc

# Scratch workspace used while executing an implementation plan
.superpowers/
```

- [ ] **Step 2: Move the original brief**

```bash
mkdir -p docs
mv spec.md docs/spec.md
```

- [ ] **Step 3: Verify**

Run: `git status --short --ignored`
Expected: `docs/spec.md` and `.gitignore` untracked, `.claude/` listed as ignored, and `.claude/settings.local.json` never appearing as a tracked or untracked file.

- [ ] **Step 4: Commit**

```bash
git add .gitignore docs/spec.md
git commit -m "Add gitignore and move the original brief into docs

settings.local.json is machine-local and accumulates absolute paths from
working sessions, so the repository ignores it for every contributor
rather than relying on personal global gitignore files."
```

---

### Task 2: Test harness and skill validator

**Files:**
- Create: `tests/lib.sh`, `tests/run-all.sh`, `tests/test-validate-skills.sh`, `scripts/validate-skills`

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/validate-skills [--root DIR]` exits 0 when every skill under `DIR/skills` is valid and 1 otherwise, printing one `path: message` diagnostic per problem. `tests/lib.sh` exports shell functions `check DESC CMD...`, `assert_status EXPECTED CMD...`, `assert_contains HAYSTACK NEEDLE`, and `finish`.

- [ ] **Step 1: Write the test harness library**

Create `tests/lib.sh`:

```bash
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
```

- [ ] **Step 2: Write the failing validator tests**

Create `tests/test-validate-skills.sh`:

```bash
#!/usr/bin/env bash
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
# A directory on PYTHONPATH holding a yaml.py that raises makes `import yaml`
# fail without touching the validator.
SHIM=$(mktemp -d "$WORK/shim.XXXXXX")
printf 'raise ImportError("simulated missing PyYAML")\n' > "$SHIM/yaml.py"

ROOT=$(new_root); make_skill "$ROOT" fallback-ok >/dev/null
check "fallback parser accepts a valid skill" \
    assert_status 0 env PYTHONPATH="$SHIM" "$VALIDATE" --root "$ROOT"

ROOT=$(new_root); DIR=$(make_skill "$ROOT" commented)
perl -pi -e 's/^name: commented$/name: commented # an inline comment/' \
    "$DIR/SKILL.md"
check "fallback parser strips an inline comment" \
    assert_status 0 env PYTHONPATH="$SHIM" "$VALIDATE" --root "$ROOT"

ROOT=$(new_root); DIR=$(make_skill "$ROOT" comment-only)
perl -pi -e 's/^description: .*$/description: # placeholder/' "$DIR/SKILL.md"
OUT=$(env PYTHONPATH="$SHIM" "$VALIDATE" --root "$ROOT" 2>&1) || true
check "fallback parser treats a comment-only value as empty" \
    assert_contains "$OUT" 'missing a `description` field'

ROOT=$(new_root); DIR=$(make_skill "$ROOT" tab-comment)
perl -pi -e 's/^name: tab-comment$/name: tab-comment\t# note/' "$DIR/SKILL.md"
check "fallback parser strips a tab-delimited comment" \
    assert_status 0 env PYTHONPATH="$SHIM" "$VALIDATE" --root "$ROOT"

finish
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bash tests/test-validate-skills.sh`
Expected: every check fails because `scripts/validate-skills` does not exist yet.

- [ ] **Step 4: Implement the validator**

Create `scripts/validate-skills`:

```python
#!/usr/bin/env python3
"""Validate every skill in this repository.

Checks layout, frontmatter, naming, references, and portability rules.
Prints one diagnostic per problem and exits 1 if any were found.
"""

from __future__ import annotations

import argparse
import os
import py_compile
import re
import subprocess
import sys
import tempfile
from pathlib import Path

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

# Markdown links to relative targets, and backticked paths under a known
# skill subdirectory. Both forms are unambiguous, so neither produces false
# positives on ordinary prose.
LINK_RE = re.compile(r"\[[^\]]*\]\((?!https?://|mailto:|#)([^)]+)\)")
CODE_PATH_RE = re.compile(r"`((?:scripts|references|assets)/[^`\s]+)`")

# Agent discovery locations. A skill that names one of these has baked in an
# install path that differs per agent and per install mode.
HARDCODED_PATH_RE = re.compile(
    r"(?:~|\$HOME)/\.(?:claude|codex|agents|gemini)/[A-Za-z0-9_./-]*skills"
)

SHELL_SHEBANG_RE = re.compile(r"^#!.*\b(?:ba|da|k|z)?sh\b")


def load_frontmatter(text: str) -> tuple[dict, list[str]]:
    """Return (fields, errors) from the leading YAML frontmatter block."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, ["missing YAML frontmatter block at the start of the file"]
    end = None
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            end = index
            break
    if end is None:
        return {}, ["unterminated YAML frontmatter block"]
    block = "\n".join(lines[1:end])
    try:
        import yaml
    except ImportError:
        return parse_flat_mapping(block)
    try:
        data = yaml.safe_load(block)
    except Exception as exc:  # noqa: BLE001 - report any parse failure
        return {}, [f"frontmatter does not parse as YAML: {exc}"]
    if data is None:
        return {}, ["frontmatter block is empty"]
    if not isinstance(data, dict):
        return {}, ["frontmatter is not a key/value mapping"]
    return data, []


def parse_flat_mapping(block: str) -> tuple[dict, list[str]]:
    """Parse the flat `key: value` subset that skill frontmatter uses.

    Used only when PyYAML is unavailable, so that validation never requires
    installing anything.
    """
    fields: dict[str, str] = {}
    errors: list[str] = []
    for offset, line in enumerate(block.splitlines()):
        lineno = offset + 2  # account for the opening --- line
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line[:1].isspace():
            errors.append(
                f"line {lineno}: nested frontmatter needs PyYAML to validate"
            )
            continue
        key, sep, value = line.partition(":")
        if not sep:
            errors.append(f"line {lineno}: not a `key: value` pair")
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        elif value.startswith("#"):
            value = ""
        else:
            # YAML starts an inline comment at a `#` preceded by whitespace,
            # so a `#` inside a word is part of the value.
            comment = re.search(r"\s#", value)
            if comment:
                value = value[: comment.start()].rstrip()
        fields[key.strip()] = value
    return fields, errors


def referenced_paths(text: str) -> list[str]:
    """Relative paths a SKILL.md points at, deduplicated in first-seen order."""
    found: list[str] = []
    for match in LINK_RE.finditer(text):
        found.append(match.group(1).split("#", 1)[0].strip())
    for match in CODE_PATH_RE.finditer(text):
        found.append(match.group(1))
    seen: set[str] = set()
    ordered = []
    for path in found:
        if path and not path.startswith("/") and path not in seen:
            seen.add(path)
            ordered.append(path)
    return ordered


def is_shell_script(path: Path) -> bool:
    if path.suffix in {".sh", ".bash"}:
        return True
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            return bool(SHELL_SHEBANG_RE.match(handle.readline()))
    except OSError:
        return False


def check_shell(path: Path, report) -> None:
    result = subprocess.run(
        ["bash", "-n", str(path)], capture_output=True, text=True
    )
    if result.returncode != 0:
        report(path, f"shell syntax error: {result.stderr.strip()}")
        return
    if shutil_which("shellcheck"):
        result = subprocess.run(
            ["shellcheck", "--format=gcc", str(path)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            for line in result.stdout.strip().splitlines():
                report(path, f"shellcheck: {line}")


def check_python(path: Path, report) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        try:
            py_compile.compile(
                str(path), cfile=os.path.join(tmp, "out.pyc"), doraise=True
            )
        except py_compile.PyCompileError as exc:
            report(path, f"python syntax error: {exc}")


def shutil_which(name: str):
    from shutil import which

    return which(name)


def validate_skill(skill_dir: Path, report) -> None:
    entrypoint = skill_dir / "SKILL.md"
    if not entrypoint.is_file():
        report(skill_dir, "no SKILL.md in skill directory")
        return

    text = entrypoint.read_text(encoding="utf-8")
    fields, errors = load_frontmatter(text)
    for message in errors:
        report(entrypoint, message)
    if errors and not fields:
        return

    name = fields.get("name", "")
    if not name:
        report(entrypoint, "frontmatter is missing a `name` field")
    else:
        if name != skill_dir.name:
            report(
                entrypoint,
                f"frontmatter name `{name}` does not match directory "
                f"`{skill_dir.name}`",
            )
        if not NAME_RE.match(name):
            report(
                entrypoint,
                f"name `{name}` must be lowercase words separated by hyphens",
            )

    if not fields.get("description", ""):
        report(entrypoint, "frontmatter is missing a `description` field")

    for reference in referenced_paths(text):
        if not (skill_dir / reference).exists():
            report(entrypoint, f"referenced path does not exist: {reference}")

    for match in HARDCODED_PATH_RE.finditer(text):
        report(
            entrypoint,
            f"hardcoded install path `{match.group(0)}`; refer to skill files "
            "relatively instead",
        )

    scripts_dir = skill_dir / "scripts"
    if scripts_dir.is_dir():
        for path in sorted(scripts_dir.rglob("*")):
            if not path.is_file():
                continue
            if not os.access(path, os.X_OK):
                report(path, "file under scripts/ is not executable")
            if is_shell_script(path):
                check_shell(path, report)
            elif path.suffix == ".py":
                check_python(path, report)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        default=str(Path(__file__).resolve().parent.parent),
        help="repository root to validate (default: this repository)",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    skills_root = root / "skills"
    problems: list[str] = []

    def report(path: Path, message: str) -> None:
        try:
            shown = path.relative_to(root)
        except ValueError:
            shown = path
        problems.append(f"{shown}: {message}")

    if not skills_root.is_dir():
        print(f"{skills_root}: no skills directory", file=sys.stderr)
        return 1

    skill_dirs = sorted(p for p in skills_root.iterdir() if p.is_dir())
    for skill_dir in skill_dirs:
        validate_skill(skill_dir, report)

    for problem in problems:
        print(problem, file=sys.stderr)

    if problems:
        print(
            f"\n{len(problems)} problem(s) in {len(skill_dirs)} skill(s)",
            file=sys.stderr,
        )
        return 1

    print(f"{len(skill_dirs)} skill(s) validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 5: Make it executable and run the tests**

```bash
chmod +x scripts/validate-skills
bash tests/test-validate-skills.sh
```

Expected: `16 checks, 0 failed`.

- [ ] **Step 6: Write the runner**

Create `tests/run-all.sh`:

```bash
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
```

- [ ] **Step 7: Verify the runner and shellcheck cleanliness**

```bash
chmod +x tests/run-all.sh
shellcheck tests/lib.sh tests/run-all.sh tests/test-validate-skills.sh
./tests/run-all.sh
```

Expected: shellcheck silent. `run-all.sh` reports `no skills directory` and exits 1, because `skills/` does not exist yet. That is correct at this point and Task 3 resolves it.

- [ ] **Step 8: Commit**

```bash
git add tests/lib.sh tests/run-all.sh tests/test-validate-skills.sh scripts/validate-skills
git commit -m "Add skill validator and test harness

Validates layout, frontmatter, naming, referenced paths, script syntax
and executability, and rejects hardcoded per-agent install paths. Uses
PyYAML when available and a flat-mapping parser otherwise so that
validation never requires installing anything."
```

---

### Task 3: lsst-run argument handling and environment detection

**Files:**
- Create: `skills/lsst-eups/scripts/lsst-run`, `skills/lsst-eups/SKILL.md`, `tests/test-lsst-run.sh`

`SKILL.md` lands here covering the wrapper as it stands, so the validator stays green; Task 5 adds the remaining sections.

**Interfaces:**
- Consumes: `scripts/validate-skills` from Task 2.
- Produces: `lsst-run [-t TAG] [-l PATH]... [--list-tags] [--] COMMAND [ARGS...]`. Exits 1 with a message naming both activation commands when `EUPS_PATH`, `EUPS_DIR`, or `LSST_CONDA_ENV_NAME` is unset. Exits 1 for an unknown option or a missing option argument.

- [ ] **Step 1: Write the failing tests**

Create `tests/test-lsst-run.sh`:

```bash
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

# Argument parsing happens before the environment check, so these run with or
# without a stack and therefore stay covered in CI.
TMPFILE=$(mktemp)
OUT=$("$LSST_RUN" -l "$TMPFILE" -- true 2>&1)
check "-l on a file says it is not a directory" \
    assert_contains "$OUT" "not a directory"
check "-l on a file exits non-zero" \
    assert_status 1 "$LSST_RUN" -l "$TMPFILE" -- true
rm -f "$TMPFILE"

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
check "invalid tag exits non-zero" assert_status 1 "$LSST_RUN" -t b1 -- true

OUT=$("$LSST_RUN" -l /nonexistent/clone -- true 2>&1)
check "missing -l path is rejected" assert_contains "$OUT" "not found"
check "missing -l path exits non-zero" \
    assert_status 1 "$LSST_RUN" -l /nonexistent/clone -- true

finish
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test-lsst-run.sh`
Expected: all checks fail because `lsst-run` does not exist.

- [ ] **Step 3: Write the argument handling and detection half of `lsst-run`**

Create `skills/lsst-eups/scripts/lsst-run`:

```bash
#!/bin/bash
#
# lsst-run: run a command inside the LSST Science Pipelines EUPS environment.
#
# Usage: lsst-run [-t TAG] [-l PATH]... [--list-tags] [--] COMMAND [ARGS...]
#
#   -t TAG       EUPS build tag for lsst_distrib (e.g. b8411). Defaults to the
#                highest bNNNN tag currently carried by lsst_distrib.
#   -l PATH      Local package clone to `setup -k -r PATH`. Repeatable and
#                applied in order, so list dependencies before the package
#                being worked on. Relative paths are resolved to absolute.
#   --list-tags  Print the build tags available for lsst_distrib and exit.
#
# The LSST environment must already be active in the shell that started the
# agent, established by either of:
#
#     source "$LSSTSW/bin/envconfig"     # lsstsw checkout
#     source <stack>/loadLSST.bash       # lsstinstall tree
#
# lsst-run does not run the command in that inherited environment. It builds a
# pristine environment holding lsst_distrib at the chosen tag and nothing else,
# caches it under ~/.cache/lsst-run, and applies any -l clones on top per call.
# The isolation keeps a local `setup` in the launching shell from silently
# changing what the command sees; the cache keeps repeat calls fast.

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/lsst-run"

err() { echo "lsst-run: $*" >&2; }
die() { err "$*"; exit 1; }

TAG=""
LOCALS=()
LIST_TAGS=0

while [ $# -gt 0 ]; do
    case "$1" in
        -t)
            [ $# -ge 2 ] || die "-t requires a tag argument"
            TAG="$2"
            shift 2
            ;;
        -l)
            [ $# -ge 2 ] || die "-l requires a path argument"
            if [ ! -e "$2" ]; then
                die "-l path not found: $2"
            elif [ ! -d "$2" ]; then
                die "-l path is not a directory: $2"
            fi
            dir=$( cd "$2" 2>/dev/null && pwd -P ) || \
                die "-l path is not readable: $2"
            LOCALS+=("$dir")
            shift 2
            ;;
        --list-tags)
            LIST_TAGS=1
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

# The wrapper deliberately refuses to guess where the stack is. Both supported
# activation paths export these three variables, so their absence means no
# environment was activated before the agent started.
if [ -z "${EUPS_PATH:-}" ] || [ -z "${EUPS_DIR:-}" ] || \
   [ -z "${LSST_CONDA_ENV_NAME:-}" ]; then
    err "no active LSST environment"
    err "activate the stack in the shell that starts the agent, then restart it:"
    err "    source \"\$LSSTSW/bin/envconfig\"   # lsstsw checkout"
    err "    source <stack>/loadLSST.bash      # lsstinstall tree"
    exit 1
fi

# Build tags carried by lsst_distrib, lowest first. A version can carry several
# colon-separated tags in any order, so split them apart rather than trusting
# position. Sorting strips the leading b so an ordinary numeric sort applies;
# a lexical sort would place b10000 before b9.
build_tags() {
    eups list lsst_distrib --raw 2>/dev/null |
        awk -F'|' '{print $3}' |
        tr ':' '\n' |
        grep -E '^b[0-9]+$' |
        sed 's/^b//' |
        sort -n -u |
        sed 's/^/b/'
}

if [ "$LIST_TAGS" = 1 ]; then
    build_tags
    exit 0
fi

if [ -n "$TAG" ]; then
    if ! eups list -t "$TAG" lsst_distrib >/dev/null 2>&1; then
        err "lsst_distrib has no build tag $TAG; available tags are:"
        build_tags >&2
        exit 1
    fi
else
    TAG=$(build_tags | tail -1)
    [ -n "$TAG" ] || die "could not determine the latest lsst_distrib build tag"
fi
err "using lsst_distrib tag $TAG"
```

- [ ] **Step 4: Write the SKILL.md sections that describe what now exists**

Create `skills/lsst-eups/SKILL.md`. This is complete and accurate for the wrapper as it stands; Task 5 adds the quick reference, rules, and troubleshooting sections.

```markdown
---
name: lsst-eups
description: Use when work on an LSST Science Pipelines package needs the EUPS stack environment — running pytest, scons, butler, pipetask, eups, or python importing lsst.* against lsst_distrib — or when the user mentions EUPS, lsstsw, "setup lsst_distrib", the stack environment, or bNNNN/weekly build tags.
---

# LSST EUPS Stack Environment

## Overview

Run every stack-dependent command through the `lsst-run` wrapper in this skill's `scripts/` directory.
Invoke it by its path within this skill directory; the examples elsewhere write `lsst-run` for brevity.

```
lsst-run [-t TAG] [-l PATH]... [--list-tags] -- COMMAND [ARGS...]
```

## Prerequisite

The user must activate an LSST environment in the shell that starts the agent, using either:

```bash
source "$LSSTSW/bin/envconfig"     # lsstsw checkout
source <stack>/loadLSST.bash       # lsstinstall tree
```

If `lsst-run` reports that no environment is active, ask the user to activate one and restart the agent.
Do not try to locate or activate a stack yourself.

## Tags

`lsst_distrib` in an lsstsw stack carries only `bNNNN` build tags — `setup -t w_2026_24 lsst_distrib` fails even though individual packages carry weekly tags.
`lsst-run` selects the highest `bNNNN` currently carried by `lsst_distrib` unless `-t` is given, and reports the choice on stderr.

Build tag numbers are local to one EUPS tree and are not stable across a redeployment of that tree.
A tag from an earlier tree will be rejected; run `lsst-run --list-tags` to see what the current tree offers.
```

- [ ] **Step 5: Run the tests**

```bash
chmod +x skills/lsst-eups/scripts/lsst-run
bash tests/test-lsst-run.sh
shellcheck skills/lsst-eups/scripts/lsst-run
./scripts/validate-skills
```

Expected: `lsst-run` tests pass (13 checks with a stack active, 8 without). shellcheck silent. Validator reports `1 skill(s) validated`.

- [ ] **Step 6: Commit**

```bash
git add skills/lsst-eups tests/test-lsst-run.sh
git commit -m "Add lsst-run argument handling and environment detection

Requires an already-activated LSST environment rather than probing for a
stack from a hardcoded default, and resolves build tags through the eups
command line. Tags sort numerically after stripping the leading b, since
a lexical sort places b10000 before b9."
```

---

### Task 4: lsst-run environment snapshot and execution

**Files:**
- Modify: `skills/lsst-eups/scripts/lsst-run` (append to the end)
- Modify: `tests/test-lsst-run.sh` (append before `finish`)

**Interfaces:**
- Consumes: `TAG`, `LOCALS`, `EUPS_PATH`, `EUPS_DIR`, `LSST_CONDA_ENV_NAME`, `CACHE_DIR`, `err`, `die` from Task 3.
- Produces: a cached snapshot at `$CACHE_DIR/env-<hash>.sh` keyed on `LSST_CONDA_ENV_NAME`, `EUPS_PATH`, and `TAG`; `lsst-run` execs the requested command inside it.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test-lsst-run.sh`, immediately before the final `finish` line:

```bash
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/lsst-run"

OUT=$("$LSST_RUN" -- python -c 'import lsst.daf.butler; print("import-ok")' 2>&1)
check "command runs against lsst_distrib" assert_contains "$OUT" "import-ok"

check "snapshot was cached" bash -c 'ls "$1"/env-*.sh >/dev/null 2>&1' _ "$CACHE_DIR"

# The snapshot must not leak the launching shell's local setups. lsst_build is
# set up by envconfig in an lsstsw tree, so assert on a marker we control.
OUT=$(SETUP_FAKE_MARKER=leaked "$LSST_RUN" -- \
    sh -c 'echo "marker=[${SETUP_FAKE_MARKER:-}]"' 2>&1)
check "launching shell setup vars do not leak" \
    assert_contains "$OUT" "marker=[]"

OUT=$("$LSST_RUN" -- sh -c 'echo "tag=$SETUP_LSST_DISTRIB"' 2>&1)
check "lsst_distrib is set up in the snapshot" assert_contains "$OUT" "lsst_distrib"

# A second call must reuse the cached snapshot rather than rebuilding it.
OUT=$("$LSST_RUN" -- true 2>&1)
check "warm call does not rebuild the snapshot" \
    assert_not_contains "$OUT" "building environment"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test-lsst-run.sh`
Expected: the new checks fail; `lsst-run` currently exits after printing the tag without running anything.

- [ ] **Step 3: Drop the now-unnecessary shellcheck suppression**

`CACHE_DIR` is declared near the top of `lsst-run` but nothing read it until this task, so it carries a `# shellcheck disable=SC2034` directive.
The code below reads it, so delete that directive line and leave the assignment.
Step 4 confirms shellcheck is still silent without it.

- [ ] **Step 4: Append the snapshot and execution logic to `lsst-run`**

```bash

# shasum lives in the conda environment and sha256sum is not universal, so try
# both before giving up.
hash_of() {
    if command -v shasum >/dev/null 2>&1; then
        printf '%s\n' "$@" | shasum -a 256 | cut -c1-16
    elif command -v sha256sum >/dev/null 2>&1; then
        printf '%s\n' "$@" | sha256sum | cut -c1-16
    else
        die "neither shasum nor sha256sum is available"
    fi
}

# The script that activates this environment from scratch. lsstsw checkouts
# provide bin/envconfig at $LSSTSW; lsstinstall trees provide loadLSST.sh at the
# root of the tree, which is three levels above the conda environment prefix.
activation_script() {
    local root candidate
    if [ -n "${LSSTSW:-}" ] && [ -f "$LSSTSW/bin/envconfig" ]; then
        printf '%s\n' "$LSSTSW/bin/envconfig"
        return 0
    fi
    [ -n "${CONDA_PREFIX:-}" ] || return 1
    root=$( cd "$CONDA_PREFIX/../../.." 2>/dev/null && pwd -P ) || return 1
    for candidate in "$root/loadLSST.sh" "$root/loadLSST.bash" \
                     "$root/bin/envconfig"; do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

SNAPSHOT="$CACHE_DIR/env-$(hash_of "$LSST_CONDA_ENV_NAME" "$EUPS_PATH" "$TAG").sh"

build_snapshot() {
    local script
    script=$(activation_script) || die \
        "cannot locate envconfig or loadLSST.sh for $LSST_CONDA_ENV_NAME"
    err "building environment snapshot for tag $TAG (this takes a few seconds)..."
    mkdir -p "$CACHE_DIR" || die "cannot create cache directory $CACHE_DIR"

    # env -i drops everything the launching shell had set up, so the snapshot
    # holds lsst_distrib and nothing else. LSST_CONDA_ENV_NAME is passed
    # through because both activation scripts honour it as an input and it
    # selects the same conda environment the user activated.
    if ! env -i \
        HOME="$HOME" \
        USER="${USER:-}" \
        TERM="${TERM:-dumb}" \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        LSST_CONDA_ENV_NAME="$LSST_CONDA_ENV_NAME" \
        ${LSSTSW:+LSSTSW="$LSSTSW"} \
        bash -c '
            source "$1" 1>&2 || exit 1
            setup -t "$2" lsst_distrib || exit 1
            export -p | grep -Ev "^declare -x (PWD|OLDPWD|SHLVL|_)="
        ' _ "$script" "$TAG" > "$SNAPSHOT.tmp"
    then
        rm -f "$SNAPSHOT.tmp"
        die "failed to build the environment snapshot for tag $TAG"
    fi
    mv "$SNAPSHOT.tmp" "$SNAPSHOT"
}

if [ ! -s "$SNAPSHOT" ]; then
    build_snapshot
fi

# shellcheck source=/dev/null
. "$SNAPSHOT"

# A snapshot left over from a removed or rebuilt tree no longer yields a usable
# environment, so rebuild it once rather than failing.
if ! command -v eups >/dev/null 2>&1; then
    err "cached snapshot is unusable; rebuilding"
    build_snapshot
    # shellcheck source=/dev/null
    . "$SNAPSHOT"
fi

# export -p captures variables but not shell functions, so `setup` has to be
# redefined before any local clone can be applied.
if [ ${#LOCALS[@]} -gt 0 ]; then
    # shellcheck source=/dev/null
    . "$EUPS_DIR/bin/setups.sh" || die "cannot source $EUPS_DIR/bin/setups.sh"
    for pkg in ${LOCALS[@]+"${LOCALS[@]}"}; do
        setup -k -r "$pkg" || die "setup -k -r $pkg failed"
    done
fi

if [ $# -eq 0 ]; then
    err "environment ready (no command given)"
    exit 0
fi

exec "$@"
```

- [ ] **Step 5: Run the tests**

```bash
bash tests/test-lsst-run.sh
shellcheck skills/lsst-eups/scripts/lsst-run
./scripts/validate-skills
```

Expected: `18 checks, 0 failed` with a stack active. shellcheck silent even though the `SC2034` directive was removed, because `CACHE_DIR` is now read. Validator reports `1 skill(s) validated`.

- [ ] **Step 6: Verify local clone layering by hand**

```bash
CLONE=$(cd "$LSSTSW/build/afw" && pwd -P)
skills/lsst-eups/scripts/lsst-run -l "$CLONE" -- \
    python -c 'import lsst.afw; print(lsst.afw.__file__)'
```

Expected: the printed path is under the clone, not under `$EUPS_PATH`.
A `ModuleNotFoundError: No module named 'lsst.afw.version'` also confirms the clone won, and means that clone needs `scons python` run once.

- [ ] **Step 7: Verify snapshot freshness by hand**

```bash
ls "${XDG_CACHE_HOME:-$HOME/.cache}"/lsst-run/env-*.sh
skills/lsst-eups/scripts/lsst-run -t "$(skills/lsst-eups/scripts/lsst-run --list-tags | tail -1)" -- true
```

Expected: exactly one snapshot per tag, and no rebuild message on the second call.

- [ ] **Step 8: Commit**

```bash
git add skills/lsst-eups/scripts/lsst-run tests/test-lsst-run.sh
git commit -m "Add lsst-run environment snapshot and execution

The snapshot is built under env -i so the launching shell's setups
cannot leak into it, and is keyed on LSST_CONDA_ENV_NAME, EUPS_PATH and
the resolved tag. Local clones are applied per call instead of being
baked in, so one snapshot exists per tag, the cache cannot be
contaminated by a local package, and table file edits take effect on the
next call without any refresh flag."
```

---

### Task 5: Final lsst-eups SKILL.md and Codex metadata

**Files:**
- Modify: `skills/lsst-eups/SKILL.md` (replace entirely)
- Create: `skills/lsst-eups/agents/openai.yaml`

**Interfaces:**
- Consumes: the `lsst-run` interface from Tasks 3 and 4.
- Produces: the installed skill's user-facing instructions.

- [ ] **Step 1: Replace `skills/lsst-eups/SKILL.md`**

```markdown
---
name: lsst-eups
description: Use when work on an LSST Science Pipelines package needs the EUPS stack environment — running pytest, scons, butler, pipetask, eups, or python importing lsst.* against lsst_distrib — or when the user mentions EUPS, lsstsw, "setup lsst_distrib", the stack environment, or bNNNN/weekly build tags.
---

# LSST EUPS Stack Environment

## Overview

Run every stack-dependent command through the `lsst-run` wrapper in this skill's `scripts/` directory.
Invoke it by its path within this skill directory; the examples below write `lsst-run` for brevity.

It runs the command against a pristine environment holding `lsst_distrib` at a build tag plus any local package clones named on the command line.
That environment is cached, so only the first call per build tag pays the few seconds of initialization and later calls add about a quarter of a second.

Each command runs in a fresh shell, so environment variables never persist from one call to the next.
Never try to "activate" the environment once and reuse it, and never hand-roll `source envconfig && setup ...` chains, because sourcing inside a pipeline silently discards the environment.

```
lsst-run [-t TAG] [-l PATH]... [--list-tags] -- COMMAND [ARGS...]
```

## Prerequisite

The user must activate an LSST environment in the shell that starts the agent, using either:

```bash
source "$LSSTSW/bin/envconfig"     # lsstsw checkout
source <stack>/loadLSST.bash       # lsstinstall tree
```

If `lsst-run` reports that no environment is active, ask the user to activate one and restart the agent.
Do not try to locate or activate a stack yourself.

If the harness sandboxes commands, `lsst-run` needs to read the stack outside the workspace and write under `~/.cache/lsst-run`.
Request escalated permissions rather than reverse-engineering the EUPS environment.

## Choose the environment

- The user asks for the EUPS/stack environment → use it.
- Package has `ups/` but no setuptools config in `pyproject.toml` → EUPS-only; use it.
- Package has `ups/` **and** a setuptools `pyproject.toml` (dual-use, common) → do NOT assume; ask the user which environment to use unless the task clearly needs the stack or they already said.
- No `ups/` → ordinary Python package; this skill does not apply.

## Quick reference

Run from the package root; `-l` also accepts absolute paths, so `-l /path/to/clone` from any directory is equivalent to `-l .` from that clone's root.
List dependencies' `-l` before the package being worked on, so the working package comes last.

| Task | Command |
|------|---------|
| Tests | `lsst-run -l . -- pytest tests/test_foo.py` |
| Build after C++ edits | `lsst-run -l . -- scons -Q -j 8` |
| Make fresh clone importable | `lsst-run -l . -- scons python` (generates `version.py`) |
| Entry points / CLI changed in pyproject.toml | `lsst-run -l . -- scons pkginfo` |
| With a local dependency clone | `lsst-run -l ~/work/daf_butler -l . -- pytest ...` |
| Stack CLI tools | `lsst-run -- butler ...`, `lsst-run -- pipetask ...`, `lsst-run -- eups ...` |
| Ad-hoc python | `lsst-run -- python -c "import lsst.afw ..."` |
| Specific build tag | `lsst-run -t b8411 -l . -- pytest ...` |
| Show available tags | `lsst-run --list-tags` |

## Tags

`lsst_distrib` in an lsstsw stack carries only `bNNNN` build tags — `setup -t w_2026_24 lsst_distrib` fails even though individual packages carry weekly tags.
`lsst-run` selects the highest `bNNNN` currently carried by `lsst_distrib` unless `-t` is given, and reports the choice on stderr.

Build tag numbers are local to one EUPS tree and are not stable across a redeployment of that tree.
A tag from an earlier tree will be rejected; run `lsst-run --list-tags` to see what the current tree offers.

## Rules

- Never `pip install` into the stack conda environment.
- Never modify the installed stack under `$EUPS_PATH`; local work happens in clones activated via `-l` (`setup -k -r`).
- When the EUPS environment is the chosen environment, never run bare `python`/`pytest` for code that imports `lsst.*` — always go through `lsst-run`. (If the user chose the pip environment for a dual-use package, ordinary tools apply and this skill stays out of the way.)

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `no active LSST environment` | Ask the user to source `envconfig` or `loadLSST.bash` and restart the agent |
| `ModuleNotFoundError: lsst.<pkg>.version` or local clone won't import | `lsst-run -l . -- scons python` |
| Import picks up stack version instead of local clone | Missing `-l` for that clone |
| `lsst_distrib has no build tag ...` | `lsst-run --list-tags`, pick a listed `bNNNN` |
| Dependency changes in `ups/*.table` not taking effect | None needed; locals are set up on every call |
```

- [ ] **Step 2: Create `skills/lsst-eups/agents/openai.yaml`**

```yaml
interface:
  display_name: "LSST EUPS"
  short_description: "Run LSST Pipelines in the EUPS stack"
  default_prompt: "Use $lsst-eups to run this task in the LSST Science Pipelines EUPS environment."
```

- [ ] **Step 3: Verify the validator accepts it**

```bash
./scripts/validate-skills
grep -n 'claude\|codex\|\.agents\|gemini' skills/lsst-eups/SKILL.md || echo "no hardcoded agent paths"
```

Expected: `1 skill(s) validated`, and no hardcoded agent paths.

- [ ] **Step 4: Commit**

```bash
git add skills/lsst-eups
git commit -m "Write the portable lsst-eups skill instructions

Reconciles the two hand-installed copies into one canonical version.
Drops the hardcoded per-agent invocation path, states the activated
environment prerequisite, generalizes the sandbox note to any harness,
and removes the refresh guidance that the new wrapper makes unnecessary."
```

---

### Task 6: Installer

**Files:**
- Create: `install.sh`, `tests/test-install.sh`

**Interfaces:**
- Consumes: `skills/lsst-eups` from Tasks 3–5.
- Produces: `./install.sh [--claude] [--codex] [--gemini] [--all] [--link|--copy] [--force] [--dry-run] [--uninstall] [SKILL...]`. Exits 0 on success, 1 on a refused conflict or an unknown skill name.

- [ ] **Step 1: Write the failing tests**

Create `tests/test-install.sh`:

```bash
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test-install.sh`
Expected: every check fails because `install.sh` does not exist.

- [ ] **Step 3: Implement `install.sh`**

```bash
#!/usr/bin/env bash
#
# Install this repository's skills into the discovery locations used by
# Claude Code, Codex, and Antigravity.
set -uo pipefail

REPO_ROOT=$( cd "$(dirname "$0")" && pwd -P )
SKILLS_DIR="$REPO_ROOT/skills"

MODE=link
FORCE=0
DRY_RUN=0
UNINSTALL=0
AGENTS=()
REQUESTED=()

usage() {
    cat <<'EOF'
Usage: install.sh [OPTIONS] [SKILL...]

Agents (default: every agent whose home directory already exists):
  --claude          install into ~/.claude/skills
  --codex           install into ~/.agents/skills, or ~/.codex/skills
  --gemini          install into ~/.gemini/config/skills
  --all             install for all three regardless of what is present

Options:
  --link            symlink the skill directory (default)
  --copy            copy the skill directory instead
  --force           replace an existing entry, keeping it as <name>.bak
  --dry-run         print what would happen and change nothing
  --uninstall       remove entries this repository installed
  -h, --help        show this message

With no SKILL arguments every skill under skills/ is installed.
EOF
}

err() { echo "install.sh: $*" >&2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --claude) AGENTS+=(claude); shift ;;
        --codex)  AGENTS+=(codex);  shift ;;
        --gemini) AGENTS+=(gemini); shift ;;
        --all)    AGENTS=(claude codex gemini); shift ;;
        --link)   MODE=link; shift ;;
        --copy)   MODE=copy; shift ;;
        --force)  FORCE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) err "unknown option: $1"; usage >&2; exit 1 ;;
        *) break ;;
    esac
done

while [ $# -gt 0 ]; do
    REQUESTED+=("$1")
    shift
done

# Whether an agent is installed for this user.
agent_present() {
    case "$1" in
        claude) [ -d "$HOME/.claude" ] ;;
        codex)  [ -d "$HOME/.agents" ] || [ -d "$HOME/.codex" ] ;;
        gemini) [ -d "$HOME/.gemini" ] ;;
        *) return 1 ;;
    esac
}

# Exactly one directory per agent, never two, so a skill is never registered
# twice. ~/.agents/skills is the preferred Codex location; ~/.codex/skills is
# still read by current Codex releases and is used when ~/.agents is absent.
target_dir() {
    case "$1" in
        claude) printf '%s\n' "$HOME/.claude/skills" ;;
        codex)
            if [ -d "$HOME/.agents" ]; then
                printf '%s\n' "$HOME/.agents/skills"
            else
                printf '%s\n' "$HOME/.codex/skills"
            fi
            ;;
        gemini) printf '%s\n' "$HOME/.gemini/config/skills" ;;
    esac
}

resolve_dir() { ( cd "$1" 2>/dev/null && pwd -P ); }

# True when target is a symlink resolving to src, or a copy matching src.
installed_from_repo() {
    local target=$1 src=$2
    if [ -L "$target" ]; then
        [ "$(resolve_dir "$target")" = "$(resolve_dir "$src")" ]
        return
    fi
    [ -d "$target" ] && diff -r "$src" "$target" >/dev/null 2>&1
}

if [ ${#AGENTS[@]} -eq 0 ]; then
    for agent in claude codex gemini; do
        agent_present "$agent" && AGENTS+=("$agent")
    done
fi

if [ ${#AGENTS[@]} -eq 0 ]; then
    err "no supported agent found; pass --claude, --codex, --gemini or --all"
    exit 1
fi

AVAILABLE=()
for path in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$path" ] || continue
    AVAILABLE+=("$(basename "$(dirname "$path")")")
done

SELECTED=()
if [ ${#REQUESTED[@]} -eq 0 ]; then
    for have in ${AVAILABLE[@]+"${AVAILABLE[@]}"}; do
        SELECTED+=("$have")
    done
else
    status=0
    for want in ${REQUESTED[@]+"${REQUESTED[@]}"}; do
        found=0
        for have in ${AVAILABLE[@]+"${AVAILABLE[@]}"}; do
            [ "$want" = "$have" ] && found=1
        done
        if [ "$found" = 1 ]; then
            SELECTED+=("$want")
        else
            err "no such skill: $want"
            status=1
        fi
    done
    [ "$status" = 0 ] || exit 1
fi

exit_status=0

for agent in ${AGENTS[@]+"${AGENTS[@]}"}; do
    dest=$(target_dir "$agent")
    for skill in ${SELECTED[@]+"${SELECTED[@]}"}; do
        src="$SKILLS_DIR/$skill"
        target="$dest/$skill"

        if [ "$UNINSTALL" = 1 ]; then
            if [ ! -e "$target" ] && [ ! -L "$target" ]; then
                continue
            fi
            if installed_from_repo "$target" "$src"; then
                if [ "$DRY_RUN" = 1 ]; then
                    echo "would remove $target"
                else
                    rm -rf "$target"
                    echo "removed $target"
                fi
            else
                err "not installed from this repository, leaving alone: $target"
            fi
            continue
        fi

        if [ -e "$target" ] || [ -L "$target" ]; then
            if [ "$MODE" = link ] && [ -L "$target" ] && \
               installed_from_repo "$target" "$src"; then
                echo "up to date: $target"
                continue
            fi
            if [ "$FORCE" != 1 ]; then
                err "$target already exists; pass --force to replace it"
                exit_status=1
                continue
            fi
            if [ "$DRY_RUN" = 1 ]; then
                echo "would move $target aside to $target.bak"
            else
                rm -rf "$target.bak"
                mv "$target" "$target.bak" || { exit_status=1; continue; }
                echo "moved aside: $target -> $target.bak"
            fi
        fi

        if [ "$DRY_RUN" = 1 ]; then
            echo "would install $skill ($MODE) into $dest"
            continue
        fi

        mkdir -p "$dest" || { exit_status=1; continue; }
        if [ "$MODE" = link ]; then
            ln -s "$src" "$target" || { exit_status=1; continue; }
        else
            cp -R "$src" "$target" || { exit_status=1; continue; }
        fi
        echo "installed $skill ($MODE) into $dest"
    done
done

exit "$exit_status"
```

- [ ] **Step 4: Run the tests**

```bash
chmod +x install.sh
bash tests/test-install.sh
shellcheck install.sh tests/test-install.sh
```

Expected: `23 checks, 0 failed`. shellcheck silent.

- [ ] **Step 5: Install for real and confirm the conflict guard**

```bash
./install.sh --dry-run
./install.sh
```

Expected: the dry run lists the actions; the real run refuses to replace the existing real directories at `~/.claude/skills/lsst-eups` and `~/.codex/skills/lsst-eups` and exits 1, telling you to pass `--force`.
Do not pass `--force` yet; Task 9 covers the cutover.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/test-install.sh
git commit -m "Add the skill installer

Symlinks whole skill directories into each agent's discovery location,
defaulting to the agents whose home directory already exists. Uses one
Codex location per run so a skill is never registered twice, and refuses
to replace an existing entry that this repository did not install unless
--force is given."
```

---

### Task 7: README, CONTRIBUTING, and the skills-list check

**Files:**
- Modify: `README.md` (replace entirely), `scripts/validate-skills`, `tests/test-validate-skills.sh`
- Create: `CONTRIBUTING.md`

**Interfaces:**
- Consumes: `install.sh`, `scripts/validate-skills`.
- Produces: validator check that `README.md`'s skills table matches `skills/`.

- [ ] **Step 1: Write the failing test for the skills-list check**

Append to `tests/test-validate-skills.sh`, immediately before the final `finish` line:

```bash
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test-validate-skills.sh`
Expected: the three new checks fail; the validator does not read `README.md` yet.

- [ ] **Step 3: Add the check to `scripts/validate-skills`**

Add this function above `main`:

```python
def check_readme(root: Path, skill_names: list[str], report) -> None:
    """The README skills table must name exactly the skills that exist."""
    readme = root / "README.md"
    if not readme.is_file():
        report(readme, "no README.md")
        return
    text = readme.read_text(encoding="utf-8")
    listed = set(re.findall(r"^\|\s*`([a-z0-9-]+)`\s*\|", text, re.MULTILINE))
    for name in skill_names:
        if name not in listed:
            report(readme, f"skill `{name}` is not listed in README.md")
    for name in sorted(listed - set(skill_names)):
        report(readme, f"README.md lists `{name}`, which is not in skills/")
```

Then call it from `main`, immediately after the `for skill_dir in skill_dirs:` loop:

```python
    check_readme(root, [p.name for p in skill_dirs], report)
```

- [ ] **Step 4: Write `README.md`**

```markdown
# agent-skills

Reusable [Agent Skills](https://code.claude.com/docs/en/skills) maintained by the Rubin Observatory Data Management team.

Each skill is one directory that installs unchanged into Claude Code, OpenAI Codex, and Google Antigravity.
There is one canonical copy of every skill; there are no per-agent forks.

## Quick start

```bash
git clone https://github.com/lsst-dm/agent-skills
cd agent-skills
./install.sh
```

With no arguments the installer targets every agent it finds installed and symlinks each skill into that agent's discovery location.
Restart your agent afterwards so it picks up the new skills.

## Available skills

| Skill | Description |
|---|---|
| `lsst-eups` | Run LSST Science Pipelines commands inside the EUPS stack environment. |

## Installation

```bash
./install.sh                     # every installed agent, every skill
./install.sh --claude            # one agent
./install.sh --all lsst-eups     # one skill, all three agents
./install.sh --copy              # copy instead of symlinking
./install.sh --dry-run           # show what would happen
./install.sh --uninstall         # remove what this repository installed
```

Discovery locations:

| Agent | Location |
|---|---|
| Claude Code | `~/.claude/skills/` |
| Codex | `~/.agents/skills/`, or `~/.codex/skills/` when `~/.agents` is absent |
| Antigravity | `~/.gemini/config/skills/` |

`~/.gemini/config/skills` is the only global location that the Antigravity IDE, the Antigravity CLI, and Antigravity itself all read.
The installer uses exactly one Codex location per run, so a skill is never registered twice.

An existing entry that this repository did not install is never replaced.
The installer reports the conflict and exits non-zero; `--force` moves the existing entry to `<name>.bak` first.

## Updating

Under the default symlink installation, `git pull` is enough — every agent sees the updated skill immediately.

Under `--copy`, re-run `./install.sh --copy --force` after pulling, otherwise the installed copies keep the version they were installed with.

## Creating a skill

```text
skills/my-new-skill/
├── SKILL.md
├── scripts/       # optional executable helpers
├── references/    # optional supporting documentation
└── assets/        # optional templates and static files
```

A minimal `SKILL.md`:

```markdown
---
name: my-new-skill
description: Use when ... — describe the triggering situation, not just the topic.
---

# My New Skill

Instructions go here.
```

The directory name must match the `name` field, and both must be lowercase words separated by hyphens.
Add the skill to the table above; CI checks that the list matches `skills/`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow.

## Portability guidelines

Write agent-neutral instructions by default.
Describe what to do in terms of ordinary commands and files rather than a particular agent's tool names, slash commands, or permission prompts.

Never hardcode a skill's own installed path.
That path differs per agent and per install mode, so refer to helpers relatively as `scripts/<name>`; every supported agent tells the model where the skill directory is.

Put reusable deterministic operations in `scripts/` as ordinary command-line programs with explicit arguments, documented dependencies, useful exit codes, and clean separation of stdout and stderr.
Put detailed supporting material in `references/` rather than bloating `SKILL.md`.

Where behavior genuinely differs between agents, express the difference conditionally inside the one `SKILL.md`.
Forking a skill per agent is a last resort.

Agent-specific metadata that other agents ignore, such as `agents/openai.yaml` for Codex, may live in the canonical skill directory because it is additive.

## Security

A skill is executable instruction, and anything under `scripts/` is executable code that your agent may run with your privileges.

Installing a skill from this repository grants it that reach, and under the default symlink installation a `git pull` updates what your agents execute without any further action from you.
Review changes before pulling or installing, and treat skill review with the same care as any other code review.

## Validation

```bash
./scripts/validate-skills   # layout, frontmatter, references, portability
./tests/run-all.sh          # validator plus the test suite
```

Both run in CI on every push and pull request.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
```

- [ ] **Step 5: Write `CONTRIBUTING.md`**

```markdown
# Contributing

## Adding a skill

Create `skills/<name>/SKILL.md` with `name` and `description` frontmatter, where `name` matches the directory and is lowercase words separated by hyphens.

Add optional `scripts/`, `references/`, and `assets/` subdirectories only where the skill needs them.

Add the skill to the table in [README.md](README.md); the validator checks that the table matches `skills/`.

## Writing a good description

The `description` is what the agent matches against to decide whether to load the skill, so describe the triggering situation rather than the topic.
Name the tools, commands, and phrases that should pull the skill in.

## Portability

Skills must work in Claude Code, Codex, and Antigravity from one copy.
See the portability guidelines in [README.md](README.md).

The rule the validator enforces mechanically is that a skill must never name `~/.claude/skills`, `~/.agents/skills`, `~/.codex/skills`, or `~/.gemini/.../skills`.

## Helper scripts

Helper scripts are ordinary command-line programs.
They take explicit arguments, document their dependencies, return useful exit codes, write results to stdout and diagnostics to stderr, and do not depend on any agent's internals.

Shell scripts must run under bash 3.2, because that is what macOS ships.
Avoid associative arrays, `readlink -f`, and `sort -V`.

## Running the checks

```bash
./scripts/validate-skills
./tests/run-all.sh
```

Install `shellcheck` for the full set of shell checks; the validator skips it when it is absent.

Tests that need a live LSST stack skip themselves when no environment is active, so the suite passes on a machine without one.

## Review

Changes go through pull request review.
Skills and their scripts are executable instructions that run on other people's machines, so review them with the same care as any other code.
```

- [ ] **Step 6: Run everything**

```bash
bash tests/test-validate-skills.sh
./tests/run-all.sh
```

Expected: `19 checks, 0 failed` for the validator tests, and `run-all.sh` exits 0.

- [ ] **Step 7: Commit**

```bash
git add README.md CONTRIBUTING.md scripts/validate-skills tests/test-validate-skills.sh
git commit -m "Add README, contributor guide, and README skills-list check

The validator now checks that the README skills table names exactly the
skills present under skills/, so the list cannot go stale."
```

---

### Task 8: Agent guidance file and its aliases

**Files:**
- Create: `AGENTS.md`, `CLAUDE.md` (symlink), `GEMINI.md` (symlink)
- Modify: `scripts/validate-skills`, `tests/test-validate-skills.sh`

`AGENTS.md` is the canonical copy because Codex and Antigravity both read it.
Claude Code reads `CLAUDE.md`, Gemini CLI reads `GEMINI.md`, and Antigravity reads `GEMINI.md` in addition to `AGENTS.md`, letting it take precedence on conflict.
Pointing both aliases at one inode means there is nothing to conflict and one file to maintain.

**Interfaces:**
- Consumes: `scripts/validate-skills` from Tasks 2 and 7.
- Produces: validator check that `CLAUDE.md` and `GEMINI.md` are symlinks named `AGENTS.md`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test-validate-skills.sh`, immediately before the final `finish` line:

```bash
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test-validate-skills.sh`
Expected: the four new checks fail; the validator does not look at the guidance files yet.

- [ ] **Step 3: Add the check to `scripts/validate-skills`**

Add this constant beside the other module-level constants:

```python
# Claude Code reads CLAUDE.md, Gemini CLI reads GEMINI.md, and Antigravity
# reads GEMINI.md on top of AGENTS.md. Symlinking the aliases to one canonical
# file keeps a single copy and removes any possibility of conflict.
AGENT_GUIDE_ALIASES = ("CLAUDE.md", "GEMINI.md")
```

Add this function above `main`:

```python
def check_agent_guides(root: Path, report) -> None:
    """The per-agent guidance files must be symlinks to AGENTS.md."""
    canonical = root / "AGENTS.md"
    if not canonical.is_file():
        report(canonical, "no AGENTS.md")
        return
    for alias in AGENT_GUIDE_ALIASES:
        path = root / alias
        if not path.is_symlink():
            if path.exists():
                report(path, "must be a symlink to AGENTS.md, not a copy")
            else:
                report(path, "missing; must be a symlink to AGENTS.md")
            continue
        target = os.readlink(path)
        if target != "AGENTS.md":
            report(path, f"symlink points at {target}, expected AGENTS.md")
```

Then call it from `main`, immediately after the `check_readme(...)` call:

```python
    check_agent_guides(root, report)
```

- [ ] **Step 4: Write `AGENTS.md`**

```markdown
# Working in this repository

This repository holds reusable Agent Skills maintained by the Rubin Observatory Data Management team.
Every skill installs unchanged into Claude Code, Codex, and Antigravity from one canonical copy.

`CLAUDE.md` and `GEMINI.md` are symlinks to this file so that every agent reads the same guidance.
Edit `AGENTS.md` and never replace an alias with a copy; the validator rejects that.

## Before you finish

Run both of these and confirm they pass:

```bash
./scripts/validate-skills
./tests/run-all.sh
```

Do not push to the remote. Commit locally and leave pushing to a human.

## Adding a skill

Create one directory under `skills/`:

```text
skills/my-new-skill/
├── SKILL.md       # required
├── scripts/       # optional executable helpers
├── references/    # optional supporting documentation
└── assets/        # optional templates and static files
```

Create the optional subdirectories only when the skill actually needs them.

`SKILL.md` starts with YAML frontmatter carrying `name` and `description`:

```markdown
---
name: my-new-skill
description: Use when ... — describe the situation that should trigger the skill.
---

# My New Skill

Instructions go here.
```

The `name` must equal the directory name and must be lowercase words separated by hyphens.

Add the skill to the table in `README.md`; the validator checks that the table matches `skills/`.

## Writing the description

The `description` is what an agent matches against when deciding whether to load the skill, so describe the triggering situation rather than the topic.
Name the concrete tools, commands, error messages, and phrases that should pull the skill in.

Prefer "Use when running pytest against a package that imports `lsst.*`" over "Helps with testing".

## Portability is the point

Write agent-neutral instructions.
Describe what to do in terms of ordinary commands and files, not a particular agent's tool names, slash commands, or permission prompts.

**Never hardcode a skill's own installed path.**
That path differs per agent and per install mode, so refer to helpers relatively as `scripts/<name>`.
Every supported agent tells the model where the skill directory is.
The validator rejects any `SKILL.md` naming `~/.claude/skills`, `~/.agents/skills`, `~/.codex/skills`, or a Gemini skills path.

Do not create per-agent copies of a skill.
Where behavior genuinely differs between agents, express the difference conditionally inside the one `SKILL.md`.
Two divergent copies of this repository's first skill are what motivated it existing; do not recreate that problem.

Keep `SKILL.md` focused.
Put detailed supporting material in `references/` and reusable deterministic operations in `scripts/`.

Agent-specific metadata that other agents ignore, such as `agents/openai.yaml` for Codex, is additive and belongs in the canonical skill directory.

## Helper scripts

Helper scripts are ordinary command-line programs.
They take explicit arguments, document their dependencies, return useful exit codes, write results to stdout and diagnostics to stderr, and depend on no agent's internals.

Everything under `scripts/` must be executable.

Shell scripts must run under **bash 3.2**, which is what macOS ships.
No associative arrays, no `${var,,}`, no `mapfile`.
Expand possibly-empty arrays as `${arr[@]+"${arr[@]}"}`.

Avoid GNU-only tool flags.
No `readlink -f`, no `sort -V`, no bare `sed -i`.
Resolve a directory with `( cd "$d" && pwd -P )`.

Shell scripts must pass `shellcheck` with no warnings.

Python helpers use the standard library only.
Nothing in this repository may require a `pip install`.

## Prose style

Write one sentence per line in Markdown.
Use American English spelling.

Comments and documentation describe the code as it is today.
Do not reference transient plans, task numbers, or past mistakes.

## Security

A skill is executable instruction and anything under `scripts/` is code that runs with the user's privileges.
Under the default symlink installation a `git pull` changes what every installed agent executes.

Treat skill review with the same care as any other code review.
```

- [ ] **Step 5: Create the symlinks and point the README at them**

```bash
ln -s AGENTS.md CLAUDE.md
ln -s AGENTS.md GEMINI.md
```

Add this subsection to `README.md`, immediately before `## Security`:

```markdown
## Guidance for agents

[AGENTS.md](AGENTS.md) carries the instructions an agent needs when adding or editing a skill here.

`CLAUDE.md` and `GEMINI.md` are symlinks to it, so Claude Code, Codex, Gemini CLI, and Antigravity all read the same guidance from one file.
Edit `AGENTS.md`; the validator rejects an alias that has been replaced by a copy.
```

- [ ] **Step 6: Verify the symlinks and the checks**

```bash
ls -l CLAUDE.md GEMINI.md
git check-attr -a CLAUDE.md >/dev/null 2>&1
bash tests/test-validate-skills.sh
./tests/run-all.sh
```

Expected: `ls -l` shows both as `-> AGENTS.md`. Validator tests report `23 checks, 0 failed`, and `run-all.sh` exits 0.

- [ ] **Step 7: Confirm git stores them as symlinks, not copies**

```bash
git add AGENTS.md CLAUDE.md GEMINI.md
git ls-files -s CLAUDE.md GEMINI.md
```

Expected: mode `120000` for both, which is git's symlink mode.
Mode `100644` would mean a copy was committed and the single-source property is already lost.

- [ ] **Step 8: Commit**

```bash
git add AGENTS.md CLAUDE.md GEMINI.md scripts/validate-skills tests/test-validate-skills.sh
git commit -m "Add agent guidance with per-agent symlink aliases

AGENTS.md is canonical because Codex and Antigravity both read it, and
CLAUDE.md and GEMINI.md symlink to it so Claude Code and Gemini find the
same content. The validator rejects an alias that is missing or has been
replaced by a copy, since divergent copies are the failure this
repository exists to prevent."
```

---

### Task 9: CI and cutover

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `scripts/validate-skills`, `tests/run-all.sh`.
- Produces: CI on push and pull request.

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: ["**"]
  pull_request:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install shellcheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck

      - name: Validate skills
        run: ./scripts/validate-skills

      - name: Run tests
        run: ./tests/run-all.sh
```

- [ ] **Step 2: Verify the workflow steps pass locally**

```bash
./scripts/validate-skills
./tests/run-all.sh
```

Expected: both exit 0.

- [ ] **Step 3: Confirm the suite passes without a stack**

```bash
env -u EUPS_PATH -u EUPS_DIR -u LSST_CONDA_ENV_NAME -u LSSTSW ./tests/run-all.sh
```

Expected: exit 0, with `lsst-run` reporting that stack-dependent checks were skipped.
This is what CI will do.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "Add CI running the validator and test suite"
```

- [ ] **Step 5: Cut over the hand-installed copies**

The divergent hand-installed copies are still in place. Replace them with links to this repository:

```bash
diff -r ~/.claude/skills/lsst-eups skills/lsst-eups
diff -r ~/.codex/skills/lsst-eups  skills/lsst-eups
./install.sh --force
ls -l ~/.claude/skills/lsst-eups ~/.codex/skills/lsst-eups
```

Expected: both are now symlinks into this repository, with the previous contents preserved at `lsst-eups.bak`.
Review the diffs first and confirm nothing in the old copies is worth keeping.

- [ ] **Step 6: Smoke test the installed skill**

```bash
~/.claude/skills/lsst-eups/scripts/lsst-run --list-tags
~/.claude/skills/lsst-eups/scripts/lsst-run -- python -c 'import lsst.daf.butler; print("ok")'
```

Expected: the tag list prints, and the import succeeds through the symlinked copy.

- [ ] **Step 7: Remove the backups once satisfied**

```bash
rm -rf ~/.claude/skills/lsst-eups.bak ~/.codex/skills/lsst-eups.bak
```

---

## Verification against a second environment flavor

The `loadLSST.sh` branch of `activation_script` cannot be exercised by the lsstsw tree, which supplies `bin/envconfig` and sets `LSSTSW`.

Once the lsstinstall-derived test installation exists, verify it from a shell where that tree is activated and `LSSTSW` is unset:

```bash
source <test-tree>/loadLSST.bash
env -u LSSTSW bash -c 'cd <repo> && ./skills/lsst-eups/scripts/lsst-run --list-tags'
env -u LSSTSW bash -c 'cd <repo> && ./skills/lsst-eups/scripts/lsst-run -- python -c "import lsst.daf.butler; print(\"ok\")"'
```

Expected: the tree root is found three levels above `$CONDA_PREFIX`, `loadLSST.sh` is used, a separate snapshot is created because `LSST_CONDA_ENV_NAME` and `EUPS_PATH` differ, and the import succeeds.

If the root derivation fails for that layout, fix `activation_script` and add a regression test that asserts the derived root for both layouts.
