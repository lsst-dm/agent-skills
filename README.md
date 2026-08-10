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

Under `--copy`, re-run `./install.sh --copy` after pulling to refresh the installed copies.
A copy this installer made records its origin, so re-running in the same mode refreshes it in place without `--force`.

Switching an installed skill between link and copy needs `--force`, so a routine `./install.sh` will not quietly turn a copy back into a symlink.

## Writing a skill

The rules for writing a skill — layout, frontmatter, portability, helper scripts, and the checks to run — live in one place, [AGENTS.md](AGENTS.md).

That file is what Claude Code, Codex, Gemini CLI, and Antigravity all load when working in this repository, through the `CLAUDE.md` and `GEMINI.md` symlinks, and it is equally the reference for a person.
Keeping the rules in a single file is the point: this repository exists because two hand-installed copies of one skill drifted apart, and its own documentation is held to the same standard.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the review workflow.

## Security

Installing a skill grants it real reach.
A skill is executable instruction, and anything under `scripts/` is code your agent may run with your privileges.

Under the default symlink installation, a `git pull` changes what your agents execute with no further action from you.
Review what you pull, and treat a skill the way you would treat any other code you are about to run.

## Validation

```bash
./tests/run-all.sh
```

This runs the skill validator and the full test suite, and CI runs the same checks on Linux and macOS for every push and pull request.

[AGENTS.md](AGENTS.md) covers the prerequisites and the individual commands.

## License

BSD 3-Clause.
See [LICENSE](LICENSE).
