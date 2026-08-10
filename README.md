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

The installer never deletes a `<name>.bak`.
If one already exists it refuses and says so, because the alternative is destroying the only remaining copy of whatever an earlier `--force` preserved.
Move or remove the old `.bak` before running `--force` again.

## Updating

Under the default symlink installation, `git pull` is enough — every agent sees the updated skill immediately.

Under `--copy`, re-run `./install.sh --copy` after pulling, otherwise the installed copies keep the version they were installed with.
A copy this installer made records its origin, so re-running refreshes it in place without needing `--force`.

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

BSD 3-Clause.
See [LICENSE](LICENSE).
