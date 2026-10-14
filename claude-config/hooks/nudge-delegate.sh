#!/usr/bin/env bash
# PreToolUse hook for Bash (main thread only). Denies a `cd <dir> &&` prefix and
# piped/chained (|, ;, &&) lookup commands (grep/rg/find/ls/cat/head/tail/wc/sed/awk).
# Injects a one-line reminder for: read-only psql queries, `git -C`, inlined secrets.
# Every deny/nudge is appended (category only, never command text) to
# $STATE/delegation-nudges.tsv.

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0
# Subagent calls are already delegated; only the main thread is nudged.
[ -n "$(printf '%s' "$input" | jq -r '.agent_id // empty')" ] && exit 0

STATE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state"
sid=$(printf '%s' "$input" | jq -r '.session_id // "x"' | tr -c 'A-Za-z0-9-' '_')
now=$(date +%s)
cat_=""

# Strip leading env assignments (FOO=bar cmd ...) and a leading `cd x &&`.
first=$(printf '%s' "$cmd" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*//; s/^cd [^&;]* *(&&|;) *//' | awk '{print $1}')

msg=""
case "$first" in
  psql)
    if printf '%s' "$cmd" | grep -Eiq -- "-c +[\"']? *(select|explain|show|with)[ (]"; then
      cat_="psql-readonly"
      msg="psql: read-only query via plain psql prompts for permission; use 'bash ~/.claude/skills/psql-select/select.sh <same psql args>' (auto-approved)."
    fi
    ;;
esac

# Prompt hygiene: `cd x &&` prefixes and `git -C` defeat allow rules; cwd already persists.
if printf '%s' "$cmd" | grep -Eq '^cd [^&;|]+(&&|;)'; then
  mkdir -p "$STATE" 2>/dev/null && printf '%s\t%s\t%s\t%s\n' "$now" "$sid" "cd-prefix-deny" "$(basename "$PWD")" >> "$STATE/delegation-nudges.tsv" 2>/dev/null
  jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Blocked: drop the \"cd <dir> &&\" prefix (cwd persists; compound commands prompt). Use an absolute path, plain git in the current repo, mvn ... -pl <module> -am from the repo root, or npm --prefix / pytest <pkg dir>."}}'
  exit 0
elif printf '%s' "$cmd" | grep -Eq '^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*git +-C '; then
  cat_="${cat_:-git-C}"
  msg="${msg:+$msg }approvals: run plain 'git ...' in the current repo (it works from any subdirectory); -C defeats allow rules."
fi

# Piped/chained lookups prompt (compound commands defeat allow rules): steer to native tools.
case "$first" in
  grep|rg|find|ls|cat|head|tail|wc|sed|awk)
    unquoted=$(printf '%s' "$cmd" | sed -E "s/\"([^\"\\\\]|\\\\.)*\"//g; s/'[^']*'//g")
    if printf '%s' "$unquoted" | grep -Eq '\||;|&&'; then
      mkdir -p "$STATE" 2>/dev/null && printf '%s\t%s\t%s\t%s\n' "$now" "$sid" "lookup-chain-deny" "$(basename "$PWD")" >> "$STATE/delegation-nudges.tsv" 2>/dev/null
      jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Blocked: one command per call, no |, ; or &&. Use the Grep tool (head_limit, -n, -A/-B) or Read with offset/limit; for 3+ lookups dispatch one code-search."}}'
      exit 0
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
