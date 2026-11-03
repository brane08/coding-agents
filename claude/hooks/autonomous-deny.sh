#!/usr/bin/env bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
# PermissionRequest hook: during an autonomous run (CLAUDE_AUTONOMOUS=1) every permission
# dialog is auto-denied so the loop never blocks on a prompt. Without CLAUDE_AUTONOMOUS=1 it
# prints nothing and exits 0, leaving the normal dialog untouched. Always exits 0.

cat >/dev/null 2>&1

[ "${CLAUDE_AUTONOMOUS:-}" = "1" ] || exit 0

printf '%s' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Autonomous run: no prompts. Mark the item BLOCKED with this reason and continue.","interrupt":false}}}'
exit 0
