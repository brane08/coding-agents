#Requires -Version 5.1
# Read-only sync check in one call: fetch, branch, status, ahead/behind, tree diff vs
# origin/<default>, last commits, PR states for the branch.
# Usage: sync-check.ps1 [default-branch]   (default: main)
$d = if ($args.Count -gt 0) { [string]$args[0] } else { 'main' }
if ($d -cnotmatch '^[A-Za-z0-9._/-]+$') {
    Write-Host "ERROR: invalid branch name: $d"
    exit 2
}

$fetchOut = @(& git fetch origin $d 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: git fetch origin $d FAILED; the comparisons below use stale refs"
    $fetchOut | Select-Object -Last 3 | ForEach-Object { Write-Host $_ }
}
& git rev-parse --verify -q "origin/$d" *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: origin/$d does not exist locally"; exit 1 }
$branch = ((& git branch --show-current 2>$null) -join '').Trim()

Write-Host ("== branch: " + $(if ($branch) { $branch } else { '(detached)' }))
Write-Host '== status (must be clean)'
$st = @(& git status --short)
if ($st.Count -gt 0) { $st | ForEach-Object { Write-Host $_ } } else { Write-Host 'clean' }
Write-Host "== HEAD...origin/$d (ahead<TAB>behind)"
& git rev-list --left-right --count "HEAD...origin/$d" | ForEach-Object { Write-Host $_ }
Write-Host "== tree diff HEAD vs origin/$d"
$df = @(& git diff --stat HEAD "origin/$d")
if ($df.Count -gt 0) { $df | ForEach-Object { Write-Host $_ } } else { Write-Host 'empty (identical tree: squash-merged or no changes)' }
Write-Host '== log'
& git log --oneline -3 | ForEach-Object { Write-Host $_ }
if ($branch -and (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "== PRs for $branch"
    & gh pr list --head $branch --state all --limit 5 --json number,state | ForEach-Object { Write-Host $_ }
}
exit 0
