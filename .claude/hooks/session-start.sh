#!/usr/bin/env bash
# Ledger - SessionStart hook.
#
# Prints the .toc version in the repo next to what is deployed in each
# WoW client, and says so loudly when they don't match. "Match" means
# the version AND the file contents (deploy.sh --status): the version
# only changes when a change is closed out, so equal versions can still
# hide stale code in the client.
#
# The user sees the summary as a systemMessage; Claude gets the same
# text as context, so it can raise a mismatch itself.
#
# Environment (all optional): LEDGER_WOW_PATH, LEDGER_HOOK_FLAVORS (see
# post-edit.sh), LEDGER_HOOKS=off / .claude/hooks.disabled to disable.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

if [ "${LEDGER_HOOKS:-}" = off ] || [ -e "$REPO/.claude/hooks.disabled" ]; then
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo '{"systemMessage":"Ledger hook: python3 not found, could not compare repo and deployed versions"}'
    exit 0
fi

LINES=()
BAD=0
for flavor in ${LEDGER_HOOK_FLAVORS:-forever classic_era}; do
    OUT="$("$REPO/deploy.sh" --status "$flavor" 2>&1)"
    RC=$?
    case "$RC" in
        0) LINES+=("  $OUT") ;;
        1) LINES+=("  >>> $OUT"); BAD=1 ;;
        2) LINES+=("  $OUT") ;;   # not installed / no client folder: informational
        *) LINES+=("  >>> deploy.sh --status $flavor failed (exit $RC): $OUT"); BAD=1 ;;
    esac
done

if [ "$BAD" -eq 1 ]; then
    HEADER="Ledger: the client does NOT run what is in the repo (./deploy.sh <flavor> fixes it):"
else
    HEADER="Ledger: repo and deployed client(s) checked:"
fi

BODY="$HEADER"
for l in "${LINES[@]}"; do
    BODY+=$'\n'"$l"
done

python3 - "$BODY" <<'PY'
import json, sys
body = sys.argv[1]
print(json.dumps({
    "systemMessage": body,
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": body,
    },
}))
PY
exit 0
