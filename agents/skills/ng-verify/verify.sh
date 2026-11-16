#!/bin/bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
set -euo pipefail

# Usage:
#   verify.sh                 → typecheck + full unit test run, current dir
#   verify.sh <angular-dir>   → typecheck + full unit test run in that dir
#   verify.sh <angular-dir> --include=<spec-glob>   → scope tests to matching specs
#   verify.sh <angular-dir> --summary               → print only the digest (no pipes needed):
#                                                     TOTAL lines, error TS, failing specs + first error line

LOGDIR="$(cd "${AGENT_PROJECT_DIR:-.}" && pwd)/.agents/logs"
mkdir -p "$LOGDIR"
[ -f "$LOGDIR/.gitignore" ] || printf '*\n' > "$LOGDIR/.gitignore"
LOG="$LOGDIR/ng-verify.log"
START=$(date +%s)

DIR="."
INCLUDE=()
SUMMARY=0
for arg in "$@"; do
  case "$arg" in
    --include=*) INCLUDE=("$arg") ;;
    --summary) SUMMARY=1 ;;
    *) DIR="$arg" ;;
  esac
done
# fd 3 = where progress goes: real stdout, or nowhere in --summary mode
if [ "$SUMMARY" = 1 ]; then exec 3>/dev/null; else exec 3>&1; fi

cd "$DIR"

if [ ! -f "tsconfig.app.json" ]; then
  echo "ERROR: no tsconfig.app.json in $DIR — not an Angular app root?"
  exit 1
fi

if [ ! -x "node_modules/.bin/tsc" ]; then
  echo "ERROR: dependencies not installed in $DIR — run npm install first"
  exit 1
fi

# Resolve a headless Chrome binary for karma/ng test — avoids the recurring
# "Chrome failed to start" failure when CHROME_BIN isn't set.
if [ -z "${CHROME_BIN:-}" ]; then
  CHROME_BIN=$(find "$HOME/.cache/puppeteer" "$HOME/.cache/ms-playwright" "$HOME/Library/Caches/ms-playwright" \
    -type f \( -name chrome -o -name chrome-headless-shell -o -name Chromium -o -name 'Google Chrome for Testing' \) \
    -perm -u+x 2>/dev/null | head -1 || true)
  export CHROME_BIN
fi

echo "Typecheck: npx tsc --noEmit -p tsconfig.app.json" | tee "$LOG" >&3
set +e
npx tsc --noEmit -p tsconfig.app.json 2>&1 | tee -a "$LOG" >&3
TSC_EXIT=${PIPESTATUS[0]}

echo "" >&3
echo "Test: npx ng test --watch=false --browsers=ChromeHeadless ${INCLUDE[*]-}" | tee -a "$LOG" >&3
npx ng test --watch=false --browsers=ChromeHeadless ${INCLUDE[@]+"${INCLUDE[@]}"} 2>&1 | tee -a "$LOG" >&3
TEST_EXIT=${PIPESTATUS[0]}
set -e

END=$(date +%s)
DURATION=$((END - START))

echo ""
echo "--- TYPECHECK $([ $TSC_EXIT -eq 0 ] && echo OK || echo FAILED), TESTS $([ $TEST_EXIT -eq 0 ] && echo PASSED || echo FAILED) in ${DURATION}s ---"

if [ $TSC_EXIT -ne 0 ]; then
  echo ""
  echo "Typecheck errors:"
  grep -E "error TS" "$LOG" || true
fi

if [ $TEST_EXIT -ne 0 ]; then
  echo ""
  echo "Test failures:"
  if [ "$SUMMARY" = 1 ]; then
    grep -E "TOTAL" "$LOG" || true
    awk '/FAILED$/ { print; if ((getline nxt) > 0) print "    " nxt }' "$LOG" || true
    grep -qE "TOTAL|FAILED" "$LOG" || { echo "(no test summary found; last log lines:)"; tail -n 5 "$LOG"; }
  else
    grep -E "FAILED" "$LOG" || true
  fi
elif [ "$SUMMARY" = 1 ]; then
  grep -E "TOTAL|Executed [0-9]+ of [0-9]+ .*SUCCESS" "$LOG" | tail -n 2 || true
fi

[ $TSC_EXIT -eq 0 ] && [ $TEST_EXIT -eq 0 ]
