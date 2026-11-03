#Requires -Version 5.1
# PreToolUse hook for Bash (main thread only). Denies a `cd <dir> &&` prefix and
# piped/chained (|, ;, &&) lookup commands (grep/rg/find/ls/cat/head/tail/wc/sed/awk).
# Injects a one-line reminder for: read-only psql queries, `git -C`, inlined secrets.
# Every deny/nudge is appended (category only, never command text) to
# $STATE/delegation-nudges.tsv.
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/Common.psm1') -Force

$in = Read-HookInput
if ($null -eq $in) { exit 0 }
$cmd = [string](Get-Prop $in 'tool_input', 'command')
if ($cmd -eq '') { exit 0 }
if ([string](Get-Prop $in 'agent_id') -ne '') { exit 0 }

$sid = Get-SafeSid (Get-Prop $in 'session_id')
$cat = ''
$msg = ''

$stripped = [regex]::Replace($cmd, '^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*', '')
$stripped = [regex]::Replace($stripped, '^cd [^&;]* *(&&|;) *', '')
$firstLine = ($stripped -split "`n")[0]
$tok = @($firstLine.Trim() -split '\s+')
$first = $tok[0]

if ($first -ceq 'psql') {
    if ($cmd -match '-c +["'']? *(select|explain|show|with)[ (]') {
        $cat = 'psql-readonly'
        $msg = "psql: use 'powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/skills/psql-select/select.ps1 `"<sql>`"' for read-only queries (enforced read-only)."
    }
}

if ($cmd -cmatch '^cd [^&;|]+(&&|;)') {
    Add-Nudge $sid 'cd-prefix-deny'
    Write-Decision deny 'Blocked: drop the "cd <dir> &&" prefix (cwd persists; compound commands prompt). Use an absolute path, plain git in the current repo, mvn ... -pl <module> -am from the repo root, or npm --prefix / pytest <pkg dir>.'
    exit 0
} elseif ($cmd -cmatch '^([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*git +-C ') {
    if ($cat -eq '') { $cat = 'git-C' }
    $msg = (($msg + " approvals: run plain 'git ...' in the current repo (it works from any subdirectory); -C defeats allow rules.").Trim())
}

if ($first -cmatch '^(grep|rg|find|ls|cat|head|tail|wc|sed|awk)$') {
    $unquoted = [regex]::Replace($cmd, '"([^"\\]|\\.)*"', '')
    $unquoted = [regex]::Replace($unquoted, "'[^']*'", '')
    if ($unquoted -match '\||;|&&') {
        Add-Nudge $sid 'lookup-chain-deny'
        Write-Decision deny 'Blocked: one command per call, no |, ; or &&. Use Read with offset/limit or dispatch one code-search (Grep tool only for a single locate-before-edit).'
        exit 0
    }
}

if ($cmd -cmatch '(TOKEN|SECRET|PASSWORD|API_KEY|APIKEY)=["'']?[A-Za-z0-9._-]{20,}|Bearer [A-Za-z0-9._-]{20,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.') {
    $msg = (($msg + ' hygiene: a token/secret literal is inlined in this command; read it from an env var or file instead (it is persisted in the session transcript).').Trim())
}

if ($msg -eq '') { exit 0 }
if ($cat -eq '') { $cat = 'hygiene' }
Add-Nudge $sid $cat
Write-Context $msg
exit 0
