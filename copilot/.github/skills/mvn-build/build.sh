#!/bin/bash
set -euo pipefail

# Usage:
#   build.sh                      → builds current directory module only
#   build.sh mono-quarkus         → builds named module via -pl
#   build.sh -pl mono-quarkus     → pass mvn flags directly
#   build.sh --reactor            → full reactor build

LOG=/tmp/mvn-build.log
START=$(date +%s)

cd "${CLAUDE_PROJECT_DIR:-.}"

# Detect if we're at reactor root (has <modules> in pom.xml)
IS_REACTOR=false
if grep -q "<modules>" pom.xml 2>/dev/null; then
  IS_REACTOR=true
fi

# Parse arguments
MODULE=""
EXTRA_ARGS=""
FULL_REACTOR=false

for arg in "$@"; do
  case "$arg" in
    --reactor) FULL_REACTOR=true ;;
    -pl) shift; MODULE="$1" ;;
    -*) EXTRA_ARGS="$EXTRA_ARGS $arg" ;;
    *) MODULE="$arg" ;;
  esac
done

# Build command
if [ "$FULL_REACTOR" = true ]; then
  CMD="mvn clean package -DskipTests -T1C $EXTRA_ARGS"
elif [ -n "$MODULE" ]; then
  CMD="mvn clean package -pl $MODULE -am -DskipTests $EXTRA_ARGS"
elif [ "$IS_REACTOR" = true ]; then
  echo "ERROR: At reactor root. Specify a module to avoid full reactor build."
  echo "Usage: build.sh <module-name>  or  build.sh --reactor"
  exit 1
else
  CMD="mvn clean package -DskipTests $EXTRA_ARGS"
fi

echo "Running: $CMD"
eval "$CMD" 2>&1 | tee "$LOG"
EXIT=${PIPESTATUS[0]}

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
