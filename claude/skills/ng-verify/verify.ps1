#Requires -Version 5.1
# Usage:
#   verify.ps1                 -> typecheck + full unit test run, current dir
#   verify.ps1 <angular-dir>   -> typecheck + full unit test run in that dir
#   verify.ps1 <angular-dir> --include=<spec-glob>   -> scope tests to matching specs
#   verify.ps1 <angular-dir> --summary               -> print only the digest:
#                                                       TOTAL lines, error TS, failing specs + first error line
Import-Module AgentCommon -Force -ErrorAction SilentlyContinue
if (-not (Get-Module AgentCommon)) { Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/Common.psm1') -Force }

$log = Get-SkillLog 'ng-verify'
$start = Get-EpochSeconds

$dir = '.'
$include = ''
$summary = $false
foreach ($x in @($args | ForEach-Object { [string]$_ })) {
    if ($x.StartsWith('--include=')) { $include = $x }
    elseif ($x -ceq '--summary') { $summary = $true }
    else { $dir = $x }
}

Set-Location -LiteralPath $dir

if (-not (Test-Path -LiteralPath 'tsconfig.app.json')) {
    Write-Host "ERROR: no tsconfig.app.json in $dir -- not an Angular app root?"
    exit 1
}
if (-not ((Test-Path -LiteralPath 'node_modules/.bin/tsc') -or (Test-Path -LiteralPath 'node_modules/.bin/tsc.cmd'))) {
    Write-Host "ERROR: dependencies not installed in $dir -- run npm install first"
    exit 1
}

# Headless Chrome for karma/ng test -- avoids the recurring "Chrome failed to start" when CHROME_BIN is unset.
if (-not $env:CHROME_BIN) {
    $homeDir = Get-UserHome
    $roots = @((Join-Path $homeDir '.cache/puppeteer'), (Join-Path $homeDir 'Library/Caches/ms-playwright'))
    if ($env:LOCALAPPDATA) { $roots += (Join-Path $env:LOCALAPPDATA 'ms-playwright') }
    if (Test-WindowsHost) {
        $fixed = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe")
        $hit = $fixed | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
        if ($hit) { $env:CHROME_BIN = $hit }
    }
    if (-not $env:CHROME_BIN) {
        $pat = if (Test-WindowsHost) { 'chrome*.exe' } else { '*chrome*' }
        foreach ($r in $roots) {
            if (Test-Path -LiteralPath $r) {
                $f = Get-ChildItem -LiteralPath $r -Recurse -File -Filter $pat -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($f) { $env:CHROME_BIN = $f.FullName; break }
            }
        }
    }
}

$all = New-Object System.Collections.Generic.List[string]
function Add-Section {
    param([string]$Header, [string]$Exe, [string[]]$Arguments)
    $all.Add($Header)
    if (-not $summary) { [Console]::Out.WriteLine($Header) }
    $res = Invoke-Logged $Exe $Arguments -Quiet:$summary
    foreach ($l in $res.Lines) { $all.Add($l) }
    return $res.Code
}

$tscExit = Add-Section 'Typecheck: npx tsc --noEmit -p tsconfig.app.json' 'npx' @('tsc', '--noEmit', '-p', 'tsconfig.app.json')
if (-not $summary) { Write-Host '' }
$all.Add('')
$ngArgs = @('ng', 'test', '--watch=false', '--browsers=ChromeHeadless')
if ($include -ne '') { $ngArgs += $include }
$testExit = Add-Section ('Test: npx ' + ($ngArgs -join ' ')) 'npx' $ngArgs

Write-Utf8File $log (($all -join "`n") + "`n")

$dur = (Get-EpochSeconds) - $start
$t = if ($tscExit -eq 0) { 'OK' } else { 'FAILED' }
$u = if ($testExit -eq 0) { 'PASSED' } else { 'FAILED' }
Write-Host ''
Write-Host "--- TYPECHECK $t, TESTS $u in ${dur}s ---"

if ($tscExit -ne 0) {
    Write-Host ''
    Write-Host 'Typecheck errors:'
    $all | Where-Object { $_ -cmatch 'error TS' } | ForEach-Object { Write-Host $_ }
}

if ($testExit -ne 0) {
    Write-Host ''
    Write-Host 'Test failures:'
    if ($summary) {
        $all | Where-Object { $_ -cmatch 'TOTAL' } | ForEach-Object { Write-Host $_ }
        for ($i = 0; $i -lt $all.Count; $i++) {
            if ($all[$i] -cmatch 'FAILED$') {
                Write-Host $all[$i]
                if ($i + 1 -lt $all.Count) { Write-Host ('    ' + $all[$i + 1]) }
            }
        }
    } else {
        $all | Where-Object { $_ -cmatch 'FAILED' } | ForEach-Object { Write-Host $_ }
    }
} elseif ($summary) {
    @($all | Where-Object { $_ -cmatch 'TOTAL|Executed [0-9]+ of [0-9]+ .*SUCCESS' } | Select-Object -Last 2) | ForEach-Object { Write-Host $_ }
}

if ($tscExit -eq 0 -and $testExit -eq 0) { exit 0 } else { exit 1 }
