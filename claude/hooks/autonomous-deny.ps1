#Requires -Version 5.1
# PermissionRequest hook: during an autonomous run (CLAUDE_AUTONOMOUS=1) every permission
# dialog is auto-denied so the loop never blocks on a prompt. Without CLAUDE_AUTONOMOUS=1 it
# prints nothing and exits 0, leaving the normal dialog untouched. Always exits 0.
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/Common.psm1') -Force

try {
    [void](Read-HookInput)
    if ($env:CLAUDE_AUTONOMOUS -ne '1') { exit 0 }
    Write-Stdout '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Autonomous run: no prompts. Mark the item BLOCKED with this reason and continue.","interrupt":false}}}'
} catch { }
exit 0
