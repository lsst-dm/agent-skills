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
