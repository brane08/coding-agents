#!/bin/bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
set -euo pipefail

# Usage:
#   build.sh                      → builds current directory module only
#   build.sh mono-quarkus         → builds named module via -pl
#   build.sh -pl mono-quarkus     → same
#   build.sh --reactor            → full reactor build
# Extra -flags are passed to mvn as separate arguments (never evaluated by a shell).

LOGDIR="$(cd "${CLAUDE_PROJECT_DIR:-.}" && pwd)/.claude/logs"
mkdir -p "$LOGDIR"
[ -f "$LOGDIR/.gitignore" ] || printf '*\n' > "$LOGDIR/.gitignore"
LOG="$LOGDIR/mvn-build.log"
START=$(date +%s)

cd "${CLAUDE_PROJECT_DIR:-.}"

IS_REACTOR=false
if grep -q "<modules>" pom.xml 2>/dev/null; then
  IS_REACTOR=true
fi

MODULE=""
EXTRA_ARGS=()
FULL_REACTOR=false

while [ $# -gt 0 ]; do
  case "$1" in
    --reactor) FULL_REACTOR=true ;;
    -pl) shift; MODULE="${1:-}" ;;
    -*) EXTRA_ARGS+=("$1") ;;
    *) MODULE="$1" ;;
  esac
  shift
done

if [ -n "$MODULE" ] && ! [[ "$MODULE" =~ ^[A-Za-z0-9._,:/-]+$ ]]; then
  echo "ERROR: invalid module name: $MODULE"
  exit 2
fi

if [ "$FULL_REACTOR" = true ]; then
  CMD=(mvn clean package -DskipTests -T1C)
elif [ -n "$MODULE" ]; then
  CMD=(mvn clean package -pl "$MODULE" -am -DskipTests)
elif [ "$IS_REACTOR" = true ]; then
  echo "ERROR: At reactor root. Specify a module to avoid full reactor build."
  echo "Usage: build.sh <module-name>  or  build.sh --reactor"
  exit 1
else
  CMD=(mvn clean package -DskipTests)
fi
CMD+=(${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"})

echo "Running: ${CMD[*]}"
set +e
"${CMD[@]}" 2>&1 | tee "$LOG"
EXIT=${PIPESTATUS[0]}
set -e

END=$(date +%s)
DURATION=$((END - START))

echo ""
echo "--- BUILD $([ $EXIT -eq 0 ] && echo 'OK' || echo 'FAILED') in ${DURATION}s ---"

if [ $EXIT -ne 0 ]; then
  echo ""
  echo "Errors:"
  grep -E "^\[ERROR\]" "$LOG" | grep -v "^$" || echo "(no [ERROR] lines found)"
fi

exit $EXIT
