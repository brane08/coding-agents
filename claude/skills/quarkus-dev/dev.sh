#!/bin/bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}"

LOGDIR="$(pwd)/.claude/logs"
mkdir -p "$LOGDIR"
[ -f "$LOGDIR/.gitignore" ] || printf '*\n' > "$LOGDIR/.gitignore"
LOG="$LOGDIR/quarkus-dev.log"
PORT=${QUARKUS_PORT:-${1:-8080}}
if ! [[ "$PORT" =~ ^[0-9]{2,5}$ ]]; then
  echo "ERROR: invalid port: $PORT"
  exit 2
fi

# Stop a previous quarkus:dev on that port; refuse to kill anything else
EXISTING=$(lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null || true)
for p in $EXISTING; do
  cmdline=$(ps -o args= -p "$p" 2>/dev/null || true)
  case "$cmdline" in
    *quarkus*|*maven*|*mvn*|*plexus-classworlds*) ;;
    *)
      echo "ERROR: port $PORT is used by PID $p ($cmdline), not a quarkus/maven process; not killing it."
      exit 1
      ;;
  esac
done
if [ -n "$EXISTING" ]; then
  echo "Stopping existing quarkus process on port $PORT (PID $EXISTING)"
  kill $EXISTING 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    lsof -ti "tcp:$PORT" -sTCP:LISTEN >/dev/null 2>&1 || break
    sleep 1
  done
fi

# Start in background, detached from this shell's stdin
nohup mvn quarkus:dev \
  -Dquarkus.http.port="$PORT" \
  -Dquarkus.live-reload.enabled=true \
  < /dev/null > "$LOG" 2>&1 &
PID=$!
echo "PID: $PID"

# Wait up to 60s for startup
for i in $(seq 1 60); do
  if grep -q "Listening on:" "$LOG" 2>/dev/null; then
    break
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Process exited unexpectedly. Last log lines:"
    tail -20 "$LOG"
    exit 1
  fi
  sleep 1
done

echo ""
if ! grep -E "Listening on:|Dev UI available at|started in|Quarkus .* started" "$LOG"; then
  echo "Not listening after 60s (PID $PID still running). Errors so far:"
  grep -E "ERROR|Exception|FAILURE" "$LOG" | tail -10 || true
  echo "Full log: $LOG"
fi
