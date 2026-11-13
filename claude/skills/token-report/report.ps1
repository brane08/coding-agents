#Requires -Version 5.1
# Token usage per model from local Claude Code session transcripts (read-only). Windows twin of report.sh.
# Usage: report.ps1 [project-name-substring]
# Prints main-session and subagent usage separately. Counts are token counts, not cost.
Import-Module AgentCommon -Force -ErrorAction SilentlyContinue
if (-not (Get-Module AgentCommon)) { Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/Common.psm1') -Force }

$filter = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
$projects = Join-Path (Get-ConfigDir) 'projects'
if (-not (Test-Path -LiteralPath $projects -PathType Container)) {
    [Console]::Error.WriteLine("token-report: no transcripts dir at $projects")
    exit 1
}

function Get-Num {
    param($V)
    if ($null -eq $V) { return [long]0 }
    return [long]$V
}

function Write-UsageTable {
    param([string]$Title, [string[]]$Files)
    Write-Host "== $Title ($($Files.Count) files)"
    if ($Files.Count -eq 0) { Write-Host '(none)'; return }
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $groups = @{}
    foreach ($f in $Files) {
        foreach ($line in [System.IO.File]::ReadLines($f)) {
            if ($line.IndexOf('"usage"') -lt 0) { continue }
            try { $o = $line | ConvertFrom-Json } catch { continue }
            if ((Get-Prop $o @('type')) -ne 'assistant') { continue }
            $u = Get-Prop $o @('message', 'usage')
            if ($null -eq $u) { continue }
            $m = Get-Prop $o @('message', 'model')
            if ([string]::IsNullOrEmpty($m)) { $m = 'unknown' }
            if ((Get-Prop $o @('message', 'model')) -eq '<synthetic>') { continue }
            $id = Get-Prop $o @('message', 'id')
            if ([string]::IsNullOrEmpty($id)) { $id = Get-Prop $o @('uuid') }
            if ([string]::IsNullOrEmpty($id)) { $id = 'x' }
            if (-not $seen.Add($f + $id)) { continue }
            if (-not $groups.ContainsKey($m)) {
                $groups[$m] = [pscustomobject]@{ Model = $m; Files = (New-Object System.Collections.Generic.HashSet[string]); Msgs = 0L; In = 0L; Out = 0L; CR = 0L; CC = 0L }
            }
            $g = $groups[$m]
            [void]$g.Files.Add($f)
            $g.Msgs++
            $g.In += Get-Num (Get-Prop $u @('input_tokens'))
            $g.Out += Get-Num (Get-Prop $u @('output_tokens'))
            $g.CR += Get-Num (Get-Prop $u @('cache_read_input_tokens'))
            $g.CC += Get-Num (Get-Prop $u @('cache_creation_input_tokens'))
        }
    }
    $rows = @($groups.Values | Sort-Object -Property @{ Expression = { -$_.Out } }, @{ Expression = { $_.Model } })
    $tot = [pscustomobject]@{ Model = 'TOTAL'; Sessions = 0; Msgs = 0L; In = 0L; Out = 0L; CR = 0L; CC = 0L }
    $table = New-Object System.Collections.Generic.List[object]
    $table.Add(@('model', 'sessions', 'msgs', 'input', 'output', 'cache_read', 'cache_create', 'cache_read/msg'))
    foreach ($r in $rows) {
        $tot.Sessions += $r.Files.Count; $tot.Msgs += $r.Msgs; $tot.In += $r.In; $tot.Out += $r.Out; $tot.CR += $r.CR; $tot.CC += $r.CC
        $table.Add(@($r.Model, $r.Files.Count, $r.Msgs, $r.In, $r.Out, $r.CR, $r.CC, [long][math]::Floor($r.CR / $r.Msgs)))
    }
    $perMsg = 0L
    if ($tot.Msgs -gt 0) { $perMsg = [long][math]::Floor($tot.CR / $tot.Msgs) }
    $table.Add(@('TOTAL', $tot.Sessions, $tot.Msgs, $tot.In, $tot.Out, $tot.CR, $tot.CC, $perMsg))
    $widths = @(0) * 8
    foreach ($row in $table) { for ($i = 0; $i -lt 8; $i++) { $w = ([string]$row[$i]).Length; if ($w -gt $widths[$i]) { $widths[$i] = $w } } }
    foreach ($row in $table) {
        $cells = for ($i = 0; $i -lt 8; $i++) { ([string]$row[$i]).PadRight($widths[$i]) }
        Write-Host (($cells -join '  ').TrimEnd())
    }
}

$main = @()
$sub = @()
foreach ($d in @(Get-ChildItem -LiteralPath $projects -Directory -Filter "*$filter*")) {
    $main += @(Get-ChildItem -LiteralPath $d.FullName -File -Filter '*.jsonl' | ForEach-Object { $_.FullName })
    foreach ($s in @(Get-ChildItem -LiteralPath $d.FullName -Directory)) {
        $sd = Join-Path $s.FullName 'subagents'
        if (Test-Path -LiteralPath $sd -PathType Container) {
            $sub += @(Get-ChildItem -LiteralPath $sd -File -Filter '*.jsonl' | ForEach-Object { $_.FullName })
        }
    }
}

Write-UsageTable 'main sessions' $main
Write-Host ''
Write-UsageTable 'subagent transcripts' $sub
Write-Host ''
Write-Host 'Token counts only (no pricing). Messages are de-duplicated by message id.'
