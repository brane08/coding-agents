#Requires -Version 5.1
# Guarded rm/mv/cp -- hard-confined to the current working directory tree.
# Refuses any source/destination that resolves (links included) outside the working dir,
# refuses the working dir root itself, refuses .git.
#
# Usage:
#   guarded-fs.ps1 rm <path>...
#   guarded-fs.ps1 mv <src> <dst>
#   guarded-fs.ps1 cp [-r] <src>... <dst>
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/Common.psm1') -Force

function Stop-Blocked {
    param([string]$Message)
    [Console]::Error.WriteLine("guarded-fs: blocked -- $Message")
    exit 1
}

$cmp = if (Test-WindowsHost) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
$root = ConvertTo-PosixPath (Resolve-RealPath (Get-Location).Path)

# follow=$false: the final component is judged by its own location; $true: by its target
# (destinations: writing through a link lands at the target).
function Resolve-Guarded {
    param([string]$Path, [bool]$Follow = $false)
    if ($Follow) {
        $p = Resolve-RealPath $Path
        $parent = Split-Path -Parent $p
        if ((Test-Path -LiteralPath $p) -or (Test-Path -LiteralPath $parent -PathType Container)) { return (ConvertTo-PosixPath $p) }
        return '__NOPARENT__'
    }
    $full = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path (Get-Location).Path $Path }))
    $parent = Split-Path -Parent $full
    if ([string]::IsNullOrEmpty($parent)) { return (ConvertTo-PosixPath $full) }
    if (Test-Path -LiteralPath $parent -PathType Container) {
        return (ConvertTo-PosixPath (Join-Path (Resolve-RealPath $parent) (Split-Path -Leaf $full)))
    }
    return '__NOPARENT__'
}

function Test-Inside {
    param([string]$Resolved, [string]$Label)
    if ($Resolved -eq '__NOPARENT__') { Stop-Blocked "parent directory of '$Label' does not exist" }
    $isRoot = $Resolved.Equals($root, $cmp)
    if (-not ($isRoot -or $Resolved.StartsWith($root.TrimEnd('/') + '/', $cmp))) {
        Stop-Blocked "'$Label' resolves to '$Resolved', outside working dir '$root'"
    }
    if ($isRoot) { Stop-Blocked 'refusing to operate on the working dir root itself' }
    if ($Resolved -match '(^|/)\.git(/|$)') { Stop-Blocked "refusing to touch .git ('$Resolved')" }
    if ($Resolved -match '(?i)(^|/)git~\d+(/|$)') { Stop-Blocked "refusing to touch what may be the 8.3 short name of .git ('$Resolved')" }
}

# rm -rf semantics: a link (symlink/junction) is unlinked, never descended into. Windows
# PowerShell 5.1 Remove-Item -Recurse follows junctions and deletes the target's contents.
function Remove-Safe {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return }
    $isLink = (-not [string]::IsNullOrEmpty($item.LinkType)) -and ($item.LinkType -ne 'HardLink')
    if ($item.PSIsContainer) {
        if (-not $isLink) {
            foreach ($child in @(Get-ChildItem -LiteralPath $item.FullName -Force)) { Remove-Safe $child.FullName }
        }
        [System.IO.Directory]::Delete($item.FullName)
    } else {
        [System.IO.File]::Delete($item.FullName)
    }
}

$cmd = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
$rest = if ($args.Count -gt 1) { @($args[1..($args.Count - 1)] | ForEach-Object { [string]$_ }) } else { @() }

switch ($cmd) {
    'rm' {
        if ($rest.Count -lt 1) { [Console]::Error.WriteLine('usage: guarded-fs.ps1 rm <path>...'); exit 1 }
        foreach ($p in $rest) { Test-Inside (Resolve-Guarded $p) $p }
        foreach ($p in $rest) {
            Remove-Safe $p
        }
        exit 0
    }
    'mv' {
        if ($rest.Count -ne 2) { [Console]::Error.WriteLine('usage: guarded-fs.ps1 mv <src> <dst>'); exit 1 }
        Test-Inside (Resolve-Guarded $rest[0]) $rest[0]
        Test-Inside (Resolve-Guarded $rest[1] $true) $rest[1]
        if (Test-Path -LiteralPath $rest[1] -PathType Container) {
            $t = Join-Path $rest[1] (Split-Path -Leaf $rest[0])
            Test-Inside (Resolve-Guarded $t $true) $t
        }
        Move-Item -LiteralPath $rest[0] -Destination $rest[1] -Force
        exit 0
    }
    'cp' {
        $recursive = $false
        $paths = @()
        foreach ($a in $rest) {
            if ($a -cmatch '^-[rRpPfinavL]' -or $a -ceq '--recursive') {
                if ($a -ceq '--recursive' -or $a -cmatch '^-[^-]*[rR]') { $recursive = $true }
            } elseif ($a.StartsWith('-')) {
                Stop-Blocked "unsupported cp flag '$a'"
            } else { $paths += $a }
        }
        if ($paths.Count -lt 2) { [Console]::Error.WriteLine('usage: guarded-fs.ps1 cp [-r] <src>... <dst>'); exit 1 }
        $dst = $paths[$paths.Count - 1]
        $srcs = @($paths[0..($paths.Count - 2)])
        foreach ($p in $srcs) {
            Test-Inside (Resolve-Guarded $p) $p
            if (Test-Path -LiteralPath $dst -PathType Container) {
                $t = Join-Path $dst (Split-Path -Leaf $p)
                Test-Inside (Resolve-Guarded $t $true) $t
            }
        }
        Test-Inside (Resolve-Guarded $dst $true) $dst
        foreach ($p in $srcs) {
            if ((Test-Path -LiteralPath $p -PathType Container) -and -not $recursive) {
                [Console]::Error.WriteLine("cp: -r not specified; omitting directory '$p'")
                exit 1
            }
            if ($recursive) { Copy-Item -LiteralPath $p -Destination $dst -Recurse -Force }
            else { Copy-Item -LiteralPath $p -Destination $dst -Force }
        }
        exit 0
    }
    default {
        [Console]::Error.WriteLine('usage: guarded-fs.ps1 <rm|mv|cp> ...')
        exit 1
    }
}
