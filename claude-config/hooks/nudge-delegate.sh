#!/usr/bin/env bash
# PreToolUse nudge for Bash. Never blocks. Injects a one-line reminder into the
# model's context when a main-thread Bash call looks like:
#   - a read-only search/nav command   -> should go to the `code-search` agent (haiku)
#   - a test run                       -> should go to `quick-triage` / `test-aggregator`
#   - an inlined secret                -> read from env/file instead
# Subagents run the same hook and receive this text too; it is addressed to the main thread.

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

# Strip leading env assignments (FOO=bar cmd ...) and a leading `cd x &&`.
first=$(printf '%s' "$cmd" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//; s/^cd [^&;]* *(&&|;) *//' | awk '{print $1}')

msg=""
case "$first" in
  grep|rg|find|cat|ls|tail|head|wc|sed|awk|tree|fd)
    msg="delegation: read-only search/nav belongs in the code-search agent (haiku), not the main thread. Batch related lookups into one dispatch."
    ;;
  git)
    sub=$(printf '%s' "$cmd" | sed -E 's/^git +//' | awk '{print $1}')
    case "$sub" in
      log|diff|show|blame)
        msg="delegation: when more than one read-only git query (log/diff/show/blame) is needed, batch them into one code-search dispatch."
        ;;
    esac
    ;;
  mvn|./mvnw|gradle|./gradlew|pytest|uv|python|python3|npm|npx|ng)
    if printf '%s' "$cmd" | grep -Eq '(^| )(test|verify|pytest|surefire:test|failsafe:integration-test|ng test|playwright test)( |$)' \
       && ! printf '%s' "$cmd" | grep -Eq -- '-Dtest='; then
      msg="delegation: test runs go through quick-triage (haiku) and failures through test-aggregator; do not run and parse test output in the main thread."
    fi
    ;;
esac

# Secret hygiene: inline bearer/JWT/token literals in a command.
if printf '%s' "$cmd" | grep -Eq '(TOKEN|SECRET|PASSWORD|API_KEY|APIKEY)=["'"'"']?[A-Za-z0-9._-]{20,}|Bearer [A-Za-z0-9._-]{20,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.'; then
  msg="${msg:+$msg }hygiene: a token/secret literal is inlined in this command; read it from an env var or file instead (it is persisted in the session transcript)."
fi

[ -z "$msg" ] && exit 0

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
