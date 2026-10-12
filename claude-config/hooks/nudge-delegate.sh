#!/usr/bin/env bash
# PreToolUse nudge for Bash. Never blocks. Injects a one-line reminder into the
# model's context when a main-thread Bash call looks like:
#   - a read-only search/nav command   -> should go to the `code-search` agent (haiku)
#   - a test run                       -> should go to `quick-triage` / `test-aggregator`
#   - an inlined secret                -> read from env/file instead
# Read-only search/nav nudges only on a chain (2+ in a 90s window per session); a single
# call is allowed inline. Git queries and test runs always nudge. Every nudge is appended
# (category only, never command text) to $STATE/delegation-nudges.tsv.

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0
# Subagent calls are already delegated; only the main thread is nudged.
[ -n "$(printf '%s' "$input" | jq -r '.agent_id // empty')" ] && exit 0

STATE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state"
sid=$(printf '%s' "$input" | jq -r '.session_id // "x"' | tr -c 'A-Za-z0-9-' '_')
now=$(date +%s)
cat_=""

chain() {
  mkdir -p "$STATE/chain" 2>/dev/null || return 1
  [ $((now % 50)) -eq 0 ] && find "$STATE/chain" -type f -mtime +1 -delete 2>/dev/null
  f="$STATE/chain/$sid"
  prev=$(cat "$f" 2>/dev/null || echo 0)
  printf '%s' "$now" > "$f" 2>/dev/null
  [ $((now - prev)) -lt 90 ]
}

# Strip leading env assignments (FOO=bar cmd ...) and a leading `cd x &&`.
first=$(printf '%s' "$cmd" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//; s/^cd [^&;]* *(&&|;) *//' | awk '{print $1}')

msg=""
case "$first" in
  grep|rg|find|cat|ls|tail|head|wc|sed|awk|tree|fd)
    if chain; then
      cat_="$first"
      msg="delegation: read-only search/nav belongs in the code-search agent (haiku), not the main thread. Batch related lookups into one dispatch."
    fi
    ;;
  git)
    sub=$(printf '%s' "$cmd" | sed -E 's/^git +//' | awk '{print $1}')
    case "$sub" in
      log|diff|show|blame)
        cat_="git-$sub"
        msg="delegation: when more than one read-only git query (log/diff/show/blame) is needed, batch them into one code-search dispatch."
        ;;
    esac
    ;;
  psql)
    if printf '%s' "$cmd" | grep -Eiq -- "-c +[\"']? *(select|explain|show|with)[ (]"; then
      cat_="psql-readonly"
      msg="psql: read-only query via plain psql prompts for permission; use 'bash ~/.claude/skills/psql-select/select.sh <same psql args>' (auto-approved)."
    fi
    ;;
  mvn|./mvnw|gradle|./gradlew|pytest|uv|python|python3|npm|npx|ng)
    if printf '%s' "$cmd" | grep -Eq '(^| )(test|verify|pytest|surefire:test|failsafe:integration-test|ng test|playwright test)( |$)' \
       && ! printf '%s' "$cmd" | grep -Eq -- '-Dtest='; then
      cat_="test"
      msg="delegation: test runs go through quick-triage (haiku) and failures through test-aggregator; do not run and parse test output in the main thread."
    fi
    ;;
esac

# Secret hygiene: inline bearer/JWT/token literals in a command.
if printf '%s' "$cmd" | grep -Eq '(TOKEN|SECRET|PASSWORD|API_KEY|APIKEY)=["'"'"']?[A-Za-z0-9._-]{20,}|Bearer [A-Za-z0-9._-]{20,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.'; then
  msg="${msg:+$msg }hygiene: a token/secret literal is inlined in this command; read it from an env var or file instead (it is persisted in the session transcript)."
fi

[ -z "$msg" ] && exit 0

mkdir -p "$STATE" 2>/dev/null && printf '%s\t%s\t%s\t%s\n' "$now" "$sid" "${cat_:-hygiene}" "$(basename "$PWD")" >> "$STATE/delegation-nudges.tsv" 2>/dev/null

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
