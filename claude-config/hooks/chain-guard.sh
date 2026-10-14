#!/usr/bin/env bash
# PreToolUse hook (main thread only; admin profile). Denies the 3rd consecutive lookup
# (read-only Bash command, Grep or Glob) with no Edit/Write/Agent in between, and points at
# a single code-search dispatch. Read and non-lookup Bash calls are neutral. Per-session
# counter lives in $STATE/chain/<session>. Deny is logged (category only) to
# $STATE/delegation-nudges.tsv.

input=$(cat)
[ -n "$(printf '%s' "$input" | jq -r '.agent_id // empty')" ] && exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')
STATE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state"
sid=$(printf '%s' "$input" | jq -r '.session_id // "x"' | tr -c 'A-Za-z0-9-' '_')
f="$STATE/chain/$sid"

case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit|Agent|Task)
    [ -f "$f" ] && printf '0' > "$f"
    exit 0
    ;;
  Grep|Glob)
    case "$(printf '%s' "$input" | jq -r '.tool_input.path // empty')" in
      */.claude/memory/*|*/.claude/projects/*) exit 0 ;;
    esac
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    case "$cmd" in
      */.claude/memory/*|*/.claude/projects/*) exit 0 ;;
    esac
    c=$(printf '%s' "$cmd" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//')
    set -- $c
    case "$1" in
      grep|rg|find|cat|ls|tail|head|wc|sed|awk|tree|fd) ;;
      git) case "$2" in log|diff|show|blame) ;; *) exit 0 ;; esac ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac

mkdir -p "$STATE/chain" 2>/dev/null
n=$(cat "$f" 2>/dev/null)
n=${n:-0}

if [ "$n" -ge 2 ]; then
  printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$sid" "chain-deny" "$(basename "$PWD")" >> "$STATE/delegation-nudges.tsv" 2>/dev/null
  jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"3rd consecutive lookup with no edit in between: dispatch one code-search with all remaining questions (ask for path:startLine-endLine), then Read those ranges."}}'
  exit 0
fi

printf '%s' "$((n + 1))" > "$f"
exit 0
