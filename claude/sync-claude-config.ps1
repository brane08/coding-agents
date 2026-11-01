#Requires -Version 5.1
<#
sync-claude-config.ps1
Copies Claude Code config from the repo's claude/ into ~/.claude/ (Windows twin of
sync-claude-config.sh). Copies ONLY the paths listed in claude/MANIFEST, always
overwriting, after backing up the files it replaces to ~/.claude/backups/<epoch-minute>/
(newest 5 kept; BACKUP_KEEP=<n> to change). Never deletes anything else in ~/.claude/.

settings.json is profile- and OS-specific: settings.<profile>.windows.json -> ~/.claude/settings.json.

Usage: powershell -NoProfile -ExecutionPolicy Bypass -File sync-claude-config.ps1 [admin|sandbox]
  No argument: reuse the profile last synced here (~/.claude/.profile), else admin.
  Repo root is one level above this script; override with $env:REPO_DIR.
#>
param([string]$ProfileName)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/Common.psm1') -Force

$destDir = Join-Path (Get-UserHome) '.claude'
$marker = Join-Path $destDir '.profile'
if (-not $ProfileName) {
    if (Test-Path -LiteralPath $marker) { $ProfileName = ([System.IO.File]::ReadAllText($marker)).Trim() }
    if (-not $ProfileName) { $ProfileName = 'admin' }
}
if ($ProfileName -notin @('admin', 'sandbox')) {
    [Console]::Error.WriteLine("Error: profile must be 'admin' or 'sandbox', got: $ProfileName")
    exit 1
}

$repoDir = if ($env:REPO_DIR) { $env:REPO_DIR } else { Split-Path -Parent $PSScriptRoot }
$srcDir = Join-Path $repoDir 'claude'
$manifestFile = Join-Path $srcDir 'MANIFEST'
if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) { [Console]::Error.WriteLine("Error: source dir not found: $srcDir"); exit 1 }
if (-not (Test-Path -LiteralPath $manifestFile)) { [Console]::Error.WriteLine("Error: manifest not found: $manifestFile"); exit 1 }
$settingsSrc = Join-Path $srcDir "settings.$ProfileName.windows.json"
if (-not (Test-Path -LiteralPath $settingsSrc)) { [Console]::Error.WriteLine("Error: settings profile not found: $settingsSrc"); exit 1 }

New-Item -ItemType Directory -Path $destDir -Force | Out-Null
$manifest = Read-Manifest $manifestFile
Write-Host "Syncing (per MANIFEST, profile: $ProfileName): $srcDir  ->  $destDir"

$keep = 5
if ($env:BACKUP_KEEP -match '^\d+$') { $keep = [int]$env:BACKUP_KEEP }
$backupRoot = Join-Path $destDir 'backups'
$backupDir = Join-Path $backupRoot ([string](Get-EpochMinute))
if (-not (Test-Path -LiteralPath $backupDir)) {
    $backed = 0
    $targets = @($manifest) + @('settings.json')
    foreach ($rel in $targets) {
        $f = Join-Path $destDir $rel
        if (Test-Path -LiteralPath $f -PathType Leaf) {
            $d = Join-Path $backupDir $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $d) -Force | Out-Null
            Copy-Item -LiteralPath $f -Destination $d -Force
            $backed++
        }
    }
    if ($backed -gt 0) { Write-Host "Backed up $backed file(s) -> $backupDir" }
    if (Test-Path -LiteralPath $backupRoot) {
        $old = @(Get-ChildItem -LiteralPath $backupRoot -Directory | Where-Object { $_.Name -match '^\d+$' } |
            Sort-Object { [long]$_.Name } -Descending | Select-Object -Skip $keep)
        foreach ($o in $old) { Remove-Item -LiteralPath $o.FullName -Recurse -Force }
    }
}

$count = 0
$missing = 0
foreach ($rel in $manifest) {
    $s = Join-Path $srcDir $rel
    if (Test-Path -LiteralPath $s -PathType Leaf) {
        $d = Join-Path $destDir $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $d) -Force | Out-Null
        if (Test-WindowsPromptFile $rel) {
            Write-Utf8File $d (ConvertTo-WindowsPrompt ([System.IO.File]::ReadAllText($s)))
        } else {
            Copy-Item -LiteralPath $s -Destination $d -Force
        }
        $count++
    } else {
        Write-Host "  skip (in MANIFEST but missing from repo): $rel"
        $missing++
    }
}

$repoFwd = $repoDir -replace '\\', '/'
$homeFwd = (Get-UserHome) -replace '\\', '/'
$settings = [System.IO.File]::ReadAllText($settingsSrc).Replace('@@REPO_DIR@@', $repoFwd).Replace('@@HOME@@', $homeFwd.TrimEnd('/'))
Write-Utf8File (Join-Path $destDir 'settings.json') $settings
Write-Utf8File $marker ($ProfileName + "`n")
$count++
Write-Host "Synced $count file(s), $missing listed-but-missing."

$skillDirs = @($manifest | Where-Object { $_ -like 'skills/*/*' } | ForEach-Object { ($_ -split '/')[1] } | Sort-Object -Unique)
$agentNames = @($manifest | Where-Object { $_ -match '^agents/.+\.md$' } | ForEach-Object { ($_ -replace '^agents/', '') -replace '\.md$', '' } | Sort-Object -Unique)
$localSkills = @()
if (Test-Path -LiteralPath (Join-Path $destDir 'skills')) {
    $localSkills = @(Get-ChildItem -LiteralPath (Join-Path $destDir 'skills') | ForEach-Object { $_.Name } | Where-Object { $skillDirs -cnotcontains $_ })
}
$localAgents = @()
if (Test-Path -LiteralPath (Join-Path $destDir 'agents')) {
    $localAgents = @(Get-ChildItem -LiteralPath (Join-Path $destDir 'agents') | ForEach-Object { $_.Name -replace '\.md$', '' } | Where-Object { $agentNames -cnotcontains $_ })
}
if ($localSkills.Count -gt 0) { Write-Host ("Local-only skills (not in MANIFEST, untouched): " + ($localSkills -join ' ')) }
if ($localAgents.Count -gt 0) { Write-Host ("Local-only agents (not in MANIFEST, untouched): " + ($localAgents -join ' ')) }
Write-Host 'Done.'
