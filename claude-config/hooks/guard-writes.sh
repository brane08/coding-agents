#!/usr/bin/env bash
# PreToolUse guard for file-writing tools.
#
#   inside project          -> pass through (normal permission rules apply)
#   agent scratchpad only   -> pass through (claude-<uid>/ dirs under a tmp root)
#   ~/.claude (config)      -> ask
#   anywhere else           -> deny
#
# Limitation: only covers Claude Code's file tools. A subprocess that opens files
# itself (python, node, a build script) is not intercepted. For OS-level
# enforcement use the sandbox.

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"guard-writes: jq missing, cannot verify write path"}}'
  exit 0
fi

f=$(printf '%s' "$input" | jq -r '
  .tool_input.file_path // .tool_input.notebook_path // empty
')
[ -z "$f" ] && exit 0

# Absolutize. The target usually does not exist yet, and on macOS /tmp is a
# symlink to /private/tmp -- so resolve the nearest EXISTING ancestor and re-append
# the rest. Resolving only the immediate parent fails for a new subdirectory and
# would leave /tmp/... unresolved, causing a false deny.
case "$f" in
  /*) abs="$f" ;;
  *)  abs="$PWD/$f" ;;
esac

# An existing symlink is judged by its target, not its own location.
n=0
while [ -L "$abs" ] && [ "$n" -lt 10 ]; do
  t=$(readlink "$abs")
  case "$t" in
    /*) abs="$t" ;;
    *)  abs="$(dirname "$abs")/$t" ;;
  esac
  n=$((n + 1))
done

rest=""
p="$abs"
while [ ! -d "$p" ] && [ "$p" != "/" ] && [ "$p" != "." ]; do
  rest="/$(basename "$p")$rest"
  p=$(dirname "$p")
done
if [ -d "$p" ] && rp=$(cd "$p" 2>/dev/null && pwd -P); then
  abs="$rp$rest"
fi
# `..` after a not-yet-existing directory is never normalised above; refuse it.
case "$rest" in
  */..|*/../*)
    printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Path contains .. after a non-existent directory; use a normalised path"}}'
    exit 0 ;;
esac
abs=${abs%/}
[ -z "$abs" ] && abs="/"

canon() { cd "$1" 2>/dev/null && pwd -P || printf '%s' "${1%/}"; }

proj=$(canon "${CLAUDE_PROJECT_DIR:-$PWD}")
cfg=$(canon "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")

# Agent scratchpad roots. Only claude-<uid>/ subdirectories of a tmp root are
# writable -- NOT the whole of /tmp.
scratch_ok=0
for root in "${CLAUDE_CODE_TMPDIR:-}" "${TMPDIR:-}" /tmp; do
  [ -z "$root" ] && continue
  r=$(canon "${root%/}")
  case "$abs" in
    "$r"/claude-*) scratch_ok=1; break ;;
  esac
done

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":%s}}' \
    "$1" "$(printf '%s' "$2" | jq -Rs .)"
}

[ "$scratch_ok" = 1 ] && exit 0

case "$abs" in
  "$proj"|"$proj"/*) exit 0 ;;
  "$cfg"|"$cfg"/*)
    emit ask "Writes to global Claude config: $abs"
    exit 0 ;;
  *)
    emit deny "Writes outside the project are not allowed: $abs"
    exit 0 ;;
esac
