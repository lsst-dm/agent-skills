---
name: lsst-eups
description: Use when work on an LSST Science Pipelines package needs the EUPS stack environment — running pytest, scons, butler, pipetask, eups, or python importing lsst.* against lsst_distrib — or when the user mentions EUPS, lsstsw, "setup lsst_distrib", the stack environment, or bNNNN/weekly build tags.
---

# LSST EUPS Stack Environment

## Overview

Run every stack-dependent command through `scripts/lsst-run` in this skill's directory.
Invoke it by its path within this skill directory; the examples below write `lsst-run` for brevity.

It runs the command against a pristine environment holding `lsst_distrib` at a chosen tag plus any local package clones named on the command line.
That environment is cached, so only the first call per tag pays the few seconds of initialization and later calls add about a quarter of a second.

Each command runs in a fresh shell, so environment variables never persist from one call to the next.
Never try to "activate" the environment once and reuse it, and never hand-roll `source envconfig && setup ...` chains, because sourcing inside a pipeline silently discards the environment.

```
lsst-run [-t TAG] [-l PATH]... [--list-tags] [--] COMMAND [ARGS...]
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
| Specific tag | `lsst-run -t b8411 -l . -- pytest ...`, `lsst-run -t w_2026_05 -- ...` |
| Show available tags | `lsst-run --list-tags` |

## Tags

Which tags `lsst_distrib` carries depends on how the stack was built.
An lsstsw stack numbers its own builds `bNNNN`, and there `setup -t w_2026_24 lsst_distrib` fails even though individual packages carry weekly tags.
A shared installation built by lsstinstall, such as one at a data facility, carries the permanent weekly tags `w_YYYY_WW` instead, and a release installation carries `vNN_N_N`.

Unless `-t` is given, `lsst-run` picks the newest tag of the most specific family the stack has — builds, then weeklies, then releases, then dailies — and reports the choice on stderr.
Run `lsst-run --list-tags` to see what the current stack actually offers.

`-t` accepts any of those forms, and rejects a movable tag such as `current`.
A movable tag would fix the cached environment to whatever it pointed at when the cache was built, which is the one thing the cache must never do.

Build tag numbers are local to one EUPS tree and are not stable across a redeployment of that tree.
A tag from an earlier tree will be rejected; `--list-tags` shows what this one has.

## Rules

- Never `pip install` into the stack conda environment.
- Never modify the installed stack under `$EUPS_PATH`; local work happens in clones activated via `-l` (`setup -k -r`).
- When the EUPS environment is the chosen environment, never run bare `python`/`pytest` for code that imports `lsst.*` — always go through `lsst-run`.
  If the user chose the pip environment for a dual-use package, ordinary tools apply and this skill stays out of the way.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `no active LSST environment` | Ask the user to source `envconfig` or `loadLSST.bash` and restart the agent |
| `ModuleNotFoundError: lsst.<pkg>.version` or local clone won't import | `lsst-run -l . -- scons python` |
| Import picks up stack version instead of local clone | Missing `-l` for that clone |
| `lsst_distrib has no tag ...` | Pick one of the tags the error lists, or run `lsst-run --list-tags` |
| Dependency changes in `ups/*.table` not taking effect | None needed; locals are set up on every call |
