#!/usr/bin/env bash
# Ledger - PostToolUse hook (matcher Write|Edit).
#
# After Claude edits a file that ships to the WoW client (anything under
# Ledger/, never spec/, docs or config): run busted; if it fails, report
# it and STOP (no deploy); if it passes, deploy to the client(s) and
# print one confirmation line with the .toc version and the time.
#
# Output goes to Claude Code as JSON: "systemMessage" is what the user
# sees; on failure "decision":"block" + "reason" feeds the failure back
# to Claude so it fixes it instead of carrying on.
#
# Environment (all optional):
#   LEDGER_WOW_PATH       WoW install root (read by deploy.sh).
#   LEDGER_HOOK_FLAVORS   Space-separated flavors to refresh, default
#                         "forever classic_era". Only flavors where Ledger
#                         is already installed are touched (--if-installed).
#   LEDGER_HOOKS=off      Disable this hook (the sentinel file
#                         .claude/hooks.disabled does the same). See
#                         "Hooks" in CLAUDE.md.
#
# Needs python3 (no jq on this machine) for the stdin JSON and the output.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# Disabled on purpose: stay silent so the switch costs nothing.
if [ "${LEDGER_HOOKS:-}" = off ] || [ -e "$REPO/.claude/hooks.disabled" ]; then
    exit 0
fi

# emit <decision: block|""> <reason> <message-for-the-user>
emit() {
    python3 - "$1" "$2" "$3" <<'PY'
import json, sys
decision, reason, message = sys.argv[1:4]
out = {"systemMessage": message}
if decision:
    out["decision"] = decision
    out["reason"] = reason
print(json.dumps(out))
PY
}

if ! command -v python3 >/dev/null 2>&1; then
    echo '{"systemMessage":"Ledger hook: python3 not found, tests and deploy were NOT run"}'
    exit 0
fi

# File that was just written, from the tool input on stdin.
FILE="$(python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = d.get("tool_input") or {}
tr = d.get("tool_response") or {}
print(ti.get("file_path") or (tr.get("filePath") if isinstance(tr, dict) else "") or "")
' 2>/dev/null)"

[ -n "$FILE" ] || exit 0
FILE="$(realpath -m -- "$FILE")"

# Only what goes to the client: everything else is a silent no-op.
case "$FILE" in
    "$REPO/Ledger/"*) ;;
    *) exit 0 ;;
esac

# Serialize: parallel edits must not race over the test copy or the deploy.
exec 9>"${TMPDIR:-/tmp}/ledger-hook-$(id -u).lock"
flock -w 60 9 || { emit "" "" "Ledger hook: another run held the lock for 60s, skipped"; exit 0; }

# --- 1. tests ---------------------------------------------------------
# busted on DrvFs (/mnt/c) takes ~2.3s, nearly all of it the specs' many
# loadfile() calls over the 9p mount; on ext4 it takes ~0.2s. The specs
# only load Ledger/core/*, so run them on a fresh copy of Ledger/ + spec/
# in a native temp dir (same content, same relative paths). If the copy
# fails, fall back to running in place: slower, never wrong.
TESTDIR="${TMPDIR:-/tmp}/ledger-hook-tests-$(id -u)"
if mkdir -p "$TESTDIR" \
    && rsync -a --delete "$REPO/Ledger/" "$TESTDIR/Ledger/" \
    && rsync -a --delete "$REPO/spec/" "$TESTDIR/spec/" \
    && { [ ! -f "$REPO/.busted" ] || cp "$REPO/.busted" "$TESTDIR/.busted"; }; then
    RUN_DIR="$TESTDIR"
else
    RUN_DIR="$REPO"
fi

# The addon's load-time print("Ledger: core/x.lua") lines are noise here.
RAW="$(cd "$RUN_DIR" && busted 2>&1)"
RC=$?
CLEAN="$(printf '%s\n' "$RAW" | grep -v -E '^[-+]?Ledger: (core|ui)/|^[-+]?$')"
SUMMARY="$(printf '%s\n' "$CLEAN" | grep -E 'successes /' | tail -n1)"
SUMMARY="${SUMMARY%% : *}"   # drop the run time: it's noise in a one-line message

REL="${FILE#"$REPO"/}"
if [ "$RC" -ne 0 ]; then
    TAIL="$(printf '%s\n' "$CLEAN" | tail -n 40)"
    emit block \
"busted FAILED after editing $REL. The deploy to the WoW client was skipped, so the client still runs the previous code. Fix the failure before continuing.

$TAIL" \
        "Ledger: busted FAILED after editing $REL (${SUMMARY:-no summary}), deploy skipped"
    exit 0
fi

# --- 2. deploy --------------------------------------------------------
DEPLOYED=()
SKIPPED=()
for flavor in ${LEDGER_HOOK_FLAVORS:-forever classic_era}; do
    OUT="$("$REPO/deploy.sh" --if-installed "$flavor" 2>&1)"
    DRC=$?
    if [ "$DRC" -ne 0 ]; then
        emit block \
"Tests passed but deploy.sh failed for flavor '$flavor' (exit $DRC), so the WoW client does NOT have the latest code:

$OUT" \
            "Ledger: tests OK but DEPLOY FAILED for $flavor: $(printf '%s' "$OUT" | tail -n1)"
        exit 0
    fi
    case "$OUT" in
        Skipped*) SKIPPED+=("$flavor") ;;
        *)        DEPLOYED+=("$flavor") ;;
    esac
done

# --- 3. one-line confirmation -----------------------------------------
VERSION="$(sed -n 's/^## Version: *//p' "$REPO/Ledger/Ledger.toc" | head -n1 | tr -d '\r')"
NOW="$(date '+%H:%M:%S')"
TESTS="$SUMMARY"

if [ "${#DEPLOYED[@]}" -eq 0 ]; then
    emit "" "" "Ledger: tests OK ($TESTS) but NOTHING deployed: Ledger is not installed in any of: ${SKIPPED[*]:-(no flavors configured)}. Check LEDGER_WOW_PATH / LEDGER_HOOK_FLAVORS or run ./deploy.sh <flavor> once."
else
    emit "" "" "Ledger v${VERSION:-?} deployed to ${DEPLOYED[*]} at $NOW  [$TESTS]"
fi
exit 0
