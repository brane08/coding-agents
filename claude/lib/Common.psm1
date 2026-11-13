#Requires -Version 5.1
# Shared helpers for the PowerShell ports of the claude/ bash scripts.
# Windows PowerShell 5.1 safe: no ?: ?? ?. && ||, UTF-8 without BOM everywhere.

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-Prop {
    param($Obj, [string[]]$Path)
    foreach ($p in $Path) {
        if ($null -eq $Obj) { return $null }
        $m = $Obj.PSObject.Properties[$p]
        if ($null -eq $m) { return $null }
        $Obj = $m.Value
    }
    return $Obj
}

function Read-HookInput {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $script:Utf8NoBom)
    $text = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try { return ($text | ConvertFrom-Json) } catch { return $null }
}

function Write-Stdout {
    param([string]$Text)
    $bytes = $script:Utf8NoBom.GetBytes($Text)
    $out = [Console]::OpenStandardOutput()
    $out.Write($bytes, 0, $bytes.Length)
    $out.Flush()
}

function ConvertTo-JsonString {
    param([string]$Text)
    return (ConvertTo-Json -InputObject $Text -Compress)
}

function Write-Decision {
    param(
        [Parameter(Mandatory)][ValidateSet('deny', 'ask', 'allow')][string]$Decision,
        [Parameter(Mandatory)][string]$Reason
    )
    $r = ConvertTo-JsonString $Reason
    Write-Stdout ('{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"' + $Decision + '","permissionDecisionReason":' + $r + '}}')
}

function Write-Context {
    param([Parameter(Mandatory)][string]$Message)
    $m = ConvertTo-JsonString $Message
    Write-Stdout ('{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":' + $m + '}}')
}

function Test-WindowsHost {
    return ([System.IO.Path]::DirectorySeparatorChar -eq '\')
}

function Get-UserHome {
    if ($env:HOME) { return $env:HOME }
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    return [Environment]::GetFolderPath('UserProfile')
}

function ConvertTo-PosixPath {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return '' }
    $p = $Path -replace '\\', '/'
    if ($p -eq '~' -or $p.StartsWith('~/')) {
        $h = (Get-UserHome) -replace '\\', '/'
        $p = $h.TrimEnd('/') + $p.Substring(1)
    }
    if ($p -match '^[A-Za-z]:') { $p = $p.Substring(0, 1).ToLowerInvariant() + $p.Substring(1) }
    if ($p.Length -gt 1) { $p = $p.TrimEnd('/') }
    if ($p -eq '') { $p = '/' }
    return $p
}

function Get-ConfigDir {
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    return (Join-Path (Get-UserHome) '.claude')
}

function Get-StateDir {
    return (Join-Path (Get-ConfigDir) 'state')
}

function Get-SafeSid {
    param($SessionId)
    $s = [string]$SessionId
    if ([string]::IsNullOrEmpty($s)) { $s = 'x' }
    return ($s -replace '[^A-Za-z0-9-]', '_')
}

