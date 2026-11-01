#Requires -Version 5.1
# PreToolUse guard: block force-pushing or deleting a protected branch.
#
# Resolves the actual target ref instead of matching on spelling, so it catches
# `git push origin main --force`, bare `git push --force` on main, `HEAD:main`, `+main`.
# Feature-branch force-pushes pass straight through.
#
# Protected branches: $CLAUDE_PROTECTED_BRANCHES (space separated), default "main master".
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/Common.psm1') -Force

$in = Read-HookInput
if ($null -eq $in) { exit 0 }
$cmd = [string](Get-Prop $in 'tool_input', 'command')
if ($cmd -eq '') { exit 0 }

$protectedStr = if ($env:CLAUDE_PROTECTED_BRANCHES) { $env:CLAUDE_PROTECTED_BRANCHES } else { 'main master' }
$protected = @($protectedStr -split '\s+' | Where-Object { $_ -ne '' })

foreach ($seg in (Split-CommandSegments $cmd)) {
    $w = Get-CommandWords $seg
    if ($w.Count -eq 0 -or $w[0] -cne 'git') { continue }
    $pushIdx = [Array]::IndexOf($w, 'push')
    if ($pushIdx -lt 0) { continue }

    $force = $false
    $delete = $false
    $refspecs = @()
    for ($i = $pushIdx + 1; $i -lt $w.Count; $i++) {
        $a = $w[$i]
        if ($a -cmatch '^(--force|--force-with-lease|--force-with-lease=.*|--force-if-includes)$') { $force = $true }
        elseif ($a -ceq '--delete') { $delete = $true }
        elseif ($a -ceq '--mirror') {
            Write-Decision deny ("git push --mirror can rewrite protected branches ($protectedStr). Push an explicit refspec instead.")
            exit 0
        }
        elseif ($a -cmatch '^-[^-]') {
            if ($a.Contains('f')) { $force = $true }
            if ($a.Contains('d')) { $delete = $true }
        }
        elseif ($a.StartsWith('-')) { }
        else { $refspecs += $a }
    }

    foreach ($r in $refspecs) {
        if ($r.StartsWith('+')) { $force = $true }
        elseif ($r.StartsWith(':')) { $delete = $true }
    }
    if (-not ($force -or $delete)) { continue }

    $targets = @()
    for ($n = 1; $n -lt $refspecs.Count; $n++) {
        $r = $refspecs[$n].TrimStart('+')
        $dst = $r.Substring($r.LastIndexOf(':') + 1)
        if ($dst -ceq 'HEAD') { $dst = Get-CurrentBranch }
        $targets += $dst
    }
    if (@($targets | Where-Object { $_ -ne '' }).Count -eq 0) { $targets = @(Get-CurrentBranch) }

    foreach ($t in $targets) {
        $t = $t -replace '^refs/heads/', ''
        if ($protected -ccontains $t) {
            $what = if ($delete) { 'delete' } else { 'force-push' }
            Write-Decision deny ("Refusing to $what the protected branch '$t'. Protected: $protectedStr.")
            exit 0
        }
    }
}
exit 0
