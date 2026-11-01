#Requires -Version 5.1
# PreToolUse guard for file-writing tools.
#
#   inside project          -> pass through (normal permission rules apply)
#   agent scratchpad only   -> pass through (claude-<uid>/ dirs under a tmp root)
#   ~/.claude (config)      -> pass through (normal permission rules apply)
#   anywhere else           -> deny
#
# Every existing path component that is a symlink/junction is followed, so a link inside
# the project that points outside it is judged by its target. `..` is normalised lexically.
# A path that cannot be normalised (illegal characters, too long for 5.1) is denied; an
# unexpected failure asks. Limitation: only covers Claude Code's file tools.
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/Common.psm1') -Force

$in = Read-HookInput
if ($null -eq $in) { exit 0 }
$f = Get-Prop $in 'tool_input', 'file_path'
if ([string]::IsNullOrEmpty([string]$f)) { $f = Get-Prop $in 'tool_input', 'notebook_path' }
if ([string]::IsNullOrEmpty([string]$f)) { exit 0 }

$win = Test-WindowsHost
$cmp = if ($win) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }

function Resolve-Abs {
    param([string]$Path)
    $p = [string]$Path
    if ($p -eq '~' -or $p.StartsWith('~/') -or $p.StartsWith('~\')) { $p = (Get-UserHome) + $p.Substring(1) }
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path (Get-Location).Path $p }
    $p = [System.IO.Path]::GetFullPath($p)
    return (ConvertTo-PosixPath (Resolve-RealPath $p))
}

function Test-Under {
    param([string]$Path, [string]$Root)
    if ($Path.Equals($Root, $cmp)) { return $true }
    $r = if ($Root.EndsWith('/')) { $Root } else { $Root + '/' }
    return $Path.StartsWith($r, $cmp)
}

try {
    try {
        $abs = Resolve-Abs ([string]$f)
    } catch {
        Write-Decision deny ("Writes outside the project are not allowed: cannot normalise path '" + [string]$f + "'")
        exit 0
    }

    $projRaw = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
    $proj = Resolve-Abs $projRaw
    $cfg = Resolve-Abs (Get-ConfigDir)

    $roots = @($env:CLAUDE_CODE_TMPDIR, $env:TMPDIR, $env:TEMP, $env:TMP, [System.IO.Path]::GetTempPath())
    if (-not $win) { $roots += '/tmp' }
    foreach ($root in $roots) {
        if ([string]::IsNullOrEmpty($root)) { continue }
        $r = Resolve-Abs $root
        if ($abs.StartsWith($r.TrimEnd('/') + '/claude-', $cmp)) { exit 0 }
    }

    if ((Test-Under $abs $proj) -or (Test-Under $abs $cfg)) { exit 0 }

    Write-Decision deny ("Writes outside the project are not allowed: " + $abs)
    exit 0
} catch {
    Write-Decision ask ("guard-writes: cannot verify write path (" + $_.Exception.Message + ")")
    exit 0
}