function Get-EpochSeconds {
    return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

function Add-Utf8Line {
    param([string]$File, [string]$Line)
    try {
        $dir = Split-Path -Parent $File
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::AppendAllText($File, $Line + "`n", $script:Utf8NoBom)
    } catch { }
}

function Write-Utf8File {
    param([string]$File, [string]$Text)
    [System.IO.File]::WriteAllText($File, $Text, $script:Utf8NoBom)
}

function Add-Nudge {
    param([string]$Sid, [string]$Category)
    $leaf = Split-Path -Leaf (Get-Location).Path
    Add-Utf8Line (Join-Path (Get-StateDir) 'delegation-nudges.tsv') ("{0}`t{1}`t{2}`t{3}" -f (Get-EpochSeconds), $Sid, $Category, $leaf)
}

function ConvertTo-ProcessArg {
    param([string]$Arg)
    if ($Arg -ne '' -and $Arg -notmatch '[\s"]') { return $Arg }
    $s = [regex]::Replace($Arg, '(\\*)"', '$1$1\"')
    $s = [regex]::Replace($s, '(\\+)$', '$1$1')
    return '"' + $s + '"'
}

# Windows PowerShell 5.1 and PowerShell < 7.3 do not escape embedded double quotes when
# passing arguments to native programs, so one argument can split into several (psql -c).
# Returns the arguments pre-escaped for those hosts and unchanged on 7.3+.
function Format-NativeArgs {
    param([string[]]$Arguments = @(), [switch]$Legacy)
    if (-not $PSBoundParameters.ContainsKey('Legacy')) {
        $Legacy = ($null -eq (Get-Variable -Name PSNativeCommandArgumentPassing -ErrorAction SilentlyContinue))
    }
    if (-not $Legacy) { return , @($Arguments) }
    $out = foreach ($a in $Arguments) {
        $s = [regex]::Replace($a, '(\\*)"', '$1$1\"')
        if ($a -match '\s' -and $s.EndsWith('\')) { $s = [regex]::Replace($s, '(\\+)$', '$1$1') }
        $s
    }
    return , @($out)
}

function Invoke-NativeCapture {
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @(), [int]$TimeoutMs = 8000)
    $quoted = foreach ($a in $Arguments) { ConvertTo-ProcessArg $a }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = ($quoted -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    try { $p = [System.Diagnostics.Process]::Start($psi) } catch { return $null }
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutMs)) {
        try { $p.Kill() } catch { }
        return $null
    }
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { return $null }
    return $out.Result
}

function Get-CurrentBranch {
    $o = Invoke-NativeCapture 'git' @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($null -eq $o) { return '' }
    return $o.Trim()
}

function Split-CommandSegments {
    param([string]$Command)
    return @($Command -split '[;&|\r\n]' | Where-Object { $_.Trim() -ne '' })
}

function Get-CommandWords {
    param([string]$Segment)
    $w = @($Segment.Trim() -split '\s+' | Where-Object { $_ -ne '' })
    $i = 0
    while ($i -lt $w.Count -and $w[$i] -match '^[A-Za-z_][A-Za-z0-9_]*=') { $i++ }
    if ($i -ge $w.Count) { return , @() }
    $first = $w[$i]
    $used = 1
    if ($first -match '^["'']' -and -not ($first.Length -gt 1 -and $first.EndsWith($first.Substring(0, 1)))) {
        $q = $first.Substring(0, 1)
        for ($j = $i + 1; $j -lt $w.Count; $j++) {
            $first += ' ' + $w[$j]
            $used++
            if ($w[$j].EndsWith($q)) { break }
        }
    }
    # `"git"`, `GIT`, `git.exe`, `"C:\Program Files\Git\cmd\git.exe"`, `/usr/bin/git` all name the same program
    $name = (($first.Trim('"', "'") -split '[\\/]')[-1] -replace '(?i)\.(exe|cmd|bat)$', '').ToLowerInvariant()
    $rest = @($name)
    if ($i + $used -lt $w.Count) { $rest += @($w[($i + $used)..($w.Count - 1)]) }
    return , $rest
}

function ConvertTo-JsonLiteral {
    param([string]$Text)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        switch ($ch) {
            '"' { [void]$sb.Append('\"') }
            '\' { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            "`b" { [void]$sb.Append('\b') }
            "`f" { [void]$sb.Append('\f') }
            default {
                if ([int][char]$ch -lt 32) { [void]$sb.Append(('\u{0:x4}' -f [int][char]$ch)) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# jq -S . compatible output: keys sorted ordinally, 2-space indent, "k": v.
function ConvertTo-SortedJson {
    param($Value, [int]$Level = 0)
    $pad = '  ' * ($Level + 1)
    $end = '  ' * $Level
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string]) { return (ConvertTo-JsonLiteral $Value) }
    if ($Value -is [System.Collections.IDictionary]) {
        $map = @{}
        foreach ($k in $Value.Keys) { $map[[string]$k] = $Value[$k] }
        $props = @($map.Keys)
    } elseif ($Value -is [System.Management.Automation.PSCustomObject]) {
        $map = @{}
        foreach ($p in $Value.PSObject.Properties) { $map[$p.Name] = $p.Value }
        $props = @($map.Keys)
    } elseif ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return '[]' }
        $parts = foreach ($i in $items) { $pad + (ConvertTo-SortedJson $i ($Level + 1)) }
        return "[`n" + ($parts -join ",`n") + "`n" + $end + ']'
    } else {
        return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $Value))
    }
    if ($props.Count -eq 0) { return '{}' }
    $sorted = [string[]]$props
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    $parts = foreach ($k in $sorted) {
        $pad + (ConvertTo-JsonLiteral $k) + ': ' + (ConvertTo-SortedJson -Value $map[$k] -Level ($Level + 1))
    }
    return "{`n" + ($parts -join ",`n") + "`n" + $end + '}'
}

