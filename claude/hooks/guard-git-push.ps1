#Requires -Version 5.1
# PreToolUse guard: block force-pushing or deleting a protected branch.
#
# Resolves the actual target ref instead of matching on spelling, so it catches
# `git push origin main --force`, bare `git push --force` on main, `HEAD:main`, `+main`.
# Also denies any push whose target is a protected branch or the default branch (including a
# plain `git push`/`git push origin` while standing on one) and `git branch -d/-D` of a
# protected branch or the current branch. A plain push from a feature branch passes.
#
# Protected branches: $CLAUDE_PROTECTED_BRANCHES (space separated), default "main master",
# plus origin's default branch (refs/remotes/origin/HEAD) when known.
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/Common.psm1') -Force

$in = Read-HookInput
if ($null -eq $in) { exit 0 }
$cmd = [string](Get-Prop $in 'tool_input', 'command')
if ($cmd -eq '') { exit 0 }

$protectedStr = if ($env:CLAUDE_PROTECTED_BRANCHES) { $env:CLAUDE_PROTECTED_BRANCHES } else { 'main master' }
$protected = @($protectedStr -split '\s+' | Where-Object { $_ -ne '' })
$defaultBranch = ''
$o = Invoke-NativeCapture 'git' @('symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD')
if ($null -ne $o) { $defaultBranch = ($o.Trim() -replace '^origin/', '') }
if ($defaultBranch -ne '') { $protected += $defaultBranch }
$protectedAll = ($protected -join ' ')

# First non-flag word after `git` (skips -C <dir>, -c <k=v> and other global flags).
function Get-GitSubcommand {
    param([string[]]$Words)
    $i = 1
    while ($i -lt $Words.Count) {
        $a = $Words[$i]
        if ($a -ceq '-C' -or $a -ceq '-c') { $i += 2; continue }
        if ($a.StartsWith('-')) { $i++; continue }
        return $a
    }
    return ''
}

foreach ($seg in (Split-CommandSegments $cmd)) {
    $w = Get-CommandWords $seg
    if ($w.Count -eq 0 -or $w[0] -cne 'git') { continue }

    if ((Get-GitSubcommand $w) -ceq 'branch') {
        $branchIdx = [Array]::IndexOf($w, 'branch')
        $del = $false
        $names = @()
        for ($i = $branchIdx + 1; $i -lt $w.Count; $i++) {
            $a = $w[$i]
            if ($a -ceq '--delete') { $del = $true }
            elseif ($a.StartsWith('--')) { }
            elseif ($a -cmatch '^-[^-]') { if ($a -cmatch '[dD]') { $del = $true } }
            else { $names += $a }
        }
        if ($del) {
            $cur = Get-CurrentBranch
            foreach ($t in $names) {
                if (($protected -ccontains $t) -or ($cur -ne '' -and $t -ceq $cur)) {
                    Write-Decision deny ("Refusing to delete the branch '$t' (protected or currently checked out). Protected: $protectedAll.")
                    exit 0
                }
            }
        }
        continue
    }

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
            Write-Decision deny ("git push --mirror can rewrite protected branches ($protectedAll). Push an explicit refspec instead.")
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
            $what = 'push to'
            if ($force) { $what = 'force-push' }
            if ($delete) { $what = 'delete' }
            Write-Decision deny ("Refusing to $what the protected/default branch '$t'. Protected: $protectedAll.")
            exit 0
        }
    }
}
exit 0
