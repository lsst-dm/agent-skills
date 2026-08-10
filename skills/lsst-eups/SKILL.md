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
