#Requires -Version 5.1
# PreToolUse guard for Bash: refuse `git push` / `gh pr create` from a branch whose PR is
# already merged (stale branch). Cut a new branch from origin/<default> instead.
#
# Uses `gh pr list --head <branch> --state all` (API call, not the cached `gh pr view`).
# Allows when: detached HEAD, protected/default branch, an OPEN PR exists, no PR found,
# or gh/network is unavailable (fail open).
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/Common.psm1') -Force

$in = Read-HookInput
if ($null -eq $in) { exit 0 }
$cmd = [string](Get-Prop $in 'tool_input', 'command')
if ($cmd -eq '') { exit 0 }

$protectedStr = if ($env:CLAUDE_PROTECTED_BRANCHES) { $env:CLAUDE_PROTECTED_BRANCHES } else { 'main master' }
$protected = @($protectedStr -split '\s+' | Where-Object { $_ -ne '' })

$hit = $false
$pushed = ''
foreach ($seg in (Split-CommandSegments $cmd)) {
    $w = Get-CommandWords $seg
    if ($w.Count -eq 0) { continue }
    if ($w[0] -ceq 'git' -and ($w -ccontains 'push')) {
        $hit = $true
        $seen = $false
        $n = 0
        foreach ($a in $w) {
            if (-not $seen) { if ($a -ceq 'push') { $seen = $true }; continue }
            if ($a.StartsWith('-')) { continue }
            $n++
            if ($n -eq 2) {
                $x = $a.TrimStart('+')
                $pushed = $x.Substring($x.LastIndexOf(':') + 1)
            }
        }
    } elseif ($w[0] -ceq 'gh') {
        $prIdx = [Array]::IndexOf($w, 'pr')
        if ($prIdx -ge 0 -and $prIdx + 1 -lt $w.Count -and $w[$prIdx + 1] -ceq 'create') { $hit = $true }
    }
}
if (-not $hit) { exit 0 }

if ($null -eq (Get-Command gh -ErrorAction SilentlyContinue)) { exit 0 }
$branch = Get-CurrentBranch
if ($branch -eq '') { exit 0 }
if ($pushed -ne '' -and $pushed -cne 'HEAD') { $branch = $pushed -replace '^refs/heads/', '' }
if ($branch -eq '' -or $branch -ceq 'HEAD') { exit 0 }
if ($protected -ccontains $branch) { exit 0 }

$states = Invoke-NativeCapture 'gh' @('pr', 'list', '--head', $branch, '--state', 'all', '--limit', '5', '--json', 'state', '-q', '.[].state')
if ($null -eq $states) { exit 0 }
$lines = @($states -split '\r?\n' | ForEach-Object { $_.Trim() })
if ($lines -ccontains 'OPEN') { exit 0 }
if (-not ($lines -ccontains 'MERGED')) { exit 0 }

Write-Decision deny ("Branch '$branch' already has a merged PR. Cut a new branch from origin/<default> (git fetch origin <default>; git switch -c <new> origin/<default>) and carry the new commits over instead of pushing or opening a PR from the stale branch.")
exit 0
