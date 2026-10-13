#!/bin/bash
# Usage: flyway-check.sh [database]
# Database precedence: argument > $DB_NAME > "dev". $DB_URL, if set, is used as-is
# and the database argument is ignored. Credentials come from env or .env, never the command line.
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}"

# Source .env if present (for project-local overrides)
[ -f .env ] && source .env

DB_NAME="${1:-${DB_NAME:-dev}}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
if [ -n "${1:-}" ]; then
  DB_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}"
else
  DB_URL="${DB_URL:-jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}}"
fi
DB_USER="${DB_USER:-dev}"
DB_PASS="${DB_PASS:-}"

# Local DBs usually use trust auth: pass a password only when one is set.
pass_args=()
[ -n "$DB_PASS" ] && pass_args=(-Dflyway.password="$DB_PASS")

mvn flyway:info \
  -Dflyway.url="$DB_URL" \
  -Dflyway.user="$DB_USER" \
  ${pass_args[@]+"${pass_args[@]}"} \
  2>&1 | grep -E "Version|State|Pending|current|Failed|Checksum" | grep -v "^\[INFO\] ---"
