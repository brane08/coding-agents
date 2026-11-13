#Requires -Version 5.1
# PermissionRequest hook: appends one JSON line per permission dialog to
# $STATE/permission-log.jsonl for skills/delegation-audit/permissions.py. Log-only: prints
# nothing and always exits 0, so it can never approve or deny a request.
# Inputs are cut to 500 chars with tokens, passwords and JWTs redacted. Rotates to .1 at 5 MB.
Import-Module AgentCommon -Force -ErrorAction SilentlyContinue
if (-not (Get-Module AgentCommon)) { Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/Common.psm1') -Force }

function Protect-Secrets {
    param([string]$Text)
    $t = [regex]::Replace($Text, '(?i)([A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY)[A-Za-z0-9_]*)=[^\s"'';]+', '$1=<redacted>')
    $t = [regex]::Replace($t, '(?i)(bearer\s+)[^\s"'';]+', '$1<redacted>')
    $t = [regex]::Replace($t, 'eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]*', '<jwt>')
    return $t
}

function Limit-Text {
    param([string]$Text)
    if ($Text.Length -gt 500) { return $Text.Substring(0, 500) }
    return $Text
}

try {
    $in = Read-HookInput
    if ($null -eq $in) { exit 0 }
    $state = Get-StateDir
    if (-not (Test-Path -LiteralPath $state)) { New-Item -ItemType Directory -Path $state -Force | Out-Null }
    $log = Join-Path $state 'permission-log.jsonl'
    if ((Test-Path -LiteralPath $log) -and ((Get-Item -LiteralPath $log).Length -gt 5242880)) {
        Move-Item -LiteralPath $log -Destination ($log + '.1') -Force
    }

    $tool = [string](Get-Prop $in 'tool_name')
    $ti = Get-Prop $in 'tool_input'
    $cmd = Get-Prop $ti 'command'
    if ($tool -match '^(Write|Edit|MultiEdit|NotebookEdit)$') {
        $fp = Get-Prop $ti 'file_path'
        if ($null -eq $fp) { $fp = Get-Prop $ti 'notebook_path' }
        $inputObj = [ordered]@{ file_path = $fp }
    } elseif ($cmd -is [string]) {
        $inputObj = [ordered]@{ command = (Limit-Text (Protect-Secrets $cmd)) }
    } else {
        $raw = if ($null -eq $ti) { '{}' } else { ConvertTo-Json -InputObject $ti -Compress -Depth 10 }
        $inputObj = [ordered]@{ raw = (Limit-Text (Protect-Secrets $raw)) }
    }

    $rec = [ordered]@{
        ts      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        session = (Get-Prop $in 'session_id')
        agent   = (Get-Prop $in 'agent_id')
        mode    = (Get-Prop $in 'permission_mode')
        cwd     = (Get-Prop $in 'cwd')
        tool    = $tool
        input   = $inputObj
    }
    Add-Utf8Line $log (ConvertTo-Json -InputObject $rec -Compress -Depth 10)
} catch { }
exit 0
