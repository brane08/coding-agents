#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$claudeDir = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $claudeDir 'lib/Common.psm1') -Force

Write-Host 'Common'
Assert-Equal 'c:/Users/a b/x' (ConvertTo-PosixPath 'C:\Users\a b\x\') 'posix path: drive lowercased, slashes, trailing slash'
Assert-Equal 'select 1\" -c \"drop' ((Format-NativeArgs @('select 1" -c "drop') -Legacy)[0]) 'legacy native arg: embedded quotes escaped'
Assert-Equal 'a b\\' ((Format-NativeArgs @('a b\') -Legacy)[0]) 'legacy native arg: trailing backslash doubled when quoted'
Assert-Equal 'a\\\"b' ((Format-NativeArgs @('a\"b') -Legacy)[0]) 'legacy native arg: backslashes before quote doubled'
Assert-Equal 'x"y' ((Format-NativeArgs @('x"y') -Legacy:$false)[0]) 'modern host: args untouched'
$ps = 'powershell -NoProfile -ExecutionPolicy Bypass -File'
Assert-Equal "run $ps `$HOME/.claude/skills/mvn-test/test.ps1 mod" (ConvertTo-WindowsPrompt 'run bash ~/.claude/skills/mvn-test/test.sh mod') 'prompt: bash <path>.sh invocation rewritten'
Assert-Equal "$ps `$HOME/.claude/skills/<skill>/<script>.ps1 x" (ConvertTo-WindowsPrompt 'bash|zsh|ksh ~/.claude/skills/<skill>/<script>.sh x') 'prompt: bash|zsh|ksh template rewritten'
Assert-Equal "$ps `$HOME/.claude/skills/quarkus-dev/dev.ps1 8102" (ConvertTo-WindowsPrompt 'QUARKUS_PORT=8102 bash ~/.claude/skills/quarkus-dev/dev.sh') 'prompt: QUARKUS_PORT prefix becomes a port argument'
Assert-Equal 'use select.ps1 only; bash scripting stays' (ConvertTo-WindowsPrompt 'use select.sh only; bash scripting stays') 'prompt: bare filename mention rewritten, plain "bash" untouched'
Assert-True (Test-WindowsPromptFile 'skills/mvn-test/SKILL.md') 'prompt file: SKILL.md'
Assert-True (-not (Test-WindowsPromptFile 'memory/libs/x.md')) 'prompt file: memory excluded'
$leftover = @()
foreach ($f in @('CLAUDE.md') + @(Get-ChildItem (Join-Path $claudeDir 'agents') -Filter '*.md' | ForEach-Object { 'agents/' + $_.Name }) + @(Get-ChildItem (Join-Path $claudeDir 'skills') -Filter 'SKILL.md' -Recurse | ForEach-Object { $_.FullName.Substring($claudeDir.Length + 1) -replace '\\', '/' })) {
    $out = ConvertTo-WindowsPrompt ([System.IO.File]::ReadAllText((Join-Path $claudeDir $f)))
    foreach ($m in [regex]::Matches($out, '\bbash [~<$/]|\.sh\b|\b(zsh|ksh) [~<]')) { $leftover += "${f}: $($m.Value)" }
}
Assert-Equal '' ($leftover -join '; ') 'real prompt files: no bash script references left after the Windows rewrite'
$tmp = New-TempDir
$mf = Join-Path $tmp 'MANIFEST'
[System.IO.File]::WriteAllText($mf, "# c`r`n`r`nhooks/a.ps1`r`n  skills/x/y.ps1  `r`n")
$m = Read-Manifest $mf
Assert-Equal 'hooks/a.ps1|skills/x/y.ps1' ($m -join '|') 'manifest: CRLF, comments, blanks stripped'
$j = '{"b":[1,{"z":"a<b>\u0027","a":null}],"a":{},"c":[],"d":true,"e":"line\nbreak \"q\""}'
$expected = "{`n  `"a`": {},`n  `"b`": [`n    1,`n    {`n      `"a`": null,`n      `"z`": `"a<b>'`"`n    }`n  ],`n  `"c`": [],`n  `"d`": true,`n  `"e`": `"line\nbreak \`"q\`"`"`n}"
Assert-Equal $expected (ConvertTo-SortedJson ($j | ConvertFrom-Json)) 'sorted json matches jq -S layout'

$jq = Get-Command jq -ErrorAction SilentlyContinue
if ($jq) {
    foreach ($p in 'admin', 'sandbox') {
        $f = Join-Path $claudeDir "settings.$p.json"
        $want = (& jq -S . $f) -join "`n"
        $got = ConvertTo-SortedJson ([System.IO.File]::ReadAllText($f) | ConvertFrom-Json)
        Assert-Equal $want $got "sorted json == jq -S on settings.$p.json"
    }
}

Write-Host 'sync/save'
$home1 = Join-Path $tmp 'home'
$repo = Join-Path $tmp 'repo with space'
$rc = Join-Path $repo 'claude'
New-Item -ItemType Directory -Path (Join-Path $rc 'hooks'), (Join-Path $rc 'lib'), (Join-Path $home1 '.claude/hooks') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $rc 'MANIFEST'), "# t`nhooks/a.ps1`nhooks/missing.ps1`nCLAUDE.md`n")
[System.IO.File]::WriteAllText((Join-Path $rc 'CLAUDE.md'), 'run bash ~/.claude/skills/mvn-test/test.sh mod')
[System.IO.File]::WriteAllText((Join-Path $rc 'hooks/a.ps1'), 'new')
[System.IO.File]::WriteAllText((Join-Path $home1 '.claude/hooks/a.ps1'), 'old')
$fwd = $repo -replace '\\', '/'
[System.IO.File]::WriteAllText((Join-Path $rc 'settings.sandbox.windows.json'), '{"z":"@@REPO_DIR@@/claude/x","a":[1],"h":"@@HOME@@/.claude/hooks/a.ps1"}')
$env2 = @{ HOME = $home1; USERPROFILE = $home1; REPO_DIR = $repo }
$sync = Join-Path $claudeDir 'sync-claude-config.ps1'
$save = Join-Path $claudeDir 'save-claude-config.ps1'

$r = Invoke-Script $sync '' $env2 @('sandbox')
Assert-Equal 0 $r.Code 'sync exits 0'
Assert-Equal 'new' ([System.IO.File]::ReadAllText((Join-Path $home1 '.claude/hooks/a.ps1'))) 'sync overwrote file'
Assert-Match 'skip \(in MANIFEST but missing from repo\): hooks/missing.ps1' $r.Out 'sync reports missing'
$s = [System.IO.File]::ReadAllText((Join-Path $home1 '.claude/settings.json'))
Assert-True ($s.Contains("$fwd/claude/x")) 'settings placeholder substituted with forward slashes'
Assert-True ($s.Contains(($home1 -replace '\\', '/') + '/.claude/hooks/a.ps1')) '@@HOME@@ substituted with user home'
Assert-Equal 'sandbox' (([System.IO.File]::ReadAllText((Join-Path $home1 '.claude/.profile'))).Trim()) 'profile marker written'
$bk = @(Get-ChildItem (Join-Path $home1 '.claude/backups') -Directory)
Assert-Equal 1 $bk.Count 'one backup dir'
Assert-Equal 'old' ([System.IO.File]::ReadAllText((Join-Path $bk[0].FullName 'hooks/a.ps1'))) 'backup holds previous content'
Assert-Equal "run $ps `$HOME/.claude/skills/mvn-test/test.ps1 mod" ([System.IO.File]::ReadAllText((Join-Path $home1 '.claude/CLAUDE.md'))) 'sync installs the Windows-rewritten CLAUDE.md'
Assert-Equal 'run bash ~/.claude/skills/mvn-test/test.sh mod' ([System.IO.File]::ReadAllText((Join-Path $rc 'CLAUDE.md'))) 'repo CLAUDE.md untouched by sync'
$bytes = [System.IO.File]::ReadAllBytes((Join-Path $home1 '.claude/settings.json'))
Assert-True (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'settings.json has no BOM'

$r = Invoke-Script $sync '' $env2 @()
Assert-Equal 0 $r.Code 'second sync in same minute does not fail (profile from marker)'

$bad = Invoke-Script $sync '' $env2 @('root')
Assert-Equal 1 $bad.Code 'invalid profile rejected'

$old = New-Item -ItemType Directory -Path (Join-Path $home1 '.claude/backups/100'), (Join-Path $home1 '.claude/backups/200'), (Join-Path $home1 '.claude/backups/300'), (Join-Path $home1 '.claude/backups/400'), (Join-Path $home1 '.claude/backups/500'), (Join-Path $home1 '.claude/backups/600')
$env3 = $env2.Clone(); $env3['BACKUP_KEEP'] = '3'
[System.IO.File]::WriteAllText((Join-Path $home1 '.claude/hooks/a.ps1'), 'older')
Remove-Item -Recurse -Force (Get-ChildItem (Join-Path $home1 '.claude/backups') -Directory | Where-Object { $_.Name -notmatch '^[1-6]00$' }).FullName
$r = Invoke-Script $sync '' $env3 @('sandbox')
$names = (Get-ChildItem (Join-Path $home1 '.claude/backups') -Directory | ForEach-Object { $_.Name } | Sort-Object) -join ','
Assert-True ($names -notmatch '(^|,)(100|200|300)(,|$)') 'prune keeps newest N only' "(got $names)"

Remove-Item -Force (Join-Path $rc 'settings.sandbox.windows.json')
[System.IO.File]::WriteAllText((Join-Path $home1 '.claude/hooks/a.ps1'), 'edited-locally')
$home1Fwd = $home1 -replace '\\', '/'
[System.IO.File]::WriteAllText((Join-Path $home1 '.claude/settings.json'), ('{"z":"' + $fwd + '/claude/x","a":[1],"h":"' + $home1Fwd + '/.claude/hooks/a.ps1"}'))
$r = Invoke-Script $save '' $env2 @('sandbox')
Assert-Equal 0 $r.Code 'save exits 0'
Assert-Equal 'edited-locally' ([System.IO.File]::ReadAllText((Join-Path $rc 'hooks/a.ps1'))) 'save copied file back'
Assert-Equal 'run bash ~/.claude/skills/mvn-test/test.sh mod' ([System.IO.File]::ReadAllText((Join-Path $rc 'CLAUDE.md'))) 'save never writes the Windows-rewritten CLAUDE.md back to the repo'
$saved = [System.IO.File]::ReadAllText((Join-Path $rc 'settings.sandbox.windows.json'))
Assert-Equal "{`n  `"a`": [`n    1`n  ],`n  `"h`": `"@@HOME@@/.claude/hooks/a.ps1`",`n  `"z`": `"@@REPO_DIR@@/claude/x`"`n}`n" $saved 'save sorts keys and restores both placeholders'

Write-Host 'windows settings'
foreach ($p in 'admin', 'sandbox') {
    $f = Join-Path $claudeDir "settings.$p.windows.json"
    $text = [System.IO.File]::ReadAllText($f)
    Assert-Equal $text ((ConvertTo-SortedJson ($text | ConvertFrom-Json)) + "`n") "settings.$p.windows.json is key-sorted"
    $obj = $text | ConvertFrom-Json
    $cmds = @()
    foreach ($ev in $obj.hooks.PSObject.Properties) { foreach ($e in @($ev.Value)) { foreach ($h in @($e.hooks)) { $cmds += [string]$h.command } } }
    Assert-True ($cmds.Count -gt 0) "settings.$p.windows.json has hooks"
    $matchers = @(); $timeouts = @()
    foreach ($ev in $obj.hooks.PSObject.Properties) { foreach ($e in @($ev.Value)) { if ($e.PSObject.Properties['matcher']) { $matchers += [string]$e.matcher }; foreach ($h in @($e.hooks)) { $timeouts += [int]$h.timeout } } }
    Assert-True (@($matchers | Where-Object { $_ -ceq 'Bash' }).Count -eq 0 -and @($matchers | Where-Object { $_ -ceq 'Bash|PowerShell' }).Count -gt 0) "settings.$p.windows.json Bash hooks also match the PowerShell tool"
    Assert-True (@($timeouts | Where-Object { $_ -lt 15 }).Count -eq 0) "settings.$p.windows.json hook timeouts allow for powershell.exe startup (>=15s)"
    $ok = $true
    foreach ($c in $cmds) {
        if ($c -notmatch '^powershell\.exe -NoProfile -ExecutionPolicy Bypass -File @@HOME@@/\.claude/(hooks/[A-Za-z-]+\.ps1)$') { $ok = $false; continue }
        if (-not (Test-Path (Join-Path $claudeDir $Matches[1]))) { $ok = $false }
    }
    Assert-True $ok "settings.$p.windows.json hook commands are PowerShell and point at existing scripts"
    Assert-True ($text -notmatch 'bash |zsh |ksh |\.sh[ "*)]') "settings.$p.windows.json has no bash script references"
}
$manifestPaths = Read-Manifest (Join-Path $claudeDir 'MANIFEST')
$missingPs1 = @(Get-ChildItem -Path (Join-Path $claudeDir 'hooks'), (Join-Path $claudeDir 'skills') -Recurse -Filter '*.ps1' -File | ForEach-Object {
    $rel = $_.FullName.Substring($claudeDir.Length + 1) -replace '\\', '/'
    if ($manifestPaths -cnotcontains $rel) { $rel }
})
Assert-Equal '' ($missingPs1 -join ',') 'every hook/skill .ps1 is listed in MANIFEST'

Write-Host 'Tree installs (agents/, copilot/)'
$repoRoot = Split-Path -Parent $claudeDir
foreach ($t in @(@('agents', '.agents'), @('copilot', '.copilot'))) {
    $dest = Join-Path (New-TempDir) $t[1]
    & (Join-Path $repoRoot ($t[0] + '/install.ps1')) $dest | Out-Null
    $name = $t[0]
    $bad = @(Get-ChildItem -LiteralPath $dest -Recurse -File -Include '*.md' | Where-Object {
            [System.IO.File]::ReadAllText($_.FullName) -match '\bbash [~<$/]|\.sh\b|\b(zsh|ksh) [~<]' } | ForEach-Object { $_.Name })
    Assert-Equal '' ($bad -join ',') "$name install: no bash script references in installed markdown"
    Assert-Equal 0 @(Get-ChildItem -LiteralPath $dest -Recurse -File -Filter '*.sh').Count "$name install: no .sh copied"
    Assert-True (Test-Path -LiteralPath (Join-Path $dest 'lib/Common.psm1')) "$name install: lib/Common.psm1 present"
    $missing = @(Get-ChildItem -LiteralPath (Join-Path $claudeDir 'skills') -Directory | ForEach-Object {
            $sk = $_.Name
            if (Test-Path -LiteralPath (Join-Path $repoRoot "$name/skills/$sk")) {
                foreach ($r in Get-ChildItem -LiteralPath $_.FullName -Filter '*.ps1' -File) {
                    if (-not (Test-Path -LiteralPath (Join-Path $dest "skills/$sk/$($r.Name)"))) { "$sk/$($r.Name)" }
                }
            }
        })
    Assert-Equal '' ($missing -join ',') "$name install: every skill has its .ps1 runner"
    Assert-True (Test-Path -LiteralPath (Join-Path $dest 'skills/mvn-test/SKILL.md')) "$name install: SKILL.md copied"
}
Assert-Equal '.claude' (Get-ToolDirName) 'tool dir name: repo/claude module logs under .claude'
$agentsDest = Join-Path (New-TempDir) '.agents'
& (Join-Path $repoRoot 'agents/install.ps1') $agentsDest | Out-Null
$installed = Import-Module (Join-Path $agentsDest 'lib/Common.psm1') -Force -PassThru
Assert-Equal '.agents' (& $installed { Get-ToolDirName }) 'tool dir name: module installed under ~/.agents logs under .agents'
Import-Module (Join-Path $claudeDir 'lib/Common.psm1') -Force

$s = Get-TestSummary
Write-Host ("Sync:{0} passed, {1} failed" -f $s.Pass, $s.Fail)
if ($s.Fail -gt 0) { exit 1 }
