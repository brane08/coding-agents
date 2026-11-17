#!/bin/bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
set -euo pipefail

# Usage:
#   test.sh                                → tests current dir module
#   test.sh mono-quarkus                   → tests named module (with -am)
#   test.sh mono-quarkus UserServiceTest   → specific test class in module

LOGDIR="$(cd "${CLAUDE_PROJECT_DIR:-.}" && pwd)/.claude/logs"
mkdir -p "$LOGDIR"
[ -f "$LOGDIR/.gitignore" ] || printf '*\n' > "$LOGDIR/.gitignore"
LOG="$LOGDIR/mvn-test.log"
START=$(date +%s)

cd "${CLAUDE_PROJECT_DIR:-.}"

IS_REACTOR=false
if grep -q "<modules>" pom.xml 2>/dev/null; then
  IS_REACTOR=true
fi

MODULE="${1:-}"
PATTERN="${2:-}"

if [ $# -gt 2 ] || [[ "$MODULE" == -* || "$PATTERN" == -* ]]; then
  echo "ERROR: usage: test.sh [<module> [TestClass]] — no flags (--summary belongs to ng-verify/verify.sh)"
  exit 2
fi

if [ -n "$MODULE" ] && ! [[ "$MODULE" =~ ^[A-Za-z0-9._,:/-]+$ ]]; then
  echo "ERROR: invalid module name: $MODULE"
  exit 2
fi
if [ -n "$PATTERN" ] && ! [[ "$PATTERN" =~ ^[A-Za-z0-9._,#*?+!-]+$ ]]; then
  echo "ERROR: invalid test pattern: $PATTERN"
  exit 2
fi

if [ -n "$MODULE" ] && [ -n "$PATTERN" ]; then
  CMD=(mvn verify -pl "$MODULE" -am "-Dtest=$PATTERN" -DfailIfNoTests=false -Dsurefire.failIfNoSpecifiedTests=false)
elif [ -n "$MODULE" ]; then
  CMD=(mvn verify -pl "$MODULE" -am)
elif [ "$IS_REACTOR" = true ]; then
  echo "ERROR: At reactor root. Specify a module: test.sh <module> [TestClass]"
  exit 1
else
  CMD=(mvn verify)
fi

echo "Running: ${CMD[*]}"
set +e
"${CMD[@]}" 2>&1 | tee "$LOG"
EXIT=${PIPESTATUS[0]}
set -e

END=$(date +%s)
DURATION=$((END - START))

echo ""
echo "--- TESTS $([ $EXIT -eq 0 ] && echo 'PASSED' || echo 'FAILED') in ${DURATION}s ---"
echo ""

grep -E "Tests run:" "$LOG" | tail -5 || true

FAILURES=$(grep -E "FAILED|<<< ERROR" "$LOG" || true)
if [ -n "$FAILURES" ]; then
  echo ""
  echo "Failed:"
  echo "$FAILURES"
  echo ""
  echo "Details (first 6 lines after each failure):"
  for f in */target/surefire-reports/*.txt target/surefire-reports/*.txt; do
    [ -f "$f" ] || continue
    grep -A6 -E "<<< (FAILURE|ERROR)" "$f" | head -40 || true
  done
fi

exit $EXIT
