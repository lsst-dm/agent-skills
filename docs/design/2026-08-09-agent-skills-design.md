# agent-skills — Design

Date: 2026-08-09

## Goal

Provide a single Git repository holding the Rubin Data Management team's reusable agent skills, installable into Claude Code, OpenAI Codex, and Google Antigravity from one canonical copy per skill.
Git is the source of truth and the distribution mechanism.

The `lsst-eups` skill is the proof of concept.

## Motivating evidence

The `lsst-eups` skill is currently installed twice, by hand, and the two copies have already diverged:

- `~/.claude/skills/lsst-eups` and `~/.codex/skills/lsst-eups` hardcode their own differing install paths in `SKILL.md`.
- The Claude copy fixed the build-tag parser to split colon-separated tag lists; the Codex copy still carries the older version that trusts tag position.
- The Codex copy carries a sandbox note and an `agents/openai.yaml` that the Claude copy lacks.

This divergence is the problem the repository exists to prevent.

## Scope

In scope: repository layout, installer, validator, CI, contributor documentation, and a corrected and portable `lsst-eups` skill.

Out of scope: a package registry, version pinning beyond Git tags, and any additional skills.

## Repository layout

```text
agent-skills/
├── README.md
├── LICENSE                      # BSD 3-Clause
├── CONTRIBUTING.md
├── AGENTS.md                    # canonical agent guidance
├── CLAUDE.md -> AGENTS.md
├── GEMINI.md -> AGENTS.md
├── install.sh
├── skills/
│   └── lsst-eups/
│       ├── SKILL.md
│       ├── agents/
│       │   └── openai.yaml      # Codex-only metadata, ignored by other agents
│       └── scripts/
│           └── lsst-run
├── scripts/
│   └── validate-skills          # python3, requires PyYAML
├── tests/
│   ├── run-all.sh
│   ├── test-validate-skills.sh
│   └── test-lsst-run.sh
├── docs/
│   ├── design/
│   │   └── 2026-08-09-agent-skills-design.md
│   └── spec.md                  # the original brief, kept for provenance
└── .github/
    └── workflows/
        └── ci.yml
```

Each immediate directory under `skills/` is one independently installable skill whose directory name matches its `name` frontmatter field.
`scripts/`, `references/`, and `assets/` subdirectories exist only where a skill needs them.

Nothing in the repository depends on the name of the checkout directory.

## Installer

```bash
./install.sh [--claude] [--codex] [--gemini] [--all]
             [--link|--copy] [--force] [--dry-run] [--uninstall]
             [SKILL...]
```

Skills are discovered by scanning for `skills/*/SKILL.md`, never from a hardcoded list.
With no skill arguments, all discovered skills are installed.

### Targets

| Agent | Install path | Selected by auto-detection when |
|-------|--------------|---------------------------------|
| Claude Code | `~/.claude/skills/` | `~/.claude` exists |
| Codex | `~/.agents/skills/`, falling back to `~/.codex/skills/` | `~/.agents` or `~/.codex` exists |
| Antigravity | `~/.gemini/config/skills/` | `~/.gemini` exists |

`~/.agents/skills` is the preferred Codex location and is used when present; `~/.codex/skills` remains supported because Codex 0.147.0 reads it and populates it with its own `.system` skills.
Exactly one Codex location is used per run, never both, so a skill cannot be registered twice.
`~/.gemini/config/skills` is the only global location recognized by all three Antigravity variants (AGY, AGY CLI, AGY IDE).

With no agent flag, the installer targets every agent whose home directory already exists, so it never creates configuration directories for tools that are not installed.

### Link versus copy

`--link` is the default: the installer symlinks the whole skill directory into each target.
A `git pull` then updates every agent immediately, which is the behavior wanted while iterating on a skill.
Symlinking the complete directory, rather than individual files, keeps `scripts/` and `references/` resolvable relative to `SKILL.md`.

`--copy` is available for Windows, where symlink creation needs developer mode or elevation, and for anyone who wants an installed version pinned against repository changes.

### Safety

An existing symlink that already points into this repository is refreshed silently.

An existing real directory, or a symlink pointing elsewhere, is never replaced without `--force`.
Without `--force` the installer reports the conflict and exits non-zero, leaving the target untouched.
With `--force` the existing entry is moved aside to `<name>.bak` before installation.

The installer never deletes a `<name>.bak`.
If one already exists it refuses and says so, because the alternative is destroying the only remaining copy of whatever a previous `--force` preserved.

