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
| Tests, one file | `lsst-run -l . -- pytest tests/test_foo.py` |
| Whole suite, package with C++ tests | `lsst-run -l . -- scons -Q -j 8 tests` |
| Build after C++ edits | `lsst-run -l . -- scons -Q -j 8` (the default targets are whichever of `lib`, `python`, `shebang`, `tests`, `examples`, `doc` have a directory, so this also runs the tests) |
| Compile the C++ library only | `lsst-run -l . -- scons -Q -j 8 lib` (compiles `src/**/*.cc` into the shared library; `scons python` builds the pybind11 modules on top of it) |
| Make fresh clone importable | `lsst-run -l . -- scons version` (generates the gitignored `version.py`) |
| Make command-line tools runnable | `lsst-run -l . -- scons bin` (generates the gitignored `bin/` wrappers, both those from `[project.scripts]` and any shebang-rewritten from a legacy `bin.src/`) |
| Register the package's Python entry points | `lsst-run -l . -- scons pkginfo` (generates the gitignored `python/*.dist-info`) |
| All three at once, for a fresh clone or worktree | `lsst-run -l . -- scons version bin pkginfo` |
| Entry points or `[project.scripts]` changed in `pyproject.toml` | `lsst-run -l . -- scons pkginfo bin` |
| With a local dependency clone | `lsst-run -l ~/work/daf_butler -l . -- pytest ...` |
| Stack CLI tools | `lsst-run -- butler ...`, `lsst-run -- pipetask ...`, `lsst-run -- eups ...` |
| Ad-hoc python | `lsst-run -- python -c "import lsst.afw ..."` |
| Specific tag | `lsst-run -t b8411 -l . -- pytest ...`, `lsst-run -t w_2026_05 -- ...` |
| Show available tags | `lsst-run --list-tags` |

The target is `tests`, plural; `scons test` is not a target and fails.

For a pure-Python package `pytest` and `scons tests` run the same tests, and `pytest` is the faster, more direct choice.
For a package that also carries C++ tests as `tests/*.cc`, only `scons tests` runs the whole suite: it compiles and runs those binaries as well as the Python tests, so a bare `pytest` silently covers only half the suite.
`scons` passes `-j N` through to pytest as `-n N`, making `scons -j 8 tests` the equivalent of `pytest -n 8 tests` plus the C++ binaries.

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
| `ModuleNotFoundError: lsst.<pkg>.version` or local clone won't import | `lsst-run -l . -- scons version` |
| `FileNotFoundError` for `butler`, `pipetask`, or another of the package's own commands, in a test that runs it as a subprocess | `lsst-run -l . -- scons bin`. The clone's `bin/` is on `PATH` but is gitignored and empty until built, so the command is missing rather than shadowed |
| A plugin the package registers is missing: a `butler` subcommand not listed, an `importlib.metadata.entry_points()` group coming back empty | `lsst-run -l . -- scons pkginfo`. Entry points are read from the generated `python/*.dist-info/entry_points.txt`, never from `pyproject.toml` directly, so editing the toml alone changes nothing |
| `scons python` reports `Nothing to be done` and nothing appears | It is not the target that generates `version.py`, `bin/`, or the entry points; use `scons version bin pkginfo` |
| Import picks up stack version instead of local clone | Missing `-l` for that clone |
| `dlopen` / `Library not loaded` for a stack `.so` | A `sh -c '...'` wrapper inside `lsst-run` discarded the library environment; pass the command to `lsst-run` directly instead |
| `lsst_distrib has no tag ...` | Pick one of the tags the error lists, or run `lsst-run --list-tags` |
| Dependency changes in `ups/*.table` not taking effect | None needed; locals are set up on every call |
