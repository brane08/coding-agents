#Requires -Version 5.1
<#
save-claude-config.ps1
Copies ~/.claude/ config INTO the repo's claude/ (Windows twin of save-claude-config.sh).
Refreshes ONLY the paths listed in claude/MANIFEST; never deletes anything in claude/.
~/.claude/settings.json -> settings.<profile>.windows.json (repo path -> @@REPO_DIR@@,
keys sorted like `jq -S`).

Usage: powershell -NoProfile -ExecutionPolicy Bypass -File save-claude-config.ps1 [admin|sandbox]
  No argument: reuse the profile last synced here (~/.claude/.profile), else admin.
  Repo root is one level above this script; override with $env:REPO_DIR.
#>
param([string]$ProfileName)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/Common.psm1') -Force

$srcDir = Join-Path (Get-UserHome) '.claude'
if (-not $ProfileName) {
    $marker = Join-Path $srcDir '.profile'
    if (Test-Path -LiteralPath $marker) { $ProfileName = ([System.IO.File]::ReadAllText($marker)).Trim() }
    if (-not $ProfileName) { $ProfileName = 'admin' }
}
if ($ProfileName -notin @('admin', 'sandbox')) {
    [Console]::Error.WriteLine("Error: profile must be 'admin' or 'sandbox', got: $ProfileName")
    exit 1
}

$repoDir = if ($env:REPO_DIR) { $env:REPO_DIR } else { Split-Path -Parent $PSScriptRoot }
$destDir = Join-Path $repoDir 'claude'
$manifestFile = Join-Path $destDir 'MANIFEST'
if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) { [Console]::Error.WriteLine("Error: source dir not found: $srcDir"); exit 1 }
if (-not (Test-Path -LiteralPath $manifestFile)) { [Console]::Error.WriteLine("Error: manifest not found: $manifestFile"); exit 1 }
$settingsFile = Join-Path $srcDir 'settings.json'
if (-not (Test-Path -LiteralPath $settingsFile)) { [Console]::Error.WriteLine("Error: settings not found: $settingsFile"); exit 1 }

$manifest = Read-Manifest $manifestFile
Write-Host "Saving (per MANIFEST, profile: $ProfileName): $srcDir  ->  $destDir"

$count = 0
$skipped = 0
foreach ($rel in $manifest) {
    $s = Join-Path $srcDir $rel
    if (Test-WindowsPromptFile $rel) {
        Write-Host "  skip (rewritten for Windows on sync; edit it in the repo): $rel"
        $skipped++
    } elseif (Test-Path -LiteralPath $s -PathType Leaf) {
        $d = Join-Path $destDir $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $d) -Force | Out-Null
        Copy-Item -LiteralPath $s -Destination $d -Force
        $count++
    } else {
        Write-Host "  skip (in MANIFEST but not found locally): $rel"
        $skipped++
    }
}

$repoFwd = $repoDir -replace '\\', '/'
$text = [System.IO.File]::ReadAllText($settingsFile)
$homeFwd = ((Get-UserHome) -replace '\\', '/').TrimEnd('/')
$text = [regex]::Replace($text, [regex]::Escape($repoFwd), '@@REPO_DIR@@', 'IgnoreCase')
$text = [regex]::Replace($text, [regex]::Escape($homeFwd), '@@HOME@@', 'IgnoreCase')
$obj = $text | ConvertFrom-Json
# `model` stays as the template has it and `modelSettings` is never saved: /model writes
# both to ~/.claude/settings.json as per-machine state, not shared config.
$destSettings = Join-Path $destDir "settings.$ProfileName.windows.json"
if ($obj.PSObject.Properties['modelSettings']) { $obj.PSObject.Properties.Remove('modelSettings') }
if (Test-Path -LiteralPath $destSettings) {
    $prev = [System.IO.File]::ReadAllText($destSettings) | ConvertFrom-Json
    if ($prev.PSObject.Properties['model']) {
        if ($obj.PSObject.Properties['model']) { $obj.model = $prev.model }
        else { $obj | Add-Member -NotePropertyName model -NotePropertyValue $prev.model }
    }
}
Write-Utf8File $destSettings ((ConvertTo-SortedJson $obj) + "`n")
$count++
Write-Host "Saved $count file(s), $skipped listed-but-missing."

$skillDirs = @($manifest | Where-Object { $_ -like 'skills/*/*' } | ForEach-Object { ($_ -split '/')[1] } | Sort-Object -Unique)
$agentNames = @($manifest | Where-Object { $_ -match '^agents/.+\.md$' } | ForEach-Object { ($_ -replace '^agents/', '') -replace '\.md$', '' } | Sort-Object -Unique)
$localSkills = @()
if (Test-Path -LiteralPath (Join-Path $srcDir 'skills')) {
    $localSkills = @(Get-ChildItem -LiteralPath (Join-Path $srcDir 'skills') | ForEach-Object { $_.Name } | Where-Object { $skillDirs -cnotcontains $_ })
}
$localAgents = @()
if (Test-Path -LiteralPath (Join-Path $srcDir 'agents')) {
    $localAgents = @(Get-ChildItem -LiteralPath (Join-Path $srcDir 'agents') | ForEach-Object { $_.Name -replace '\.md$', '' } | Where-Object { $agentNames -cnotcontains $_ })
}
if ($localSkills.Count -gt 0) { Write-Host ("Local-only skills (not in MANIFEST, not saved): " + ($localSkills -join ' ')) }
if ($localAgents.Count -gt 0) { Write-Host ("Local-only agents (not in MANIFEST, not saved): " + ($localAgents -join ' ')) }
Write-Host 'Done.'
Write-Host "Review changes with: git status claude/ (in $repoDir)"
Write-Host 'New file to add to the shared config? Copy it in, add a line to MANIFEST, then: git add claude/...'