Provenance is recorded rather than inferred.
A copied installation carries a marker file naming the repository it came from, so a copy this installer made is still recognized as its own after the repository changes, and is refreshed in place rather than being treated as a stranger and backed up again.
Comparing content instead would misclassify every outdated copy the moment anyone pulled.

This rule matters immediately: real directories exist today at `~/.claude/skills/lsst-eups` and `~/.codex/skills/lsst-eups`, and both hold hand-edited content that must not be destroyed silently.

`--dry-run` prints the actions that would be taken and changes nothing.

`--uninstall` removes only entries that are symlinks resolving into this repository, or copies whose content matches the repository; anything else is reported and left alone.

## Validation and CI

`scripts/validate-skills` is a python3 program requiring PyYAML, listed in `requirements-dev.txt`.

An earlier design avoided any dependency by falling back to a hand-rolled parser for the flat `key: value` subset that frontmatter uses.
That fallback proved to be a poor trade.
It needed two rounds of fixes for comment handling alone, it was invisible on any machine that had PyYAML installed, and it could not parse the nested `agents/openai.yaml` metadata at all, which left the one file no agent reads as the one file nothing checked.
Requiring PyYAML for the repository's own tooling costs a development dependency and removes an entire class of parsing bugs.

Skills themselves are unaffected: a skill may use the standard library, or whatever its target environment already provides.

Checks:

1. Every immediate directory under `skills/` contains a `SKILL.md`.
2. The frontmatter block is present and parses.
3. `name` and `description` are present and non-empty.
4. `name` equals the containing directory name.
5. `name` matches `^[a-z0-9]+(-[a-z0-9]+)*$`.
6. Relative paths referenced from `SKILL.md` resolve to files that exist.
7. Shell scripts pass `bash -n`, and `shellcheck` when it is available.
8. Python files pass `py_compile`.
9. Files under `scripts/` are executable.
10. Every skill under `skills/` appears in the available-skills list in `README.md`, and that list names no skill that does not exist.
11. No `SKILL.md` names a per-agent discovery location such as `~/.claude/skills` or `~/.codex/skills`, since a skill must not hardcode its own installed path.
12. `CLAUDE.md` and `GEMINI.md` are symlinks named `AGENTS.md`, not copies.
13. A skill's optional `agents/openai.yaml` parses, carries a non-empty `interface.display_name` and `interface.short_description`, and its `default_prompt` names the skill it belongs to rather than some other one.

The validator exits non-zero on any failure and prints one diagnostic per problem with the offending path.

CI runs the validator and the test suite on push and pull request through GitHub Actions.
Contributors run the same checks locally with `./scripts/validate-skills` and `tests/run-all.sh`.

## Skill authoring conventions

Skills are agent-neutral by default.
A skill describes what to do in terms of ordinary tools and files, not in terms of a particular agent's tool names, slash commands, or permission prompts.

A skill must not hardcode its own installed path, because that path differs per agent and per install mode.
Skills refer to their own helpers relatively, as `scripts/<name>` within the skill directory, since every supported agent supplies the skill's base directory when the skill loads.

Helper scripts behave as ordinary command-line programs with explicit arguments, documented dependencies, useful exit codes, and clean separation of stdout and stderr.

Where behavior genuinely differs between agents, `SKILL.md` expresses the difference conditionally rather than forking the skill.
Forking into per-agent skill directories is a last resort and is not used by any current skill.

Agent-specific metadata files that other agents ignore, such as `agents/openai.yaml` for Codex, may live in the canonical skill directory because they are additive.

## The lsst-eups skill

The repository holds one reconciled copy, taking the corrected build-tag parser from the Claude copy and the clearer section heading from the Codex copy.

Portability corrections applied to `SKILL.md`:

- The hardcoded `~/.claude/skills/lsst-eups/scripts/lsst-run` invocation path is replaced by a relative reference to `scripts/lsst-run` in the skill's own directory.
- "Environment variables do not persist between Bash tool calls" becomes a statement about each command running in a fresh shell, which is true for every agent.
- The Codex sandbox paragraph is generalized: if the harness sandboxes commands, the wrapper needs to read the stack outside the workspace and write under `~/.cache/lsst-run`, and the agent should request escalation rather than reverse-engineering the EUPS environment.

A new precondition is documented: the user must activate an LSST environment before starting the agent.

## lsst-run design

### Precondition

`lsst-run` requires that the agent was started from a shell with an LSST environment already activated, by either `source $LSSTSW/bin/envconfig` for an lsstsw tree or `source loadLSST.bash` for an lsstinstall tree.

