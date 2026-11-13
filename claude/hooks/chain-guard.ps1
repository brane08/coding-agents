#Requires -Version 5.1
# PreToolUse hook (main thread only; admin profile). Denies the 7th consecutive lookup
# (read-only Bash command, Grep or Glob) with no Edit/Write/Agent in between, and points at
# a single code-search dispatch. Read and non-lookup Bash calls are neutral, including scripts
# run with bash/zsh/ksh/sh/dash/powershell/pwsh; `<shell> -c "<cmd>"` is judged by <cmd>.
# Per-session counter lives in $STATE/chain/<session>.
Import-Module AgentCommon -Force -ErrorAction SilentlyContinue
if (-not (Get-Module AgentCommon)) { Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/Common.psm1') -Force }

$in = Read-HookInput
if ($null -eq $in) { exit 0 }
if ($null -ne (Get-Prop $in 'agent_id') -and [string](Get-Prop $in 'agent_id') -ne '') { exit 0 }

$tool = [string](Get-Prop $in 'tool_name')
$sid = Get-SafeSid (Get-Prop $in 'session_id')
$chainDir = Join-Path (Get-StateDir) 'chain'
$f = Join-Path $chainDir $sid

$stripEnv = '^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*'
$skip = '.claude/(memory|projects)/'

switch -Regex ($tool) {
    '^(Edit|Write|MultiEdit|NotebookEdit|Agent|Task)$' {
        if (Test-Path -LiteralPath $f) { Write-Utf8File $f '0' }
        exit 0
    }
    '^(Grep|Glob)$' {
        $p = [string](Get-Prop $in 'tool_input', 'path')
        if (($p -replace '\\', '/') -match $skip) { exit 0 }
    }
    '^Bash$' {
        $cmd = [string](Get-Prop $in 'tool_input', 'command')
        if (($cmd -replace '\\', '/') -match $skip) { exit 0 }
        $c = [regex]::Replace($cmd, $stripEnv, '')
        $m = [regex]::Match($c, '^(bash|zsh|ksh|sh|dash) +-[a-z]*c[a-z]* +(["''])(.*)\2 *$')
        if ($m.Success) { $c = [regex]::Replace($m.Groups[3].Value, $stripEnv, '') }
        $tok = @($c.Trim() -split '\s+')
        $first = $tok[0]
        $second = if ($tok.Count -gt 1) { $tok[1] } else { '' }
        if ($first -match '^(bash|zsh|ksh|sh|dash|powershell|pwsh)(\.exe)?$') { exit 0 }
        if ($first -match '^(grep|rg|find|cat|ls|tail|head|wc|sed|awk|tree|fd|Get-ChildItem|Get-Content|Select-String|gci|gc|sls|dir|type)$') {
            # lookup
        } elseif ($first -ceq 'git') {
            if ($second -cnotmatch '^(log|diff|show|blame)$') { exit 0 }
        } else { exit 0 }
    }
    default { exit 0 }
}

$n = 0
if (Test-Path -LiteralPath $f) {
    $raw = ([System.IO.File]::ReadAllText($f)).Trim()
    if ($raw -match '^\d+$') { $n = [int]$raw }
}

$limit = 7

if ($n -ge ($limit - 1)) {
    Add-Utf8Line (Join-Path (Get-StateDir) 'delegation-nudges.tsv') ("{0}`t{1}`tchain-deny`t{2}" -f (Get-EpochSeconds), $sid, (Split-Path -Leaf (Get-Location).Path))
    Write-Decision deny ("${limit}th consecutive lookup with no edit in between: dispatch one code-search with all remaining questions (ask for path:startLine-endLine), then Read those ranges.")
    exit 0
}

if (-not (Test-Path -LiteralPath $chainDir)) { New-Item -ItemType Directory -Path $chainDir -Force | Out-Null }
Write-Utf8File $f ([string]($n + 1))
exit 0
