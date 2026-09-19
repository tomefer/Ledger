#!/usr/bin/env bash
# Ledger - deploy.sh
# Copies the addon folder (Ledger/Ledger, the one with Ledger.toc) into
# a WoW installation's Interface/AddOns, replacing whatever was there
# before so files removed from the repo don't linger as zombies. Run
# from WSL after any change under Ledger/Ledger, then /reload in game.
#
# Usage: ./deploy.sh [flavor]
#   flavor: classic_era (default) | forever
#
# Only ever touches <flavor addons folder>/Ledger: spec/, .git/ and
# CLAUDE.md live at the repo root, siblings of Ledger/Ledger, so
# copying that subfolder alone already excludes every dev file with no
# extra filtering needed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_SRC="$REPO_ROOT/Ledger"
ADDON_TOC="$ADDON_SRC/Ledger.toc"

FLAVOR="${1:-classic_era}"

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

if [ ! -f "$ADDON_TOC" ]; then
    echo "error: $ADDON_TOC not found -- run deploy.sh from a Ledger checkout" >&2
    exit 1
fi

if [ ! -d "$WOW_ADDONS_PATH" ]; then
    echo "error: destination path does not exist: $WOW_ADDONS_PATH" >&2
    echo "set LEDGER_WOW_PATH to the root of your WoW installation (the folder" >&2
    echo "that contains $FLAVOR_DIR), e.g.:" >&2
    echo "  LEDGER_WOW_PATH=\"/mnt/c/Path/To/World of Warcraft\" ./deploy.sh $FLAVOR" >&2
    exit 1
fi

DEST="$WOW_ADDONS_PATH/Ledger"

echo "Deploying $ADDON_SRC -> $DEST (flavor: $FLAVOR)"
rm -rf -- "$DEST"
cp -r -- "$ADDON_SRC" "$DEST"

VERSION="$(sed -n 's/^## Version: *//p' "$ADDON_TOC" | head -n1)"

echo "Deployed Ledger v${VERSION:-?} to $DEST at $(date '+%Y-%m-%d %H:%M:%S')"