Both activation paths export `EUPS_PATH`, `EUPS_DIR`, `CONDA_PREFIX`, and `LSST_CONDA_ENV_NAME`, so the wrapper detects and identifies the environment uniformly without needing to know which flavor produced it.
If those variables are absent, `lsst-run` exits with a message naming both activation commands.

Requiring activation replaces the previous approach of defaulting `LSSTSW` to a hardcoded personal path, which could not work for anyone else on the team.

### Why a cached environment snapshot

The snapshot exists for two reasons.

It gives isolation: the command runs against exactly `lsst_distrib` at a known build tag plus the locals named on the command line, and not against whatever the launching shell happened to have set up.
A user who ran `setup -r .` in some package before starting the agent would otherwise silently contaminate every subsequent command.

It gives speed: a cold activation costs about 6.6 s, while restoring a snapshot costs about 50 ms.

### Build tag resolution

Tags are resolved and validated through the public EUPS command-line interface, not by reading `ups_db` internals, because the internal layout is not a stable contract.

Every tag comes from `eups list lsst_distrib --raw`, taking the third field and splitting it on colons.
This costs about 0.10 s and runs in the inherited environment, which already has `eups` on the path.

Which tags a stack carries depends on how it was built, and the wrapper has to work with both.
An lsstsw checkout numbers its own builds `bNNNN`.
A shared installation built by lsstinstall, such as one at a data facility, carries the permanent weekly tags `w_YYYY_WW`, and a release installation carries `vNN_N_N`.
Both kinds of stack also carry dated dailies, `d_YYYY_MM_DD`.

The default is the newest tag of the most specific family present, tried in the order build, weekly, release, daily.
Preferring by family rather than mixing them keeps an lsstsw stack on its own build numbers even though it also carries dailies, and lets a site installation fall through to its weeklies.

Ordering within a family uses `sort -V`, which compares digit runs numerically.
That matters in both directions: a lexical sort places `b10000` before `b8411` and `b9`, and it places `w_2026_10` before `w_2026_5`.

An explicit `-t TAG` is checked twice.
Its shape must match one of the families, which rejects a movable tag such as `current`: the environment snapshot is keyed on the tag, so a tag that moves would pin a user to a stale build indefinitely.
It is then validated against the tree with `eups list -t TAG lsst_distrib`, which exits 2 for an unsupported tag and 0 otherwise.
On failure the wrapper prints the tags this stack actually has.

The resolved tag is never cached.
Caching it was the cause of a real failure: the cache was keyed on a hash of `$LSSTSW` and validated only against the regular expression `^b[0-9]+$`, so after the EUPS tree was deleted and redeployed, the recorded `b8290` still looked structurally valid and was reused indefinitely even though it no longer existed in the tree.
Build tag numbers are local to a single EUPS tree and are not stable across redeployment, so any cached tag is a latent staleness bug.

### Snapshot contents and key

The snapshot captures a pristine environment holding `lsst_distrib` at the resolved tag and nothing else.

It is keyed on a hash of `LSST_CONDA_ENV_NAME`, `EUPS_PATH`, and the tag.
Including `LSST_CONDA_ENV_NAME` prevents the `lsst-scipipe-13.0.0` against `lsst-scipipe-13.1.0` confusion that the previous `$LSSTSW`-only key allowed.
Including the tag means a new build produces a new key and therefore an automatic rebuild.

Local clones are deliberately excluded from the snapshot and from its key.
A `setup -k -r` costs roughly 0.1 s, so applying locals on every invocation is effectively free, and it means one snapshot exists per tag rather than one per combination of tag and locals.
It also means the cache can never be contaminated by a local package, and that edits to a local `ups/*.table` take effect on the next call with no user action.

Because every staleness source is now covered by the key or by per-call setup, there is no `--refresh` flag.
A snapshot that no longer yields a working environment is detected and rebuilt automatically.

### Snapshot construction

The snapshot is built in a scrubbed environment, `env -i` carrying only `HOME`, `USER`, `TERM`, a minimal `PATH`, and `LSST_CONDA_ENV_NAME`.
The activation script is located from the environment: `$LSSTSW/bin/envconfig` when `LSSTSW` is set, otherwise by taking `CONDA_PREFIX` up three levels to the tree root and using `loadLSST.sh` there.
Exporting `LSST_CONDA_ENV_NAME` into that shell makes both activation scripts select the same conda environment the user activated, since both honor it as an input.

After activation and `setup -t TAG lsst_distrib`, the environment is captured with `export -p`, excluding `PWD`, `OLDPWD`, `SHLVL`, and `_`, which are per-shell state that must not be replayed.

### Invocation flow

