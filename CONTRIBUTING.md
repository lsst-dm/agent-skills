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

[AGENTS.md](AGENTS.md) states the same rules in the form an agent working in this repository reads.
Keep the two in step when either changes.

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
