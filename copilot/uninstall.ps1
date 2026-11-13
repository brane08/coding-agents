#Requires -Version 5.1
# Rolls back copilot/install.ps1: removes the installed skills, agents, instructions, memory notes and
# lib/Common.psm1 from ~/.copilot, then prunes emptied directories. Files you added yourself are kept.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1 [dest] [-DryRun]
param([string]$Dest, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'claude/lib/Common.psm1') -Force
if (-not $Dest) { $Dest = Join-Path (Get-UserHome) '.copilot' }
if (-not (Test-Path -LiteralPath $Dest -PathType Container)) { Write-Host "Nothing to remove: $Dest does not exist."; exit 0 }
$n = Uninstall-SkillTree -TreeDir $PSScriptRoot -Dest $Dest -DryRun:$DryRun
if ($DryRun) { Write-Host "Dry run: $n file(s) would be removed from $Dest" } else { Write-Host "Removed $n file(s) from $Dest" }
foreach ($m in (Remove-AgentCommonIfUnused -DryRun:$DryRun)) { if (-not $DryRun) { Write-Host "Unregistered module AgentCommon: $m" } }
Write-Host 'VS Code: remove the entries you merged from copilot/vscode-settings.windows.snippet.json by hand.'
