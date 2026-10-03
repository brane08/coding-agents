#!/bin/bash
set -euo pipefail

# Usage:
#   verify.sh                 → typecheck + full unit test run, current dir
#   verify.sh <angular-dir>   → typecheck + full unit test run in that dir
#   verify.sh <angular-dir> --include=<spec-glob>   → scope tests to matching specs

LOG=/tmp/ng-verify.log
START=$(date +%s)

DIR="."
INCLUDE=""
for arg in "$@"; do
  case "$arg" in
    --include=*) INCLUDE="$arg" ;;
    *) DIR="$arg" ;;
  esac
done

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
  CHROME_BIN=$(find "$HOME/.cache/puppeteer" "$HOME/Library/Caches/ms-playwright" \
    -type f -iname "*chrome*" -perm -u+x 2>/dev/null | head -1 || true)
  export CHROME_BIN
fi

echo "Typecheck: npx tsc --noEmit -p tsconfig.app.json"
npx tsc --noEmit -p tsconfig.app.json 2>&1 | tee "$LOG"
TSC_EXIT=${PIPESTATUS[0]}

echo ""
echo "Test: npx ng test --watch=false --browsers=ChromeHeadless $INCLUDE"
npx ng test --watch=false --browsers=ChromeHeadless $INCLUDE 2>&1 | tee -a "$LOG"
TEST_EXIT=${PIPESTATUS[0]}

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
  grep -E "FAILED" "$LOG" || true
fi

[ $TSC_EXIT -eq 0 ] && [ $TEST_EXIT -eq 0 ]
