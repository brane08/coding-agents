#Requires -Version 5.1
# Usage:
#   test.ps1                                -> tests current dir module
#   test.ps1 mono-quarkus                   -> tests named module (with -am)
#   test.ps1 mono-quarkus UserServiceTest   -> specific test class in module
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/Common.psm1') -Force

$log = Get-SkillLog 'mvn-test'
$start = Get-EpochSeconds
$proj = Get-ProjectDir
Set-Location -LiteralPath $proj

$isReactor = (Test-Path -LiteralPath 'pom.xml') -and ([System.IO.File]::ReadAllText((Resolve-Path 'pom.xml').ProviderPath).Contains('<modules>'))

$a = @($args | ForEach-Object { [string]$_ })
$module = if ($a.Count -ge 1) { $a[0] } else { '' }
$pattern = if ($a.Count -ge 2) { $a[1] } else { '' }

if ($a.Count -gt 2 -or $module.StartsWith('-') -or $pattern.StartsWith('-')) {
    Write-Host 'ERROR: usage: test.ps1 [<module> [TestClass]] -- no flags (--summary belongs to ng-verify/verify.ps1)'
    exit 2
}
if ($module -ne '' -and $module -cnotmatch '^[A-Za-z0-9._,:/-]+$') { Write-Host "ERROR: invalid module name: $module"; exit 2 }
if ($pattern -ne '' -and $pattern -cnotmatch '^[A-Za-z0-9._,#*?+!-]+$') { Write-Host "ERROR: invalid test pattern: $pattern"; exit 2 }

if ($module -ne '' -and $pattern -ne '') {
    $mvnArgs = @('verify', '-pl', $module, '-am', "-Dtest=$pattern", '-DfailIfNoTests=false', '-Dsurefire.failIfNoSpecifiedTests=false')
} elseif ($module -ne '') {
    $mvnArgs = @('verify', '-pl', $module, '-am')
} elseif ($isReactor) {
    Write-Host 'ERROR: At reactor root. Specify a module: test.ps1 <module> [TestClass]'
    exit 1
} else {
    $mvnArgs = @('verify')
}

Write-Host ('Running: mvn ' + ($mvnArgs -join ' '))
$r = Invoke-Logged 'mvn' $mvnArgs
Write-Utf8File $log (($r.Lines -join "`n") + "`n")

$dur = (Get-EpochSeconds) - $start
$status = if ($r.Code -eq 0) { 'PASSED' } else { 'FAILED' }
Write-Host ''
Write-Host "--- TESTS $status in ${dur}s ---"
Write-Host ''

@($r.Lines | Where-Object { $_ -match 'Tests run:' } | Select-Object -Last 5) | ForEach-Object { Write-Host $_ }

$failures = @($r.Lines | Where-Object { $_ -cmatch 'FAILED|<<< ERROR' })
if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host 'Failed:'
    $failures | ForEach-Object { Write-Host $_ }
    Write-Host ''
    Write-Host 'Details (first 6 lines after each failure):'
    $reports = @(Get-ChildItem -Path '*/target/surefire-reports/*.txt', 'target/surefire-reports/*.txt' -File -ErrorAction SilentlyContinue)
    foreach ($f in $reports) {
        $lines = [System.IO.File]::ReadAllLines($f.FullName)
        $out = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -cmatch '<<< (FAILURE|ERROR)') {
                for ($j = $i; $j -le [Math]::Min($i + 6, $lines.Count - 1); $j++) { $out.Add($lines[$j]) }
            }
        }
        $out | Select-Object -First 40 | ForEach-Object { Write-Host $_ }
    }
}
exit $r.Code
