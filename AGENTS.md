# Working in this repository

This repository holds reusable Agent Skills maintained by the Rubin Observatory Data Management team.
Every skill installs unchanged into Claude Code, Codex, and Antigravity from one canonical copy.

**This file is the single source of truth for how skills are written here**, for agents and people alike.
`README.md` describes what the repository is and how to install from it; `CONTRIBUTING.md` covers the review workflow.
Neither restates the rules below, so there is one place to change when a rule changes.

`CLAUDE.md` and `GEMINI.md` are symlinks to this file so that every agent reads the same guidance.
Edit `AGENTS.md` and never replace an alias with a copy; the validator rejects that.

## Before you finish

The validator needs PyYAML.
Any Science Pipelines conda environment already provides it; otherwise install the development dependencies with `python3 -m pip install -r requirements-dev.txt`.

Run both of these and confirm they pass:

```bash
./scripts/validate-skills
./tests/run-all.sh
```

Install `shellcheck` for the full set of shell checks; the validator skips it when absent.

Tests needing a live LSST stack skip themselves when no environment is active, so the suite passes on a machine without one.

To check the bash 3.2 floor that macOS ships, run the suite under the system bash:

```bash
BASH_BIN=/bin/bash ./tests/run-all.sh
```

CI does this automatically on its macOS leg.

Do not push to the remote.
Commit locally and leave pushing to a human.

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

Watch for tool flags that differ between the BSD utilities macOS ships and the GNU ones on Linux.
`sed -i` is the one that actually breaks: BSD requires a backup suffix argument, so write `sed -i ''`, or `sed -i.bak` and remove the backup, or use a temporary file.

`sort -V` and `readlink -f` both work on current macOS and Linux, so they are allowed.
Prefer `( cd "$d" && pwd -P )` for resolving a directory anyway, since it needs no flag at all and works on any shell.

Shell scripts must pass `shellcheck` with no warnings.

A skill's own helpers should lean on the standard library, or on packages already present in the environment the skill targets.
The `lsst-eups` skill, for instance, may rely on anything in the Science Pipelines conda environment, because that environment is its prerequisite.

The repository's own tooling is a different matter.
`scripts/validate-skills` requires PyYAML, since a skill's frontmatter and its per-agent metadata are YAML and hand-rolled parsing of them was a recurring source of bugs.
Development dependencies are listed in `requirements-dev.txt`.

## Prose style

Write one sentence per line in Markdown.
Use American English spelling.

Comments and documentation describe the code as it is today.
Do not reference transient plans, task numbers, or past mistakes.

## Security

What you write here runs on other people's machines.
A skill is executable instruction, and anything under `scripts/` is code their agent may run with their privileges.
Under the default symlink installation a `git pull` changes what every installed agent executes, with no further action from them.

Write accordingly, and review changes with the same care as any other code.
