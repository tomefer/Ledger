#!/usr/bin/env bash
# Ledger - deploy.sh
# Copies the addon folder (Ledger/, the one with Ledger.toc) into a WoW
# installation's Interface/AddOns, replacing whatever was there before
# so files removed from the repo don't linger as zombies. Run from WSL
# after any change under Ledger/, then /reload in game. (Claude Code's
# PostToolUse hook does this automatically after tests pass; see
# .claude/hooks/post-edit.sh.)
#
# Usage: ./deploy.sh [--if-installed | --status] [flavor]
#   flavor: classic_era (default) | forever
#
#   --if-installed  Deploy only if Ledger is already installed for that
#                   flavor; otherwise print a "Skipped" line and exit 0.
#                   Used by the hook so it never creates a first install
#                   in a client the developer isn't using.
#   --status        Deploy nothing. Print one line comparing the repo
#                   with what is installed in the client: the .toc
#                   versions AND the file contents (the version only
#                   changes when a change is closed out, so equal
#                   versions don't prove equal code). Exit code: 0 in
#                   sync, 1 out of sync, 2 not installed / client folder
#                   not found.
#
# Only ever touches <flavor addons folder>/Ledger: spec/, .git/ and
# CLAUDE.md live at the repo root, siblings of Ledger/, so copying that
# subfolder alone already excludes every dev file with no extra
# filtering needed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_SRC="$REPO_ROOT/Ledger"
ADDON_TOC="$ADDON_SRC/Ledger.toc"

MODE=deploy
IF_INSTALLED=0
FLAVOR_ARG=""
for arg in "$@"; do
    case "$arg" in
        --status)       MODE=status ;;
        --if-installed) IF_INSTALLED=1 ;;
        -*)
            echo "error: unknown option '$arg' -- expected --status or --if-installed" >&2
            exit 1
            ;;
        *)              FLAVOR_ARG="$arg" ;;
    esac
done
FLAVOR="${FLAVOR_ARG:-classic_era}"

# Each Blizzard client flavor lives in its own folder next to the
# others under the WoW install root. "forever" is this addon's own
# name for the WoW Forever beta (build 1.60.1, interface 16001, still
# the Classic product line) -- confirmed against the actual install,
# not guessed.
declare -A FLAVOR_DIRS=(
    [classic_era]="_classic_era_"
    [forever]="_classic_beta_"
)

FLAVOR_DIR="${FLAVOR_DIRS[$FLAVOR]:-}"
if [ -z "$FLAVOR_DIR" ]; then
    echo "error: unknown flavor '$FLAVOR' -- expected one of: ${!FLAVOR_DIRS[*]}" >&2
    exit 1
fi

# Root of the WoW installation (the folder that directly contains
# _classic_era_, _classic_beta_, etc.), NOT a full path down to
# Interface/AddOns: the flavor decides that last stretch. This repo is
# public, so no machine-specific path is hardcoded here: override with
# LEDGER_WOW_PATH for any install that isn't at the default Battle.net
# location, e.g.:
#   export LEDGER_WOW_PATH="/mnt/c/Games/World of Warcraft"
WOW_ROOT="${LEDGER_WOW_PATH:-/mnt/c/Program Files (x86)/World of Warcraft}"
WOW_ADDONS_PATH="$WOW_ROOT/$FLAVOR_DIR/Interface/AddOns"
DEST="$WOW_ADDONS_PATH/Ledger"

if [ ! -f "$ADDON_TOC" ]; then
    echo "error: $ADDON_TOC not found -- run deploy.sh from a Ledger checkout" >&2
    exit 1
fi

# "## Version: X" of a .toc file (tr: the client's side may save CRLF).
toc_version() {
    sed -n 's/^## Version: *//p' "$1" | head -n1 | tr -d '\r'
}

VERSION="$(toc_version "$ADDON_TOC")"

if [ "$MODE" = status ]; then
    if [ ! -d "$WOW_ADDONS_PATH" ]; then
        echo "[$FLAVOR] repo v${VERSION:-?} | client folder not found: $WOW_ADDONS_PATH"
        exit 2
    fi
    if [ ! -f "$DEST/Ledger.toc" ]; then
        echo "[$FLAVOR] repo v${VERSION:-?} | not installed in this client (./deploy.sh $FLAVOR installs it)"
        exit 2
    fi

    DEPLOYED_VERSION="$(toc_version "$DEST/Ledger.toc")"

    # Compare file by file (paths relative to the addon folder). Not
    # `diff -rq` parsed as text: it quotes paths with spaces or
    # parentheses, and the default WoW path has both.
    DIFFS=()
    while IFS= read -r f; do
        if [ ! -e "$DEST/$f" ]; then
            DIFFS+=("$f (missing in client)")
        elif ! cmp -s -- "$ADDON_SRC/$f" "$DEST/$f"; then
            DIFFS+=("$f")
        fi
    done < <(cd "$ADDON_SRC" && find . -type f | sed 's#^\./##' | sort)
    while IFS= read -r f; do
        if [ ! -e "$ADDON_SRC/$f" ]; then
            DIFFS+=("$f (only in client)")
        fi
    done < <(cd "$DEST" && find . -type f | sed 's#^\./##' | sort)

    LIST=""
    if [ "${#DIFFS[@]}" -gt 0 ]; then
        LIST="$(printf '%s, ' "${DIFFS[@]:0:5}")"
        LIST="${LIST%, }"
        if [ "${#DIFFS[@]}" -gt 5 ]; then
            LIST="$LIST, ..."
        fi
    fi

    if [ "$VERSION" != "$DEPLOYED_VERSION" ]; then
        echo "[$FLAVOR] repo v${VERSION:-?} | deployed v${DEPLOYED_VERSION:-?} | VERSION MISMATCH (${#DIFFS[@]} files differ)"
        exit 1
    elif [ "${#DIFFS[@]}" -gt 0 ]; then
        echo "[$FLAVOR] repo v${VERSION:-?} | deployed v${DEPLOYED_VERSION:-?} | SAME VERSION BUT CONTENT DIFFERS (${#DIFFS[@]} files: $LIST)"
        exit 1
    fi
    echo "[$FLAVOR] repo v${VERSION:-?} | deployed v${DEPLOYED_VERSION:-?} | in sync"
    exit 0
fi

if [ "$IF_INSTALLED" = 1 ] && [ ! -d "$DEST" ]; then
    echo "Skipped $FLAVOR: Ledger is not installed in that client (run ./deploy.sh $FLAVOR once to install it)"
    exit 0
fi

if [ ! -d "$WOW_ADDONS_PATH" ]; then
    echo "error: destination path does not exist: $WOW_ADDONS_PATH" >&2
    echo "set LEDGER_WOW_PATH to the root of your WoW installation (the folder" >&2
    echo "that contains $FLAVOR_DIR), e.g.:" >&2
    echo "  LEDGER_WOW_PATH=\"/mnt/c/Path/To/World of Warcraft\" ./deploy.sh $FLAVOR" >&2
    exit 1
fi

echo "Deploying $ADDON_SRC -> $DEST (flavor: $FLAVOR)"
rm -rf -- "$DEST"
cp -r -- "$ADDON_SRC" "$DEST"

echo "Deployed Ledger v${VERSION:-?} to $DEST at $(date '+%Y-%m-%d %H:%M:%S')"
