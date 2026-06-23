#!/bin/bash
set -euo pipefail

cd "${CLAUDE_PROJECT_DIR:-.}"

# Defaults — override via env or .env file
DB_URL="${DB_URL:-jdbc:postgresql://localhost:5432/dev}"
DB_USER="${DB_USER:-dev}"
DB_PASS="${DB_PASS:-dev}"

# Source .env if present (for project-local overrides)
[ -f .env ] && source .env

mvn flyway:info \
  -Dflyway.url="$DB_URL" \
  -Dflyway.user="$DB_USER" \
  -Dflyway.password="$DB_PASS" \
  2>&1 | grep -E "Version|State|Pending|current|Failed|Checksum" | grep -v "^\[INFO\] ---"
