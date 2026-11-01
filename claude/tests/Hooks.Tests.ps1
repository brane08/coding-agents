#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$hooks = Join-Path (Split-Path -Parent $PSScriptRoot) 'hooks'

function J { param($o) ConvertTo-Json -InputObject $o -Compress -Depth 10 }
function Bash { param([string]$c, [string]$sid = 's1', $agent = $null)
    $o = @{ tool_name = 'Bash'; session_id = $sid; tool_input = @{ command = $c } }
    if ($agent) { $o.agent_id = $agent }
    J $o
}

$root = New-TempDir
$proj = Join-Path $root 'my proj'
$cfg = Join-Path $root 'cfg'
$tmpRoot = Join-Path $root 'tmp'
New-Item -ItemType Directory -Path $proj, $cfg, $tmpRoot | Out-Null
$env1 = @{ CLAUDE_PROJECT_DIR = $proj; CLAUDE_CONFIG_DIR = $cfg; CLAUDE_CODE_TMPDIR = $tmpRoot }

Write-Host 'guard-writes'
$gw = Join-Path $hooks 'guard-writes.ps1'
function W { param([string]$p) J @{ tool_name = 'Write'; tool_input = @{ file_path = $p } } }
$r = Invoke-Script $gw (W (Join-Path $proj 'a.txt')) $env1 -WorkDir $proj
Assert-Equal '' $r.Out 'inside project passes (path with space)'
$r = Invoke-Script $gw (W (Join-Path $cfg 'x.md')) $env1 -WorkDir $proj
Assert-Equal '' $r.Out 'config dir passes'
$r = Invoke-Script $gw (W (Join-Path $tmpRoot 'claude-1000/s/out.txt')) $env1 -WorkDir $proj
Assert-Equal '' $r.Out 'scratchpad claude-* passes'
$r = Invoke-Script $gw (W (Join-Path $tmpRoot 'other/out.txt')) $env1 -WorkDir $proj
Assert-Match '"permissionDecision":"deny"' $r.Out 'non-claude tmp subdir denied'
$outside = Join-Path $root 'elsewhere/x.txt'
$r = Invoke-Script $gw (W $outside) $env1 -WorkDir $proj
Assert-Match 'Writes outside the project are not allowed' $r.Out 'outside project denied'
$r = Invoke-Script $gw (W ((Join-Path $proj 'new') + '/../../elsewhere/x.txt')) $env1 -WorkDir $proj
Assert-Match '"permissionDecision":"deny"' $r.Out 'dotdot escape denied'
$r = Invoke-Script $gw (W 'rel/file.txt') $env1 -WorkDir $proj
Assert-Equal '' $r.Out 'relative path resolves against cwd'
$r = Invoke-Script $gw '' $env1 -WorkDir $proj
Assert-Equal '' $r.Out 'empty stdin passes'
$r = Invoke-Script $gw (J @{ tool_name = 'Write'; tool_input = @{} }) $env1 -WorkDir $proj
Assert-Equal '' $r.Out 'no file_path passes'
$r = Invoke-Script $gw (J @{ tool_name = 'NotebookEdit'; tool_input = @{ notebook_path = $outside } }) $env1 -WorkDir $proj
Assert-Match 'deny' $r.Out 'notebook_path checked'

$isWin = [System.IO.Path]::DirectorySeparatorChar -eq '\'
if (-not $isWin) {
    $linkTarget = Join-Path $root 'linktarget'
    New-Item -ItemType Directory -Path $linkTarget | Out-Null
    & ln -s $linkTarget (Join-Path $proj 'linkdir')
    $r = Invoke-Script $gw (W (Join-Path $proj 'linkdir/x.txt')) $env1 -WorkDir $proj
    Assert-Match '"permissionDecision":"deny"' $r.Out 'write through parent symlink to outside is denied'
}
$r = Invoke-Script $gw '{"tool_name":"Write","tool_input":{"file_path":"a\u0000b"}}' $env1 -WorkDir $proj
Assert-Match '"permissionDecision":"(deny|ask)"' $r.Out 'unnormalisable path fails closed'

Write-Host 'nudge-delegate'
$nd = Join-Path $hooks 'nudge-delegate.ps1'
$r = Invoke-Script $nd (Bash 'cd foo && ls') $env1
Assert-Match 'drop the \\?"cd' $r.Out 'cd prefix denied'
$r = Invoke-Script $nd (Bash 'ls | head') $env1
Assert-Match 'one command per call' $r.Out 'piped lookup denied'
$r = Invoke-Script $nd (Bash 'grep "a|b" file') $env1
Assert-Equal '' $r.Out 'pipe inside quotes allowed'
$r = Invoke-Script $nd (Bash 'psql -h x -c "select 1"') $env1
Assert-Match 'additionalContext.*psql-select' $r.Out 'psql read-only nudged'
$r = Invoke-Script $nd (Bash 'git -C /x status') $env1
Assert-Match 'additionalContext.*approvals' $r.Out 'git -C nudged'
$r = Invoke-Script $nd (Bash 'git status') $env1
Assert-Equal '' $r.Out 'plain git quiet'
$r = Invoke-Script $nd (Bash 'curl -H "Bearer abcdefghijklmnopqrstuvwxyz" x') $env1
Assert-Match 'hygiene' $r.Out 'bearer literal nudged'
$r = Invoke-Script $nd (Bash 'cd foo && ls' 's1' 'agent-1') $env1
Assert-Equal '' $r.Out 'subagent calls ignored'
Assert-True ((Get-Content -Raw (Join-Path $cfg 'state/delegation-nudges.tsv')) -match "cd-prefix-deny") 'nudge logged to tsv'