# The runners are shared by the Claude, agents and Copilot trees. Which tree they run from is
# read off where this module is installed: ~/.agents/lib -> .agents, ~/.copilot/lib -> .copilot,
# anything else (~/.claude/lib, the repo) -> .claude.
function Get-ToolDirName {
    if ($env:AGENT_TOOL_DIR -match '^\.[A-Za-z0-9_-]+$') { return $env:AGENT_TOOL_DIR }
    foreach ($frame in @(Get-PSCallStack)) {
        $s = $frame.ScriptName
        if ([string]::IsNullOrEmpty($s) -or $s -eq $PSCommandPath) { continue }
        $p = Split-Path -Parent $s
        while ($p) {
            $leaf = Split-Path -Leaf $p
            if ($leaf -in @('.claude', '.agents', '.copilot')) { return $leaf }
            $parent = Split-Path -Parent $p
            if ($parent -eq $p) { break }
            $p = $parent
        }
    }
    return '.claude'
}

# ---- Registered module -------------------------------------------------------------------
# Common.psm1 is installed once, as the user module AgentCommon, so every tree's runners and
# hooks share one copy: `Import-Module AgentCommon`. Scripts fall back to the path import when
# the module is not registered (running from the repo).

function Get-UserModuleDirs {
    if ($env:AGENT_MODULE_DIR) { return , @($env:AGENT_MODULE_DIR) }
    if (Test-WindowsHost) {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        return , @((Join-Path $docs 'WindowsPowerShell/Modules'), (Join-Path $docs 'PowerShell/Modules'))
    }
    $data = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path (Get-UserHome) '.local/share' }
    return , @((Join-Path $data 'powershell/Modules'))
}

# Copies Common.psm1 + AgentCommon.psd1 into <user modules>/AgentCommon (both Windows PowerShell 5.1
# and PowerShell 7 locations on Windows). Returns the directories written.
function Install-AgentCommon {
    $manifest = Join-Path $PSScriptRoot 'AgentCommon.psd1'
    $root = Join-Path $PSScriptRoot 'Common.psm1'
    if (-not (Test-Path -LiteralPath $manifest)) { throw "AgentCommon.psd1 not found next to $root" }
    $out = @()
    foreach ($d in (Get-UserModuleDirs)) {
        $target = Join-Path $d 'AgentCommon'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Copy-Item -LiteralPath $root -Destination (Join-Path $target 'Common.psm1') -Force
        Copy-Item -LiteralPath $manifest -Destination (Join-Path $target 'AgentCommon.psd1') -Force
        $out += $target
    }
    return , $out
}

# True while any tree (~/.claude, ~/.agents, ~/.copilot) still has installed PowerShell runners or hooks.
function Test-AgentCommonInUse {
    foreach ($tool in '.claude', '.agents', '.copilot') {
        foreach ($sub in 'skills', 'hooks') {
            $p = Join-Path (Join-Path (Get-UserHome) $tool) $sub
            if ((Test-Path -LiteralPath $p -PathType Container) -and
                (Get-ChildItem -LiteralPath $p -Recurse -File -Filter '*.ps1' | Select-Object -First 1)) { return $true }
        }
    }
    return $false
}

# Removes the registered module unless another tree still needs it. Returns the directories removed.
function Remove-AgentCommonIfUnused {
    param([switch]$DryRun)
    if (Test-AgentCommonInUse) { return , @() }
    $out = @()
    foreach ($d in (Get-UserModuleDirs)) {
        $target = Join-Path $d 'AgentCommon'
        if (-not (Test-Path -LiteralPath $target -PathType Container)) { continue }
        $out += $target
        if ($DryRun) { Write-Host "  would remove: $target"; continue }
        Remove-Item -LiteralPath $target -Recurse -Force
    }
    return , $out
}

function Get-ProjectDir {
    foreach ($n in 'CLAUDE_PROJECT_DIR', 'AGENT_PROJECT_DIR') {
        $v = [Environment]::GetEnvironmentVariable($n)
        if ($v) { return $v }
    }
    return '.'
}

