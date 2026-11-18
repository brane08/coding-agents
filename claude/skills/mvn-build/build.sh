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
    -pl) [ $# -ge 2 ] || { echo "ERROR: -pl needs a module name"; exit 2; }; shift; MODULE="$1" ;;
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

# Best effort, once per pom change: pull -sources.jar for dependencies so library inspection reads
# sources instead of decompiling. Never affects the build result. PULL_SOURCES=0 skips it.
if [ $EXIT -eq 0 ] && [ "${PULL_SOURCES:-1}" != "0" ]; then
  STAMP="$LOGDIR/.sources-stamp"
  if [ ! -f "$STAMP" ] || [ -n "$(find . -name pom.xml -newer "$STAMP" -not -path '*/node_modules/*' -not -path '*/target/*' -print -quit)" ]; then
    echo "Pulling dependency sources (once per pom change; PULL_SOURCES=0 to skip)..."
    SRC_ARGS=()
    if [ "$FULL_REACTOR" != true ] && [ -n "$MODULE" ]; then SRC_ARGS=(-pl "$MODULE" -am); fi
    if mvn -B -q dependency:sources -Dmdep.failOnMissingClassifierArtifact=false ${SRC_ARGS[@]+"${SRC_ARGS[@]}"} >> "$LOG" 2>&1; then
      touch "$STAMP"
    else
      echo "(sources pull failed; see $LOG)"
    fi
  fi
fi

if [ $EXIT -ne 0 ]; then
  echo ""
  echo "Errors:"
  grep -E "^\[ERROR\]" "$LOG" | grep -v "^$" || echo "(no [ERROR] lines found)"
fi

exit $EXIT
