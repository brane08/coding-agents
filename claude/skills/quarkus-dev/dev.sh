#!/bin/bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}"

LOG=/tmp/quarkus-dev.log
PORT=${QUARKUS_PORT:-8080}

# Kill any existing quarkus:dev on that port
EXISTING=$(lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  echo "Killing existing process on port $PORT (PID $EXISTING)"
  kill $EXISTING 2>/dev/null || true
  sleep 1
fi

# Start in background
mvn quarkus:dev \
  -Dquarkus.http.port=$PORT \
  -Dquarkus.live-reload.enabled=true \
  > "$LOG" 2>&1 &
PID=$!
echo "PID: $PID"

# Wait up to 60s for startup
for i in $(seq 1 60); do
  if grep -q "Listening on:" "$LOG" 2>/dev/null; then
    break
  fi
  if ! kill -0 $PID 2>/dev/null; then
    echo "Process exited unexpectedly. Last log lines:"
    tail -20 "$LOG"
    exit 1
  fi
  sleep 1
done

echo ""
grep -E "Listening on:|Dev UI available at|started in|Quarkus .* started" "$LOG" || \
  echo "Startup may still be in progress. Check: tail -f $LOG"