1. Verify an activated environment, or exit with instructions.
2. Resolve or validate the build tag through `eups`.
3. Build the snapshot for this environment and tag if it is absent, and validate an existing one in a subshell, rebuilding it if it no longer yields a working environment.
4. Rebuild the process environment from the snapshot alone, under `env -i`, carrying across only variables that cannot influence what EUPS resolves but that ordinary tools need: `HOME`, and where set, `USER`, `LOGNAME`, `TERM`, `TMPDIR`, `TZ`, `LANG`, the `LC_*` categories, `SSH_AUTH_SOCK`, and the proxy variables.
5. Inside that clean shell, source `$EUPS_DIR/bin/setups.sh` to obtain the `setup` shell function, which `export -p` does not capture, then apply each `setup -k -r` in the order given.
6. `exec` the requested command.

Sourcing the snapshot into the current shell and exec'ing from there would not deliver the isolation the snapshot exists for.
Sourcing can only overwrite the variables the snapshot defines; anything else the launching shell exported would survive into the command, including a stray `SETUP_*` naming a package outside `lsst_distrib`, which is exactly what EUPS reads to decide what is active.
The command therefore runs in an environment rebuilt from the snapshot rather than layered on top of the inherited one.

`TERM` is excluded from the snapshot at build time, because the snapshot is built under `env -i` with `TERM=dumb` and would otherwise force that on every command.
The caller's real `TERM` is carried across instead.

A warm invocation costs about 0.15 s.

### Command-line interface

```text
lsst-run [-t TAG] [-l PATH]... [--list-tags] [--] COMMAND [ARGS...]
```

`-l` is repeatable and applied in order, so dependencies are listed before the package being worked on.
Relative paths are resolved to absolute.

## Testing

`tests/test-validate-skills.sh` builds fixture skill directories covering each validator rule, including deliberately invalid ones, and asserts the exit codes and messages.

`tests/test-lsst-run.sh` covers argument parsing, the unactivated-environment error, tag resolution and rejection of an invalid tag, snapshot reuse, and local-clone layering.
Tests requiring a real stack skip themselves cleanly when no LSST environment is activated, so CI without a stack still passes.

Manual verification covers the `envconfig` branch against the existing lsstsw tree.
The `loadLSST.sh` branch has no lsstinstall tree available to test against yet, so it remains verified only by inspection; exercising it against a real lsstinstall installation is still outstanding.

## Documentation

The three documents divide by audience, and each rule is stated in exactly one of them.

`AGENTS.md` is the single source of truth for how a skill is written: layout, frontmatter, portability, helper script constraints, prose conventions, and the checks to run before finishing.
It is what every agent loads, through the `CLAUDE.md` and `GEMINI.md` symlinks, and it is equally the reference for a person doing the same work.

`README.md` covers what the repository is, quick start, the available-skills table, installation and discovery locations, what happens on `git pull` under each install mode, and the risk a user accepts by installing a skill.
It points at `AGENTS.md` for authoring rather than restating any of them.

`CONTRIBUTING.md` covers only the workflow around a change: branch, pull request, and the review expectation.
It states no authoring rule of its own.

Restating a rule in a second document was tried and abandoned.
A wrong claim about `sort -V` sat in two files at once and was corrected in one of them first, which is precisely the divergence this repository exists to prevent.
Its own documentation is not exempt from that, so the rules have one home and the other documents link to it.

The available-skills list in `README.md` is checked against `skills/` by the validator so it cannot go stale.

`AGENTS.md` holds the guidance an agent needs when adding or editing a skill in this repository: the directory layout, frontmatter requirements, the portability rules, the bash 3.2 and standard-library-only constraints, the prose conventions, and the instruction to run the validator and tests before finishing and to leave pushing to a human.

It is the canonical copy because Codex and Antigravity both read `AGENTS.md`.
Claude Code reads `CLAUDE.md` and Gemini CLI reads `GEMINI.md`; Antigravity reads `GEMINI.md` in addition to `AGENTS.md` and lets it win on conflict.
Both aliases are symlinks to `AGENTS.md`, so there is one file to maintain and identical content cannot conflict.
The validator enforces that they remain symlinks, because a copy would reintroduce exactly the divergence this repository exists to prevent.

Git stores these as symlinks (mode `120000`).
A Windows checkout without developer mode or `core.symlinks=true` will materialize them as small text files containing the target name, which costs those users the per-agent aliases but leaves `AGENTS.md` itself correct.

## Decisions deferred

Project-local installation into `.claude/skills` and `.agents/skills` is not implemented; user-level installation covers the current need and the layout does not preclude adding it.

Git tags for pinned versions are not introduced until someone needs them.
