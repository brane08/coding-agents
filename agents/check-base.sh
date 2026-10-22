#!/usr/bin/env bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
# Compares the tool-free base agents (agents/agents/<n>.md) with the full tool versions.
# The base is only a baseline: tool files stay complete and may differ from it.
#   - base files must not mention a specific tool (claude, copilot)   -> always an error (exit 1)
#   - claude/agents/<n>.md vs base: description and body differences  -> reported, exit 0
#     (body = text after the frontmatter, up to the "## Claude Code specifics" heading or end of file)
# Usage: bash agents/check-base.sh [--strict]    --strict also fails (exit 1) when a tool file differs
set -euo pipefail

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/agents/agents"
CLAUDE="$ROOT/claude/agents"
ERRORS=0
DRIFT=0

body() {
  awk '
    /^---$/ && n < 2 { n++; next }
    n < 2 { next }
    /^## .* specifics$/ { exit }
    /^$/ { blank++; next }
    { while (blank > 0) { print ""; blank-- } print }
  ' "$1"
}

desc() { grep -m1 '^description:' "$1" || true; }

for base in "$BASE"/*.md; do
  name=$(basename "$base")
  if grep -nEi 'claude|copilot|omitClaudeMd' "$base" >&2; then
    echo "ERROR not tool-free: $base" >&2; ERRORS=1
  fi
  tool="$CLAUDE/$name"
  if [ ! -f "$tool" ]; then echo "note: no claude version of $name" >&2; continue; fi
  if [ "$(desc "$base")" != "$(desc "$tool")" ]; then echo "drift: description differs: $name" >&2; DRIFT=1; fi
  if ! diff -u <(body "$base") <(body "$tool") >&2; then echo "drift: body differs: $name" >&2; DRIFT=1; fi
done

for tool in "$CLAUDE"/*.md; do
  [ -f "$BASE/$(basename "$tool")" ] || echo "note: claude-only agent (no base): $(basename "$tool")" >&2
done

[ "$ERRORS" = 0 ] && [ "$DRIFT" = 0 ] && echo "base agents are tool-free and claude/agents matches them"
[ "$ERRORS" = 0 ] && [ "$DRIFT" = 1 ] && echo "base agents are tool-free; some claude/agents differ from the base (see above)"
[ "$ERRORS" = 1 ] && exit 1
[ "$STRICT" = 1 ] && [ "$DRIFT" = 1 ] && exit 1
exit 0