Write-Host 'chain-guard'
$cg = Join-Path $hooks 'chain-guard.ps1'
$last = $null
for ($i = 1; $i -le 7; $i++) { $last = Invoke-Script $cg (Bash "grep x f$i" 'sc') $env1 }
Assert-Match '7th consecutive lookup' $last.Out '7th lookup denied'
$null = Invoke-Script $cg (J @{ tool_name = 'Edit'; session_id = 'sc'; tool_input = @{} }) $env1
$r = Invoke-Script $cg (Bash 'grep x f' 'sc') $env1
Assert-Equal '' $r.Out 'edit resets counter'
$null = 1..6 | ForEach-Object { Invoke-Script $cg (Bash 'bash ~/x.sh' 'sd') $env1 }
$r = Invoke-Script $cg (Bash 'bash ~/x.sh' 'sd') $env1
Assert-Equal '' $r.Out 'script runs neutral'

Write-Host 'log-ask'
$la = Join-Path $hooks 'log-ask.ps1'
$r = Invoke-Script $la (J @{ session_id = 's9'; cwd = '/p'; tool_name = 'Bash'; permission_mode = 'default'; tool_input = @{ command = 'curl API_KEY=abcdef123456 -H "Bearer tok123"' } }) $env1
Assert-Equal '' $r.Out 'log-ask prints nothing'
$log = Get-Content -Raw (Join-Path $cfg 'state/permission-log.jsonl')
Assert-True (($log -match 'API_KEY=') -and ($log -notmatch 'abcdef123456') -and ($log -notmatch 'tok123')) 'secrets redacted'
$rec = $log.Trim() | ConvertFrom-Json
Assert-Equal 'Bash' $rec.tool 'log record parses'
Assert-True ($log -notmatch '^\xEF\xBB\xBF') 'no BOM'

Write-Host 'guard-git-push'
$gp = Join-Path $hooks 'guard-git-push.ps1'
foreach ($c in @('git push --force origin main', 'git push origin +main', 'git push origin :main', 'git push -fu origin master', 'git push --mirror', 'git push --delete origin main', 'echo hi; git push origin main --force-with-lease')) {
    $r = Invoke-Script $gp (Bash $c) $env1
    Assert-Match '"permissionDecision":"deny"' $r.Out "deny: $c"
}
foreach ($c in @('git.exe push -f origin main', 'GIT push -f origin main', '"git" push -f origin main', '& git push --force origin main', '/usr/bin/git push -f origin main', '"C:\Program Files\Git\cmd\git.exe" push -f origin main')) {
    $r = Invoke-Script $gp (Bash $c) $env1
    Assert-Match '"permissionDecision":"deny"' $r.Out "deny (spelling variant): $c"
}
foreach ($c in @('git push origin feature --force','git push origin main', 'git status', 'git push -u origin feat/x')) {
    $r = Invoke-Script $gp (Bash $c) $env1
    Assert-Equal '' $r.Out "pass: $c"
}

Write-Host 'guard-merged-pr'
$mp = Join-Path $hooks 'guard-merged-pr.ps1'
$r = Invoke-Script $mp (Bash 'git status') $env1
Assert-Equal '' $r.Out 'non-push passes'
$r = Invoke-Script $mp (Bash 'git push origin main') $env1
Assert-Equal '' $r.Out 'protected branch passes'
if (-not $isWin) {
    $stubs = Join-Path $root 'hookstubs'
    New-Item -ItemType Directory -Path $stubs | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $stubs 'gh'), "#!/bin/sh`necho MERGED`n")
    [System.IO.File]::WriteAllText((Join-Path $stubs 'git'), "#!/bin/sh`necho feat/stale`n")
    & chmod +x (Join-Path $stubs 'gh') (Join-Path $stubs 'git')
    $env4 = $env1.Clone(); $env4['PATH'] = $stubs + ':' + $env:PATH
    foreach ($c in @('git push origin feat/stale', 'gh pr create --fill', 'gh --repo o/r pr create', 'git.exe push', 'GH pr create')) {
        $r = Invoke-Script $mp (Bash $c) $env4
        Assert-Match 'already has a merged PR' $r.Out "merged-PR branch denied: $c"
    }
    $r = Invoke-Script $mp (Bash 'gh pr list') $env4
    Assert-Equal '' $r.Out 'gh pr list unaffected'
}

$s = Get-TestSummary
Write-Host ("Hooks: {0} passed, {1} failed" -f $s.Pass, $s.Fail)
if ($s.Fail -gt 0) { exit 1 }
