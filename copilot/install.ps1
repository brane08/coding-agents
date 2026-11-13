#Requires -Version 5.1
# Windows install of the Copilot tree: copilot/ -> ~/.copilot (markdown rewritten to the .ps1 commands,
# runners taken from claude/skills). Usage: powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [dest]
param([string]$Dest)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'claude/lib/Common.psm1') -Force
if (-not $Dest) { $Dest = Join-Path (Get-UserHome) '.copilot' }
$n = Install-SkillTree -TreeDir $PSScriptRoot -Dest $Dest
Write-Host "Installed $n file(s) to $Dest"
foreach ($m in (Install-AgentCommon)) { Write-Host "Registered module AgentCommon -> $m" }
Write-Host 'VS Code: merge copilot/vscode-settings.windows.snippet.json into your settings.'