# <project>/<tool dir>/logs/<skill>.log (self-ignoring dir).
function Get-SkillLog {
    param([Parameter(Mandatory)][string]$Skill)
    $proj = Get-ProjectDir
    $logDir = Join-Path ((Resolve-Path -LiteralPath $proj).ProviderPath) ((Get-ToolDirName) + '/logs')
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $gi = Join-Path $logDir '.gitignore'
    if (-not (Test-Path -LiteralPath $gi)) { Write-Utf8File $gi "*`n" }
    return (Join-Path $logDir "$Skill.log")
}

# Runs a native command with stderr merged, echoing lines (unless -Quiet) and returning
# @{ Code; Lines }. Arguments are always passed as an array so PowerShell 5.1 cannot split
# tokens such as -Dfoo.bar=1.
function Invoke-Logged {
    param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments = @(), [switch]$Quiet)
    $lines = New-Object System.Collections.Generic.List[string]
    $code = 0
    try {
        $native = Format-NativeArgs $Arguments
        & $Exe @native 2>&1 | ForEach-Object {
            $s = "$_"
            $lines.Add($s)
            if (-not $Quiet) { [Console]::Out.WriteLine($s) }
        }
        $code = $LASTEXITCODE
    } catch {
        $lines.Add($_.Exception.Message)
        if (-not $Quiet) { [Console]::Out.WriteLine($_.Exception.Message) }
        $code = 127
    }
    if ($null -eq $code) { $code = 0 }
    return [pscustomobject]@{ Code = [int]$code; Lines = $lines }
}

# Physical path: every existing component that is a link (symlink/junction) is followed.
function Resolve-RealPath {
    param([Parameter(Mandatory)][string]$Path, [int]$Depth = 0)
    $full = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path (Get-Location).Path $Path }))
    $root = [System.IO.Path]::GetPathRoot($full)
    $cur = $root
    $rest = $full.Substring($root.Length)
    foreach ($part in ($rest -split '[\\/]' | Where-Object { $_ -ne '' })) {
        $next = Join-Path $cur $part
        $item = Get-Item -LiteralPath $next -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and -not [string]::IsNullOrEmpty($item.LinkType) -and $Depth -lt 10) {
            $t = @($item.Target)[0]
            if (-not [string]::IsNullOrEmpty($t)) {
                if (-not [System.IO.Path]::IsPathRooted($t)) { $t = Join-Path $cur $t }
                $next = Resolve-RealPath $t ($Depth + 1)
            }
        }
        $cur = $next
    }
    return $cur
}

$script:WindowsPromptFiles = '^(CLAUDE\.md|agents/[^/]+\.md|skills/[^/]+/SKILL\.md)$'

# Prompt files are written once, with Unix commands. The Windows sync rewrites them so the
# installed copy names the .ps1 twins; the repo copy (and the prompt size) stays unchanged.
function Test-WindowsPromptFile {
    param([string]$RelPath)
    return ($RelPath -replace '\\', '/') -match $script:WindowsPromptFiles
}

