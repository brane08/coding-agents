#!/bin/bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
# Usage: flyway-check.sh [database]
# Database precedence: argument > $DB_NAME > "dev". $DB_URL, if set, is used as-is
# and the database argument is ignored. Local DBs use trust auth: no password handling.
# Maven runs from the project root ($CLAUDE_PROJECT_DIR, else the current directory);
# set FLYWAY_MODULE to a module path to pass -pl <module> -am.
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}"

DB_NAME="${1:-${DB_NAME:-dev}}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
if [ -n "${1:-}" ]; then
  DB_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"
else
  DB_URL="${DB_URL:-jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}}"
fi
DB_USER="${DB_USER:-dev}"

mod_args=()
if [ -n "${FLYWAY_MODULE:-}" ]; then
  if ! [[ "$FLYWAY_MODULE" =~ ^[A-Za-z0-9._,:/-]+$ ]]; then
    echo "ERROR: invalid FLYWAY_MODULE: $FLYWAY_MODULE"
    exit 2
  fi
  mod_args=(-pl "$FLYWAY_MODULE" -am)
fi

mvn flyway:info \
  ${mod_args[@]+"${mod_args[@]}"} \
  -Dflyway.url="$DB_URL" \
  -Dflyway.user="$DB_USER" \
  2>&1 | grep -E "Version|State|Pending|current|Failed|Checksum" | grep -v "^\[INFO\] ---"
