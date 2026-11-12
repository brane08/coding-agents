#!/usr/bin/env bash
# Token usage per model from local Claude Code session transcripts (read-only).
# Usage: report.sh [project-name-substring]
# Prints main-session and subagent usage separately. Counts are token counts, not cost.
if [ -z "${BASH_VERSION-}" ]; then
  if command -v bash >/dev/null 2>&1; then exec bash "$0" "$@"; fi
  echo "token-report: bash not found" >&2
  exit 127
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "token-report: jq not found" >&2
  exit 127
fi

here="$(cd "$(dirname "$0")" && pwd)"
projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
filter="${1-}"

if [ ! -d "$projects" ]; then
  echo "token-report: no transcripts dir at $projects" >&2
  exit 1
fi

print_table() {
  local title="$1"; shift
  local files=("$@")
  echo "== $title (${#files[@]} files)"
  if [ "${#files[@]}" -eq 0 ]; then
    echo "(none)"
    return
  fi
  local rows
  rows="$(jq -r -n -f "$here/usage.jq" "${files[@]}")" || { echo "token-report: jq failed" >&2; return 1; }
  local table
  table="$(printf 'model\tsessions\tmsgs\tinput\toutput\tcache_read\tcache_create\tcache_read/msg\n%s\n' "$rows")"
  if command -v column >/dev/null 2>&1; then
    column -t -s "$(printf '\t')" <<< "$table"
  else
    printf '%s\n' "$table"
  fi
}

shopt -s nullglob
main=("$projects"/*"$filter"*/*.jsonl)
sub=("$projects"/*"$filter"*/*/subagents/*.jsonl)

print_table "main sessions" "${main[@]}"
echo
print_table "subagent transcripts" "${sub[@]}"
echo
echo "Token counts only (no pricing). Messages are de-duplicated by message id."
