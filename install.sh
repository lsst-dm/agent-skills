#!/usr/bin/env bash
#
# Install this repository's skills into the discovery locations used by
# Claude Code, Codex, and Antigravity.
set -uo pipefail

REPO_ROOT=$( cd "$(dirname "$0")" && pwd -P )

err() { echo "install.sh: $*" >&2; }

[ -n "${HOME:-}" ] || { err "HOME is not set"; exit 1; }
SKILLS_DIR="$REPO_ROOT/skills"

# Written into every directory this installer copies, recording where it
# came from so a later run can tell its own copies apart from directories
# the user maintains by hand.
MARKER=.agent-skills-source

MODE="link"
FORCE=0
DRY_RUN=0
UNINSTALL=0
AGENTS=()
REQUESTED=()

usage() {
    cat <<'EOF'
Usage: install.sh [OPTIONS] [SKILL...]

Agents (default: every agent whose home directory already exists):
  --claude          install into ~/.claude/skills
  --codex           install into ~/.agents/skills, or ~/.codex/skills
  --gemini          install into ~/.gemini/config/skills
  --all             install for all three regardless of what is present

Options:
  --link            symlink the skill directory (default)
  --copy            copy the skill directory instead
  --force           replace an existing entry, keeping it as <name>.bak
  --dry-run         print what would happen and change nothing
  --uninstall       remove entries this repository installed
  -h, --help        show this message

With no SKILL arguments every skill under skills/ is installed.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --claude) AGENTS+=(claude); shift ;;
        --codex)  AGENTS+=(codex);  shift ;;
        --gemini) AGENTS+=(gemini); shift ;;
        --all)    AGENTS=(claude codex gemini); shift ;;
        --link)   MODE="link"; shift ;;
        --copy)   MODE="copy"; shift ;;
        --force)  FORCE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) err "unknown option: $1"; usage >&2; exit 1 ;;
        *) break ;;
    esac
done

while [ $# -gt 0 ]; do
    REQUESTED+=("$1")
    shift
done

# Whether an agent is installed for this user.
agent_present() {
    case "$1" in
        claude) [ -d "$HOME/.claude" ] ;;
        codex)  [ -d "$HOME/.agents" ] || [ -d "$HOME/.codex" ] ;;
        gemini) [ -d "$HOME/.gemini" ] ;;
        *) return 1 ;;
    esac
}

# Exactly one directory per agent, never two, so a skill is never registered
# twice. ~/.agents/skills is the preferred Codex location; ~/.codex/skills is
# still read by current Codex releases and is used when ~/.agents is absent.
target_dir() {
    case "$1" in
        claude) printf '%s\n' "$HOME/.claude/skills" ;;
        codex)
            if [ -d "$HOME/.agents" ]; then
                printf '%s\n' "$HOME/.agents/skills"
            else
                printf '%s\n' "$HOME/.codex/skills"
            fi
            ;;
        gemini) printf '%s\n' "$HOME/.gemini/config/skills" ;;
    esac
}

resolve_dir() { ( cd "$1" 2>/dev/null && pwd -P ); }

# True when target is a symlink into this repository, or a copy this
# installer made. Copies record their origin because comparing content
# stops matching as soon as the repository changes, which would make our
# own outdated copy indistinguishable from a directory the user maintains.
installed_from_repo() {
    local target=$1 src=$2
    if [ -L "$target" ]; then
        if [ "$(resolve_dir "$target")" = "$(resolve_dir "$src")" ]; then
            return 0
        fi
        # A link whose target has gone still names where it pointed.
        [ "$(readlink "$target")" = "$src" ]
        return
    fi
    [ -d "$target" ] && [ -f "$target/$MARKER" ] && \
        [ "$(cat "$target/$MARKER" 2>/dev/null)" = "$REPO_ROOT" ]
}

