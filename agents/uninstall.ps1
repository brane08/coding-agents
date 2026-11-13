#Requires -Version 5.1
# Rolls back agents/install.ps1: removes the installed skills, agent definitions, AGENTS.md and
# lib/Common.psm1 from ~/.agents, then prunes emptied directories. Files you added yourself are kept.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1 [dest] [-DryRun]
param([string]$Dest, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'claude/lib/Common.psm1') -Force
if (-not $Dest) { $Dest = Join-Path (Get-UserHome) '.agents' }
if (-not (Test-Path -LiteralPath $Dest -PathType Container)) { Write-Host "Nothing to remove: $Dest does not exist."; exit 0 }
$n = Uninstall-SkillTree -TreeDir $PSScriptRoot -Dest $Dest -DryRun:$DryRun
if ($DryRun) { Write-Host "Dry run: $n file(s) would be removed from $Dest" } else { Write-Host "Removed $n file(s) from $Dest" }
foreach ($m in (Remove-AgentCommonIfUnused -DryRun:$DryRun)) { if (-not $DryRun) { Write-Host "Unregistered module AgentCommon: $m" } }
