#Requires -Version 5.1
# Usage:
#   build.ps1                      -> builds current directory module only
#   build.ps1 mono-quarkus         -> builds named module via -pl
#   build.ps1 -pl mono-quarkus     -> same
#   build.ps1 --reactor            -> full reactor build
# Extra -flags are passed to mvn as separate arguments (never evaluated by a shell).
Import-Module AgentCommon -Force -ErrorAction SilentlyContinue
if (-not (Get-Module AgentCommon)) { Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/Common.psm1') -Force }

$log = Get-SkillLog 'mvn-build'
$start = Get-EpochSeconds
$proj = Get-ProjectDir
Set-Location -LiteralPath $proj

$isReactor = (Test-Path -LiteralPath 'pom.xml') -and ([System.IO.File]::ReadAllText((Resolve-Path 'pom.xml').ProviderPath).Contains('<modules>'))

$module = ''
$extra = @()
$full = $false
$a = @($args | ForEach-Object { [string]$_ })
for ($i = 0; $i -lt $a.Count; $i++) {
    $x = $a[$i]
    if ($x -ceq '--reactor') { $full = $true }
    elseif ($x -ceq '-pl') { $i++; $module = if ($i -lt $a.Count) { $a[$i] } else { '' } }
    elseif ($x.StartsWith('-')) { $extra += $x }
    else { $module = $x }
}

if ($module -ne '' -and $module -cnotmatch '^[A-Za-z0-9._,:/-]+$') { Write-Host "ERROR: invalid module name: $module"; exit 2 }

if ($full) { $mvnArgs = @('clean', 'package', '-DskipTests', '-T1C') }
elseif ($module -ne '') { $mvnArgs = @('clean', 'package', '-pl', $module, '-am', '-DskipTests') }
elseif ($isReactor) {
    Write-Host 'ERROR: At reactor root. Specify a module to avoid full reactor build.'
    Write-Host 'Usage: build.ps1 <module-name>  or  build.ps1 --reactor'
    exit 1
}
else { $mvnArgs = @('clean', 'package', '-DskipTests') }
$mvnArgs += $extra

Write-Host ('Running: mvn ' + ($mvnArgs -join ' '))
$r = Invoke-Logged 'mvn' $mvnArgs
Write-Utf8File $log (($r.Lines -join "`n") + "`n")

$dur = (Get-EpochSeconds) - $start
$status = if ($r.Code -eq 0) { 'OK' } else { 'FAILED' }
Write-Host ''
Write-Host "--- BUILD $status in ${dur}s ---"

if ($r.Code -ne 0) {
    Write-Host ''
    Write-Host 'Errors:'
    $errs = @($r.Lines | Where-Object { $_ -cmatch '^\[ERROR\]' })
    if ($errs.Count -eq 0) { Write-Host '(no [ERROR] lines found)' } else { $errs | ForEach-Object { Write-Host $_ } }
}
exit $r.Code
