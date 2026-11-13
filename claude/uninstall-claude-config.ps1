#Requires -Version 5.1
<#
uninstall-claude-config.ps1
Rolls back sync-claude-config.ps1: deletes the files listed in claude/MANIFEST (skills, hooks, agents,
CLAUDE.md, memory, lib ...) plus settings.json and .profile from ~/.claude, then prunes emptied
directories. Local-only files, state/ and backups/ are never touched.

-Restore  afterwards copy back the newest ~/.claude/backups/<epoch-minute>/ (what the last sync replaced).
-DryRun   list what would happen, change nothing.

Usage: powershell -NoProfile -ExecutionPolicy Bypass -File uninstall-claude-config.ps1 [-Restore] [-DryRun]
#>
param([switch]$Restore, [switch]$DryRun)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/Common.psm1') -Force

$destDir = Join-Path (Get-UserHome) '.claude'
$repoDir = if ($env:REPO_DIR) { $env:REPO_DIR } else { Split-Path -Parent $PSScriptRoot }
$manifestFile = Join-Path (Join-Path $repoDir 'claude') 'MANIFEST'
if (-not (Test-Path -LiteralPath $manifestFile)) { [Console]::Error.WriteLine("Error: manifest not found: $manifestFile"); exit 1 }
if (-not (Test-Path -LiteralPath $destDir -PathType Container)) { Write-Host "Nothing to remove: $destDir does not exist."; exit 0 }

$targets = @(Read-Manifest $manifestFile) + @('settings.json', '.profile')
$removed = 0
$dirs = New-Object System.Collections.Generic.HashSet[string]
foreach ($rel in $targets) {
    $f = Join-Path $destDir $rel
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
    $removed++
    if ($DryRun) { Write-Host "  would remove: $f"; continue }
    Remove-Item -LiteralPath $f -Force
    $p = Split-Path -Parent $f
    while ($p -and $p.Length -gt $destDir.Length) { [void]$dirs.Add($p); $p = Split-Path -Parent $p }
}
if (-not $DryRun) { Remove-EmptyDirs -Dirs @($dirs) }
if ($DryRun) { Write-Host "Dry run: $removed file(s) would be removed from $destDir" } else { Write-Host "Removed $removed file(s) from $destDir" }

foreach ($m in (Remove-AgentCommonIfUnused -DryRun:$DryRun)) { if (-not $DryRun) { Write-Host "Unregistered module AgentCommon: $m" } }

if ($Restore) {
    $backupRoot = Join-Path $destDir 'backups'
    $latest = $null
    if (Test-Path -LiteralPath $backupRoot) {
        $latest = Get-ChildItem -LiteralPath $backupRoot -Directory | Where-Object { $_.Name -match '^\d+$' } |
            Sort-Object { [long]$_.Name } -Descending | Select-Object -First 1
    }
    if ($null -eq $latest) { Write-Host 'No backup found to restore.'; exit 0 }
    $base = $latest.FullName.TrimEnd('\', '/')
    $restored = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $base -File -Recurse)) {
        $rel = $f.FullName.Substring($base.Length).TrimStart('\', '/')
        $d = Join-Path $destDir $rel
        $restored++
        if ($DryRun) { Write-Host "  would restore: $d"; continue }
        New-Item -ItemType Directory -Path (Split-Path -Parent $d) -Force | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $d -Force
    }
    if ($DryRun) { Write-Host "Dry run: $restored file(s) would be restored from $($latest.Name)" } else { Write-Host "Restored $restored file(s) from backups/$($latest.Name)" }
}
