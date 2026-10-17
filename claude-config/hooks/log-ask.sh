#!/usr/bin/env bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
# PermissionRequest hook: appends one JSON line per permission dialog to
# $STATE/permission-log.jsonl for skills/delegation-audit/permissions.py. Log-only: prints
# nothing and always exits 0, so it can never approve or deny a request.
# Edit/Write/NotebookEdit log file_path only; any tool with a command input (Bash runs
# bash/zsh/ksh alike, PowerShell) logs it as `command`; inputs are cut to 500 chars with
# tokens, passwords and JWTs redacted. Rotates to .1 at 5 MB.

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
STATE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state"
LOG="$STATE/permission-log.jsonl"
mkdir -p "$STATE" 2>/dev/null || exit 0

[ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 5242880 ] && mv -f "$LOG" "$LOG.1" 2>/dev/null

printf '%s' "$input" | jq -c '
  def redact:
    gsub("(?<k>[A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY)[A-Za-z0-9_]*)=[^\\s\"'"'"';]+"; "\(.k)=<redacted>"; "i")
    | gsub("(?<k>bearer\\s+)[^\\s\"'"'"';]+"; "\(.k)<redacted>"; "i")
    | gsub("eyJ[\\w-]{10,}\\.[\\w-]{10,}\\.[\\w-]*"; "<jwt>");
  {
    ts: (now | todate),
    session: .session_id,
    agent: (.agent_id // null),
    mode: (.permission_mode // null),
    cwd,
    tool: .tool_name,
    input: (
      if (.tool_name | test("^(Write|Edit|MultiEdit|NotebookEdit)$"))
      then {file_path: (.tool_input.file_path // .tool_input.notebook_path)}
      elif (.tool_input.command | type) == "string"
      then {command: (.tool_input.command | redact | .[0:500])}
      else {raw: ((.tool_input // {}) | tostring | redact | .[0:500])}
      end)
  }' >> "$LOG" 2>/dev/null

exit 0
