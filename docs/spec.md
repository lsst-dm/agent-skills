# Shared Claude Code / Codex Skills Repository

## Goal

Create a Git repository for maintaining and distributing reusable agent skills across the engineering team.

The primary requirement is that skills should work with **both Claude Code and OpenAI Codex** wherever possible, without maintaining two copies of the same skill.

Git should be the source of truth.

## Background

Claude Code and Codex both support the Agent Skills convention based around a skill directory containing a `SKILL.md` entrypoint.

A portable skill generally looks like:

```text
skill-name/
├── SKILL.md
├── scripts/       # optional executable helpers
├── references/    # optional documentation/context
└── assets/        # optional templates/static files
```

`SKILL.md` contains YAML frontmatter followed by the skill instructions.

For example:

```markdown
---
name: validate-github-actions
description: Validate GitHub Actions workflows, including syntax, action versions, permissions, and repository-specific policies.
---

# Validate GitHub Actions

Instructions go here.
```

The skill name should normally be lowercase and hyphen-separated, and the directory name should match the skill name.

## Proposed Repository Structure

Use a single repository containing multiple independently installable skills:

```text
agent-skills/
├── README.md
├── LICENSE
├── skills/
│   ├── skill-one/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   ├── references/
│   │   └── assets/
│   └── skill-two/
│       └── SKILL.md
├── tests/
└── install.sh
```

Not every skill needs `scripts/`, `references/`, or `assets/`. They should only exist when needed.

## One Canonical Skill, Not Claude/Codex Copies

Do **not** structure the repository like this unless a genuine implementation difference requires it:

```text
skills/
├── claude/
│   └── my-skill/
└── codex/
    └── my-skill/
```

Instead, maintain one canonical implementation:

```text
skills/
└── my-skill/
    ├── SKILL.md
    ├── scripts/
    └── references/
```

The same directory should then be installed into the appropriate discovery location for each client.

## Skill Discovery Locations

The relevant user-level locations are:

```text
Claude Code:
~/.claude/skills/<skill-name>/

Codex:
~/.agents/skills/<skill-name>/
```

`.agents/skills` should be treated as the preferred current Codex location.

There has also historically been a Codex-specific location:

```text
~/.codex/skills/
```

Consider whether the installer should optionally support this as a compatibility location, but do not make it the canonical repository layout.

For project-local skills, the corresponding convention is approximately:

```text
.claude/skills/
.agents/skills/
```

## Installation Strategy

The repository should include an installer that allows team members to install skills for either or both agents.

Desired interface:

```bash
./install.sh --claude
./install.sh --codex
./install.sh --all
```

It should also be possible to install an individual skill, for example:

```bash
./install.sh --all validate-github-actions
```

Exact CLI design can be improved if there is a cleaner approach.

The installer should discover directories beneath `skills/` rather than requiring a hard-coded list of skills.

### Copy vs Symlink

Evaluate the tradeoffs between copying and symlinking.

The desirable development experience is for changes to a checked-out skills repository to become immediately available to the agents, which favors symlinks.

However:

- directory symlinks should be preferred over symlinking only `SKILL.md`;
- Windows compatibility may favor copying;
- the installer should not unexpectedly destroy user-maintained directories.

A reasonable design might support:

```bash
./install.sh --all --link
./install.sh --all --copy
```

with a sensible documented default.

If symlinks are used, link the complete skill directory.

For example:

```text
~/.claude/skills/my-skill -> ~/src/agent-skills/skills/my-skill
~/.agents/skills/my-skill -> ~/src/agent-skills/skills/my-skill
```

## Cross-Agent Portability

Skills should be agent-neutral by default.

Prefer instructions like:

```markdown
Search the repository for workflow files.

Run the repository's configured validators.

Report the file, line, rule, and suggested correction.
```

Avoid unnecessary assumptions such as:

```markdown
Use Claude Code's AskUserQuestion tool.
Invoke a Codex-specific command.
Use a slash command that only exists in one agent.
```

Scripts included in a skill should ideally behave like ordinary command-line programs with:

- explicit arguments;
- documented dependencies;
- deterministic behavior where practical;
- useful exit codes;
- useful stdout/stderr;
- no dependency on Claude or Codex internals unless unavoidable.

## Handling Agent-Specific Behavior

Some workflows may genuinely require agent-specific functionality.

