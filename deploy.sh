#!/usr/bin/env bash
# Ledger - deploy.sh
# Copies the addon folder (Ledger/Ledger, the one with Ledger.toc) into
# WoW Classic Era's Interface/AddOns, replacing whatever was there
# before so files removed from the repo don't linger as zombies. Run
# from WSL after any change under Ledger/Ledger, then /reload in game.
#
# Only ever touches <destination>/Ledger: spec/, .git/ and CLAUDE.md
# live at the repo root, siblings of Ledger/Ledger, so copying that
# subfolder alone already excludes every dev file with no extra
# filtering needed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_SRC="$REPO_ROOT/Ledger"
ADDON_TOC="$ADDON_SRC/Ledger.toc"

# Where WoW Classic Era's Interface/AddOns folder lives. This repo is
# public, so no machine-specific path is hardcoded here: override with
# LEDGER_WOW_PATH for any install that isn't at the default Battle.net
# location, e.g.:
#   export LEDGER_WOW_PATH="/mnt/c/Games/World of Warcraft/_classic_era_/Interface/AddOns"
WOW_ADDONS_PATH="${LEDGER_WOW_PATH:-/mnt/c/Program Files (x86)/World of Warcraft/_classic_era_/Interface/AddOns}"

if [ ! -f "$ADDON_TOC" ]; then
    echo "error: $ADDON_TOC not found -- run deploy.sh from a Ledger checkout" >&2
    exit 1
fi

if [ ! -d "$WOW_ADDONS_PATH" ]; then
    echo "error: destination path does not exist: $WOW_ADDONS_PATH" >&2
    echo "set LEDGER_WOW_PATH to your WoW Classic Era Interface/AddOns folder, e.g.:" >&2
    echo "  LEDGER_WOW_PATH=\"/mnt/c/Path/To/World of Warcraft/_classic_era_/Interface/AddOns\" ./deploy.sh" >&2
    exit 1
fi

DEST="$WOW_ADDONS_PATH/Ledger"

echo "Deploying $ADDON_SRC -> $DEST"
rm -rf -- "$DEST"
cp -r -- "$ADDON_SRC" "$DEST"

VERSION="$(sed -n 's/^## Version: *//p' "$ADDON_TOC" | head -n1)"

echo "Deployed Ledger v${VERSION:-?} to $DEST at $(date '+%Y-%m-%d %H:%M:%S')"