function ConvertTo-WindowsPrompt {
    param([string]$Text)
    $ps = 'powershell -NoProfile -ExecutionPolicy Bypass -File'
    $t = [regex]::Replace($Text, '\bQUARKUS_PORT=(\d+) bash (\S+?)\.sh', ($ps + ' $2.ps1 $1'))
    $t = [regex]::Replace($t, '\bQUARKUS_PORT=(\d+) (\S+?)\.sh\b', '$2.ps1 $1')
    # VAR=value bash x.sh is not PowerShell: set it with $env: first (the Windows auto-approve regex allows that prefix).
    $t = [regex]::Replace($t, '\b([A-Z][A-Z0-9_]*)=(\S+) bash (?=\S*?\.sh\b)', ('$$env:${1}=''${2}''; ' + $ps + ' '))
    $t = $t.Replace('bash|zsh|ksh ', $ps + ' ')
    $t = [regex]::Replace($t, '\bbash (?=\S*?\.sh\b)', ($ps + ' '))
    # A bare installed runner path has no interpreter; .ps1 files do not run from the command line under the default policy.
    $t = [regex]::Replace($t, '(?<!-File )(?<![\w/.$~\\-])(~/\.\w+/skills/[\w-]+/[\w-]+)\.sh\b', ($ps + ' ${1}.sh'))
    $t = [regex]::Replace($t, '\.sh\b', '.ps1')
    $t = [regex]::Replace($t, '(?<=`)(AGENT_PROJECT_DIR|CLAUDE_PROJECT_DIR)=([^`]+)(?=`)', '$$env:${1}=''${2}''')
    $t = [regex]::Replace($t, '\bset (AGENT_PROJECT_DIR|CLAUDE_PROJECT_DIR)=(\S+)', 'set $$env:${1}=''${2}''')
    $t = [regex]::Replace($t, '`\$(?!HOME`)([A-Z][A-Z0-9_]*)`', '`$$env:${1}`')
    $t = $t.Replace('(any of bash, zsh, ksh works). Always write the path with `~`.', '(Windows PowerShell 5.1+). Always write the path with `$HOME`.')
    $t = $t.Replace('always `~`, never `$HOME` or an absolute path (auto-approve only matches `~`)', 'always `$HOME`, never `~` or an absolute path (auto-approve matches `$HOME` and `$env:USERPROFILE`)')
    $shellNote = 'Shell: Windows PowerShell 5.1+, no bash-only syntax. Equivalents: grep = Select-String, find = Get-ChildItem -Recurse, head/tail = Select-Object -First/-Last, jq = ConvertFrom-Json.'
    $t = $t.Replace('Shell: zsh, macOS or Ubuntu/Debian VM — no bash-only syntax unless asked.', $shellNote)
    $t = $t.Replace('Shell: zsh on macOS or Ubuntu/Debian; no bash-only syntax unless asked.', $shellNote)
    $t = [regex]::Replace($t, '(?m)^(compatibility: Requires )(?:bash|zsh|`zsh`)( \(the script re-execs itself into zsh\))?', '${1}PowerShell 5.1+')
    $t = $t.Replace('Requires PowerShell 5.1+ and standard coreutils', 'Requires PowerShell 5.1+').Replace(', lsof,', ',')
    $t = $t.Replace('Requires `zsh` and', 'Requires PowerShell 5.1+ and')
    $t = [regex]::Replace($t, 'via `PIPESTATUS\[0\]`', 'by capturing the exit code itself')
    $t = $t.Replace('or use `jq`', 'or use `ConvertFrom-Json`').Replace('`unzip -l <jar>`', '`jar tf <jar>`')
    # $HOME is set in Windows PowerShell 5.1, 7.x and Git Bash; a bare ~ is not expanded in a native -File argument on 5.1.
    $t = $t.Replace($ps + ' ~/', $ps + ' $HOME/')
    return $t
}

function Copy-WindowsMarkdown {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Write-Utf8File $Destination (ConvertTo-WindowsPrompt ([System.IO.File]::ReadAllText($Source)))
}

