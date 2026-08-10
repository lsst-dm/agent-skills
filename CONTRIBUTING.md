# Contributing

## Where the rules live

[AGENTS.md](AGENTS.md) is the single source of truth for how skills are written here: the directory layout, the frontmatter requirements, the portability rules, the constraints on helper scripts, and the checks to run before you finish.

It is written to be read by an agent working in this repository, and it is equally the reference for a person doing the same work.
Read it before adding or changing a skill.

This file covers only the workflow around that work.

## Workflow

Work on a branch and open a pull request.

Run the checks described in [AGENTS.md](AGENTS.md) before pushing; CI runs the same ones on Linux and macOS.

Add any new skill to the table in [README.md](README.md).
The validator fails if that table and `skills/` disagree, so this cannot be forgotten silently.

## Review

Changes go through pull request review.

A skill is executable instruction that runs on other people's machines, so review one with the same care as any other code.
Pay particular attention to anything under `scripts/`, and to changes in what a skill tells an agent to do without asking.

## Changing the rules themselves

Rules belong in [AGENTS.md](AGENTS.md) and nowhere else.

If you find a rule restated in `README.md` or in this file, that is a defect worth fixing rather than a copy worth updating.
Divergent copies of the same content are the problem this repository exists to prevent, and its own documentation is not exempt.