Do not immediately fork the entire skill.

First see whether a single `SKILL.md` can express the difference conditionally, for example:

```markdown
## Agent-specific behavior

When running in Claude Code, use the available Claude interaction and permission mechanisms.

When running in Codex, use the equivalent Codex mechanisms.

Do not assume a client-specific mechanism exists unless it is available in the current environment.
```

If substantial differences really are necessary, factor out as much common functionality as possible rather than maintaining two unrelated copies.

For example:

```text
skills/
├── my-skill/
│   ├── SKILL.md
│   ├── scripts/
│   │   └── common-validator.py
│   └── references/
│       └── common-policy.md
│
├── my-skill-claude/
│   └── SKILL.md
│
└── my-skill-codex/
    └── SKILL.md
```

This should be the exception rather than the default.

## Validation / CI

Add automated validation for skills.

At minimum CI should check:

1. Every immediate skill directory under `skills/` contains `SKILL.md`.
2. YAML frontmatter parses correctly.
3. Required fields such as `name` and `description` are present.
4. `name` matches the containing directory.
5. Skill names conform to the expected lowercase/hyphen convention.
6. Referenced files exist.
7. Executable scripts pass appropriate syntax/static checks where practical.
8. Shell scripts pass `shellcheck` if available.
9. Python helpers compile or otherwise pass a minimal validation.
10. Broken relative links from `SKILL.md` are detected where practical.

Keep validation simple enough that contributors can run it locally.

A command such as this would be useful:

```bash
make validate
```

or:

```bash
./scripts/validate-skills
```

## README

Create a useful top-level README covering:

### What this repository is

Explain that it contains team-maintained reusable skills for coding agents, currently targeting Claude Code and Codex.

### Quick start

Something approximately like:

```bash
git clone <repo>
cd agent-skills

./install.sh --all
```

### Available skills

Document how users can see the available skills.

Ideally generate or validate this list from `skills/` so it does not become stale.

### Creating a skill

Document the expected structure:

```text
skills/my-new-skill/
├── SKILL.md
├── scripts/
├── references/
└── assets/
```

Include a minimal `SKILL.md` example.

### Portability guidelines

Explain:

- write agent-neutral instructions by default;
- avoid Claude/Codex-specific behavior unless necessary;
- use ordinary CLI programs for helper scripts;
- put detailed supporting material in `references/`;
- put reusable deterministic operations in `scripts/`;
- avoid bloating `SKILL.md` with large reference material.

### Installation

Explain Claude and Codex discovery locations and how the installer works.

### Updating

Explain what happens after `git pull`, especially under copy vs symlink installation modes.

### Security

Call out that skills and particularly scripts are effectively executable agent instructions/code.

Team members should review changes before installing/updating skills.

## Versioning / Team Distribution

Git is the distribution mechanism.

Recommended workflow:

1. Team member clones the repository.
2. Team member runs the installer.
3. Skills appear in Claude Code and/or Codex.
4. Updates come through normal Git pulls.
5. Changes to skills go through code review.

Do not invent a complex package registry unless there is a demonstrated need.

Git tags/releases may eventually be useful if users need pinned versions.

## Initial Implementation Request

Please inspect the current repository and implement the foundations described above.

Specifically:

1. Establish or normalize the `skills/<skill-name>/` layout.
2. Preserve any existing skill content.
3. Add an installer supporting Claude, Codex, and both.
4. Prefer one canonical copy of each skill.
5. Support a safe link/copy installation strategy.
6. Add skill validation.
7. Add appropriate CI for the validation.
8. Write the top-level README.
9. Add contributor documentation if it improves clarity.
10. Keep the implementation simple and maintainable.

Before introducing dependencies, prefer standard shell/Python functionality already available on normal developer machines.

Do not introduce separate Claude and Codex versions of an existing skill unless inspection of the skill shows that this is actually necessary.

## Design Principles

Optimize for:

- one source of truth;
- portability between agents;
- low maintenance overhead;
- easy installation;
- easy contribution;
- code reviewability;
- deterministic helper scripts;
- minimal agent-specific coupling;
- gradual extension as more skills are added.

Avoid premature infrastructure.

The desired end state is that a team member can clone one repository, run roughly:

```bash
./install.sh --all
```

and immediately have the team's skills available in both Claude Code and Codex.
