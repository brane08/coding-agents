#Requires -Version 5.1
# Windows twin of check-base.sh. Compares the tool-free base agents (agents/agents/<n>.md) with the
# full Claude versions.
#   - base files must not mention a specific tool (claude, copilot) -> always an error (exit 1)
#   - claude/agents/<n>.md vs base: description and body differences -> reported, exit 0
#     (body = text after the frontmatter, up to the "## ... specifics" heading or end of file)
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File agents\check-base.ps1 [--strict]
param([switch]$Strict)
$ErrorActionPreference = 'Stop'
if ($args -contains '--strict') { $Strict = $true }

$root = Split-Path -Parent $PSScriptRoot
$baseDir = Join-Path $root 'agents/agents'
$claudeDir = Join-Path $root 'claude/agents'
$errors = 0
$drift = 0

function Write-Err { param([string]$Text) [Console]::Error.WriteLine($Text) }

function Get-Body {
    param([string]$File)
    $lines = [System.IO.File]::ReadAllLines($File)
    $seen = 0
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
        if ($seen -lt 2) { if ($l -ceq '---') { $seen++ }; continue }
        if ($l -cmatch '^## .* specifics$') { break }
        $out.Add($l)
    }
    while ($out.Count -gt 0 -and $out[$out.Count - 1] -eq '') { $out.RemoveAt($out.Count - 1) }
    return , $out.ToArray()
}

function Get-Desc {
    param([string]$File)
    foreach ($l in [System.IO.File]::ReadAllLines($File)) { if ($l -cmatch '^description:') { return $l } }
    return ''
}

foreach ($base in @(Get-ChildItem -LiteralPath $baseDir -Filter '*.md' -File)) {
    $name = $base.Name
    $hits = @(Select-String -LiteralPath $base.FullName -Pattern 'claude|copilot|omitClaudeMd')
    if ($hits.Count -gt 0) {
        foreach ($h in $hits) { Write-Err ("{0}:{1}" -f $h.LineNumber, $h.Line) }
        Write-Err "ERROR not tool-free: $($base.FullName)"
        $errors = 1
    }
    $tool = Join-Path $claudeDir $name
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { Write-Err "note: no claude version of $name"; continue }
    if ((Get-Desc $base.FullName) -cne (Get-Desc $tool)) { Write-Err "drift: description differs: $name"; $drift = 1 }
    $a = Get-Body $base.FullName
    $b = Get-Body $tool
    $d = @(Compare-Object -ReferenceObject $a -DifferenceObject $b -CaseSensitive)
    if ($d.Count -gt 0) {
        foreach ($x in $d) { Write-Err ($(if ($x.SideIndicator -eq '<=') { '-' } else { '+' }) + $x.InputObject) }
        Write-Err "drift: body differs: $name"
        $drift = 1
    }
}

foreach ($tool in @(Get-ChildItem -LiteralPath $claudeDir -Filter '*.md' -File)) {
    if (-not (Test-Path -LiteralPath (Join-Path $baseDir $tool.Name) -PathType Leaf)) { Write-Err "note: claude-only agent (no base): $($tool.Name)" }
}

if ($errors -eq 0 -and $drift -eq 0) { Write-Host 'base agents are tool-free and claude/agents matches them' }
if ($errors -eq 0 -and $drift -eq 1) { Write-Host 'base agents are tool-free; some claude/agents differ from the base (see above)' }
if ($errors -eq 1) { exit 1 }
if ($Strict -and $drift -eq 1) { exit 1 }
exit 0
