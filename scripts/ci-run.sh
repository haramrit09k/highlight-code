#!/usr/bin/env bash
# Runs a command in CI and, if it fails, repeats its errors as GitHub annotations so they
# show up on the pull request (and through the checks API) without opening the full log.
#
# Usage: scripts/ci-run.sh <command> [args...]
set -uo pipefail

LOG="$(mktemp)"
"$@" 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}

if [[ $STATUS -ne 0 ]]; then
  # Compiler errors, XCTest failures and our own FAIL lines; fall back to the log tail.
  MATCHES="$(grep -E 'error:|FAIL|failed \(|fatal' "$LOG" | grep -v '^Test Suite' | head -n 40)"
  [[ -n "$MATCHES" ]] || MATCHES="$(tail -n 40 "$LOG")"
  # Annotations are single-line; GitHub decodes %0A back to newlines.
  BODY="$(printf '%s' "$MATCHES" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
  echo "::error title=$1 failed::${BODY}"
fi
rm -f "$LOG"
exit "$STATUS"
