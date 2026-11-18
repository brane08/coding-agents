#!/bin/bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
set -euo pipefail

# Usage: pull.sh <groupId:artifactId:version>
# Pulls <artifactId>-<version>-sources.jar into ~/.m2/repository via dependency:get.
# Every attempt is logged to <project>/.agents/logs/pull-sources.log; after MAX failed
# attempts for the same GAV it refuses (exit 3) so the caller asks the user instead.
# Exit: 0 present/pulled, 1 pull failed, 2 bad usage, 3 attempt limit reached.

MAX=2

if [ $# -ne 1 ]; then
  echo "Usage: pull.sh <groupId:artifactId:version>"
  exit 2
fi
GAV="$1"
if ! [[ "$GAV" =~ ^[A-Za-z0-9._-]+:[A-Za-z0-9._-]+:[A-Za-z0-9._-]+$ ]]; then
  echo "ERROR: expected groupId:artifactId:version, got: $GAV"
  exit 2
fi
GROUP="${GAV%%:*}"
REST="${GAV#*:}"
ARTIFACT="${REST%%:*}"
VERSION="${REST#*:}"

JAR="$HOME/.m2/repository/${GROUP//.//}/$ARTIFACT/$VERSION/$ARTIFACT-$VERSION-sources.jar"
if [ -f "$JAR" ]; then
  echo "sources already present: $JAR"
  exit 0
fi

LOGDIR="$(cd "${AGENT_PROJECT_DIR:-.}" && pwd)/.agents/logs"
mkdir -p "$LOGDIR"
[ -f "$LOGDIR/.gitignore" ] || printf '*\n' > "$LOGDIR/.gitignore"
LOG="$LOGDIR/pull-sources.log"

FAILS=$(grep -c -F -- " $GAV FAIL" "$LOG" 2>/dev/null || true)
FAILS="${FAILS:-0}"
if [ "$FAILS" -ge "$MAX" ]; then
  echo "pull failed ${FAILS}x for $GAV (limit $MAX) - stop and ask the user (javap ok?)."
  exit 3
fi

cd "${AGENT_PROJECT_DIR:-.}"
set +e
OUT=$(mvn -B -q dependency:get "-Dartifact=$GAV:jar:sources" -Dtransitive=false 2>&1)
EXIT=$?
set -e

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ $EXIT -eq 0 ] && [ -f "$JAR" ]; then
  printf '%s %s OK\n' "$TS" "$GAV" >> "$LOG"
  echo "pulled: $JAR"
  exit 0
fi

printf '%s %s FAIL\n' "$TS" "$GAV" >> "$LOG"
echo "$OUT" | grep -E "^\[ERROR\]" | tail -n 5 || true
echo "attempt $((FAILS + 1))/$MAX failed for $GAV (no sources published, or network/repo issue)."
exit 1