if [ ${#AGENTS[@]} -eq 0 ]; then
    for agent in claude codex gemini; do
        agent_present "$agent" && AGENTS+=("$agent")
    done
fi

if [ ${#AGENTS[@]} -eq 0 ]; then
    err "no supported agent found; pass --claude, --codex, --gemini or --all"
    exit 1
fi

AVAILABLE=()
for path in "$SKILLS_DIR"/*/SKILL.md; do
    [ -f "$path" ] || continue
    AVAILABLE+=("$(basename "$(dirname "$path")")")
done

SELECTED=()
if [ ${#REQUESTED[@]} -eq 0 ]; then
    for have in ${AVAILABLE[@]+"${AVAILABLE[@]}"}; do
        SELECTED+=("$have")
    done
else
    status=0
    for want in ${REQUESTED[@]+"${REQUESTED[@]}"}; do
        found=0
        for have in ${AVAILABLE[@]+"${AVAILABLE[@]}"}; do
            [ "$want" = "$have" ] && found=1
        done
        if [ "$found" = 1 ]; then
            SELECTED+=("$want")
        else
            err "no such skill: $want"
            status=1
        fi
    done
    [ "$status" = 0 ] || exit 1
fi

exit_status=0

for agent in ${AGENTS[@]+"${AGENTS[@]}"}; do
    dest=$(target_dir "$agent")
    for skill in ${SELECTED[@]+"${SELECTED[@]}"}; do
        src="$SKILLS_DIR/$skill"
        target="$dest/$skill"

        if [ "$UNINSTALL" = 1 ]; then
            if [ ! -e "$target" ] && [ ! -L "$target" ]; then
                continue
            fi
            if installed_from_repo "$target" "$src"; then
                if [ "$DRY_RUN" = 1 ]; then
                    echo "would remove $target"
                else
                    rm -rf "$target"
                    echo "removed $target"
                fi
            else
                err "not installed from this repository, leaving alone: $target"
                exit_status=1
            fi
            continue
        fi

        if [ -e "$target" ] || [ -L "$target" ]; then
            if installed_from_repo "$target" "$src"; then
                if [ "$MODE" = link ] && [ -L "$target" ]; then
                    echo "up to date: $target"
                    continue
                fi
                if { [ "$MODE" = link ] && [ ! -L "$target" ]; } ||
                   { [ "$MODE" = copy ] && [ -L "$target" ]; }; then
                    # Switching between link and copy undoes a deliberate
                    # choice, so it is never done by default.
                    if [ "$FORCE" != 1 ]; then
                        err "$target is installed as the other mode; pass --force to switch it"
                        exit_status=1
                        continue
                    fi
                fi
                # Ours already, so nothing needs preserving. Replacing rather
                # than skipping is what lets a copy pick up a pull.
                if [ "$DRY_RUN" = 1 ]; then
                    echo "would replace $target"
                else
                    rm -rf "$target" || { exit_status=1; continue; }
                    echo "replaced $target"
                fi
            elif [ "$FORCE" != 1 ]; then
                err "$target already exists; pass --force to replace it"
                exit_status=1
                continue
            else
                if [ -e "$target.bak" ] || [ -L "$target.bak" ]; then
                    err "$target.bak already exists; move or remove it first"
                    exit_status=1
                    continue
                fi
                if [ "$DRY_RUN" = 1 ]; then
                    echo "would move $target aside to $target.bak"
                else
                    mv "$target" "$target.bak" || { exit_status=1; continue; }
                    echo "moved aside: $target -> $target.bak"
                fi
            fi
        fi

        if [ "$DRY_RUN" = 1 ]; then
            echo "would install $skill ($MODE) into $dest"
            continue
        fi

        mkdir -p "$dest" || { exit_status=1; continue; }
        if [ "$MODE" = link ]; then
            ln -s "$src" "$target" || { exit_status=1; continue; }
        else
            cp -R "$src" "$target" || { exit_status=1; continue; }
            printf '%s\n' "$REPO_ROOT" > "$target/$MARKER" || {
                exit_status=1
                continue
            }
        fi
        echo "installed $skill ($MODE) into $dest"
    done
done

exit "$exit_status"