# Every file Install-SkillTree writes for <TreeDir> (agents/ or copilot/): Rel is the path under
# <Dest>, Source the repo file, Rewrite true for markdown. Shared by install and uninstall so the
# two cannot drift.
function Get-SkillTreeFiles {
    param([Parameter(Mandatory)][string]$TreeDir)
    $claudeDir = Join-Path (Split-Path -Parent $TreeDir) 'claude'
    $root = (Resolve-Path -LiteralPath $TreeDir).ProviderPath.TrimEnd('\', '/')
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($f in @(Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
                $_.Extension -ne '.sh' -and $_.Name -ne 'INSTALL.md' -and $_.Name -notlike '*.snippet.json' -and
                -not ($_.DirectoryName -eq $root -and $_.Name -in @('install.ps1', 'uninstall.ps1', 'check-base.ps1')) })) {
        $rel = ($f.FullName.Substring($root.Length).TrimStart('\', '/')) -replace '\\', '/'
        $out.Add([pscustomobject]@{ Rel = $rel; Source = $f.FullName; Rewrite = ($f.Extension -eq '.md') })
    }
    foreach ($skill in @(Get-ChildItem -LiteralPath (Join-Path $TreeDir 'skills') -Directory)) {
        $runners = Join-Path $claudeDir ('skills/' + $skill.Name)
        if (Test-Path -LiteralPath $runners) {
            foreach ($r in @(Get-ChildItem -LiteralPath $runners -File -Filter '*.ps1')) {
                $out.Add([pscustomobject]@{ Rel = ('skills/' + $skill.Name + '/' + $r.Name); Source = $r.FullName; Rewrite = $false })
            }
        }
    }
    return , $out.ToArray()
}

# Installs <TreeDir>/skills (agents/ or copilot/) into <Dest>/skills: markdown rewritten to the .ps1
# commands, runners taken from claude/skills (single source). The shared module is registered
# separately (Install-AgentCommon). Returns the number of files written.
function Install-SkillTree {
    param([Parameter(Mandatory)][string]$TreeDir, [Parameter(Mandatory)][string]$Dest)
    $n = 0
    foreach ($e in (Get-SkillTreeFiles -TreeDir $TreeDir)) {
        $target = Join-Path $Dest $e.Rel
        if ($e.Rewrite) { Copy-WindowsMarkdown $e.Source $target }
        else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $e.Source -Destination $target -Force
        }
        $n++
    }
    return $n
}

# Removes the empty directories in $Dirs (deepest first) and then $Stop itself if it ends up empty.
function Remove-EmptyDirs {
    param([string[]]$Dirs, [string]$Stop)
    foreach ($d in ($Dirs | Sort-Object -Property Length -Descending)) {
        if ((Test-Path -LiteralPath $d -PathType Container) -and -not (Get-ChildItem -LiteralPath $d -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $d -Force
        }
    }
    if ($Stop -and (Test-Path -LiteralPath $Stop -PathType Container) -and -not (Get-ChildItem -LiteralPath $Stop -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $Stop -Force
    }
}

# Reverses Install-SkillTree: deletes exactly the files it writes into <Dest>, then prunes the
# directories that become empty. Files the user added under <Dest> are left alone.
# Returns the number of files removed (or that would be, with -DryRun).
function Uninstall-SkillTree {
    param([Parameter(Mandatory)][string]$TreeDir, [Parameter(Mandatory)][string]$Dest, [switch]$DryRun)
    $n = 0
    $dirs = New-Object System.Collections.Generic.HashSet[string]
    foreach ($e in (Get-SkillTreeFiles -TreeDir $TreeDir)) {
        $target = Join-Path $Dest $e.Rel
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
        $n++
        if ($DryRun) { Write-Host "  would remove: $target"; continue }
        Remove-Item -LiteralPath $target -Force
        $p = Split-Path -Parent $target
        while ($p -and $p.Length -gt $Dest.Length) { [void]$dirs.Add($p); $p = Split-Path -Parent $p }
    }
    if (-not $DryRun) { Remove-EmptyDirs -Dirs @($dirs) -Stop $Dest }
    return $n
}

function Get-EpochMinute {
    return ([long][math]::Floor((Get-EpochSeconds) / 60)) * 60
}

function Read-Manifest {
    param([Parameter(Mandatory)][string]$File)
    $out = @()
    foreach ($line in [System.IO.File]::ReadAllLines($File)) {
        $l = $line.TrimEnd("`r").Trim()
        if ($l -eq '' -or $l.StartsWith('#')) { continue }
        $out += $l
    }
    return , $out
}

Export-ModuleMember -Function Get-Prop, Read-HookInput, Write-Stdout, ConvertTo-JsonString, Write-Decision, Write-Context, Test-WindowsHost, Get-UserHome, ConvertTo-PosixPath, Get-ConfigDir, Get-StateDir, Get-SafeSid, Get-EpochSeconds, Add-Utf8Line, Write-Utf8File, Add-Nudge, Read-Manifest, Invoke-NativeCapture, Get-CurrentBranch, Split-CommandSegments, Get-CommandWords, ConvertTo-JsonLiteral, ConvertTo-SortedJson, Get-EpochMinute, Get-SkillLog, Invoke-Logged, Resolve-RealPath, Format-NativeArgs, ConvertTo-ProcessArg, Test-WindowsPromptFile, ConvertTo-WindowsPrompt, Get-ToolDirName, Get-ProjectDir, Copy-WindowsMarkdown, Install-SkillTree, Get-SkillTreeFiles, Uninstall-SkillTree, Remove-EmptyDirs, Get-UserModuleDirs, Install-AgentCommon, Test-AgentCommonInUse, Remove-AgentCommonIfUnused
