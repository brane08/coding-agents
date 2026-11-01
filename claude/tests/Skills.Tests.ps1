#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$skills = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/Common.psm1') -Force

$win = Test-WindowsHost
$root = New-TempDir
$stubDir = Join-Path $root 'stubs'
New-Item -ItemType Directory -Path $stubDir | Out-Null
$argsFile = Join-Path $root 'argv.txt'

# Stub executables record "args joined by space" (plus PGOPTIONS) to $env:STUB_OUT and print canned lines.
function New-Stub {
    param([string]$Name, [string[]]$Output)
    if ($win) {
        $body = "@echo off`r`necho %* > `"%STUB_OUT%`"`r`necho PGOPTIONS=%PGOPTIONS% >> `"%STUB_OUT%`"`r`n"
        foreach ($l in $Output) { $body += "echo $l`r`n" }
        $body += "exit /b %STUB_EXIT%`r`n"
        [System.IO.File]::WriteAllText((Join-Path $stubDir "$Name.cmd"), $body)
    } else {
        $f = Join-Path $stubDir $Name
        $body = "#!/bin/sh`necho `"`$*`" > `"`$STUB_OUT`"`necho `"PGOPTIONS=`$PGOPTIONS`" >> `"`$STUB_OUT`"`n"
        foreach ($l in $Output) { $body += "echo '$l'`n" }
        $body += "exit `${STUB_EXIT:-0}`n"
        [System.IO.File]::WriteAllText($f, $body)
        & chmod +x $f
    }
}
New-Stub 'mvn' @('[INFO] Tests run: 3, Failures: 0', '[INFO] Version  State  current', '[INFO] --- plugin', '[ERROR] boom')
New-Stub 'psql' @('1')

$pathSep = [System.IO.Path]::PathSeparator
$baseEnv = @{ PATH = ($stubDir + $pathSep + $env:PATH); STUB_OUT = $argsFile; STUB_EXIT = '0' }
function Env-With { param([hashtable]$Extra) $e = $baseEnv.Clone(); foreach ($k in $Extra.Keys) { $e[$k] = $Extra[$k] }; return $e }
function Last-Argv { ([System.IO.File]::ReadAllLines($argsFile))[0].Trim() }

$proj = Join-Path $root 'proj'
New-Item -ItemType Directory -Path $proj | Out-Null

Write-Host 'psql-select'
$sel = Join-Path $skills 'psql-select/select.ps1'
$r = Invoke-Script $sel '' (Env-With @{}) @('select 1') $proj
Assert-Equal 0 $r.Code 'select short form exits 0'
Assert-Equal '-h localhost -U postgres -d prore -A -t -c select 1' (Last-Argv) 'short form builds psql args'
Assert-Match 'PGOPTIONS=.*default_transaction_read_only=on' ([System.IO.File]::ReadAllText($argsFile)) 'read-only forced via PGOPTIONS'
$r = Invoke-Script $sel '' (Env-With @{}) @('pagila', 'show server_version') $proj
Assert-Equal '-h localhost -U postgres -d pagila -A -t -c show server_version' (Last-Argv) 'db + sql form'
foreach ($bad in @('drop table x', 'select 1; select 2', 'delete from t')) {
    $r = Invoke-Script $sel '' (Env-With @{}) @($bad) $proj
    Assert-True ($r.Code -eq 1 -and $r.Err -match 'blocked') "blocked: $bad"
}
$r = Invoke-Script $sel '' (Env-With @{}) @('-h', 'localhost', '-Atc', 'select 1') $proj
Assert-True ($r.Code -eq 1 -and $r.Err -match 'combined short flags') 'combined -Atc blocked'
$r = Invoke-Script $sel '' (Env-With @{}) @('-d', 'x', '-f', 'a.sql') $proj
Assert-True ($r.Code -eq 1 -and $r.Err -match 'single') '-f blocked'
$r = Invoke-Script $sel '' (Env-With @{}) @('-d', 'x', '-c', 'select 1', '-c', 'select 2') $proj
Assert-True ($r.Code -eq 1 -and $r.Err -match 'exactly one') 'two -c blocked'

Write-Host 'mvn-test'
$tst = Join-Path $skills 'mvn-test/test.ps1'
$e = Env-With @{ CLAUDE_PROJECT_DIR = $proj }
$r = Invoke-Script $tst '' $e @('mod-a', 'FooTest') $proj
Assert-Equal 0 $r.Code 'test.ps1 exits 0'
Assert-Equal 'verify -pl mod-a -am -Dtest=FooTest -DfailIfNoTests=false -Dsurefire.failIfNoSpecifiedTests=false' (Last-Argv) 'module+class args'
Assert-Match '--- TESTS PASSED in \d+s ---' $r.Out 'passed banner'
Assert-True (Test-Path (Join-Path $proj '.claude/logs/mvn-test.log')) 'log written under project .claude/logs'
Assert-Equal '*' (([System.IO.File]::ReadAllText((Join-Path $proj '.claude/logs/.gitignore'))).Trim()) 'log dir self-ignoring'
$r = Invoke-Script $tst '' $e @('--summary') $proj
Assert-Equal 2 $r.Code 'flags rejected'
$r = Invoke-Script $tst '' $e @('bad module!') $proj
Assert-Equal 2 $r.Code 'invalid module rejected'
$r = Invoke-Script $tst '' (Env-With @{ CLAUDE_PROJECT_DIR = $proj; STUB_EXIT = '1' }) @('mod-a') $proj
Assert-True ($r.Code -eq 1 -and $r.Out -match '--- TESTS FAILED') 'failure propagates exit code'
$reactor = Join-Path $root 'reactor'
New-Item -ItemType Directory -Path $reactor | Out-Null
[System.IO.File]::WriteAllText((Join-Path $reactor 'pom.xml'), '<project><modules><module>a</module></modules></project>')
$r = Invoke-Script $tst '' (Env-With @{ CLAUDE_PROJECT_DIR = $reactor }) @() $reactor
Assert-True ($r.Code -eq 1 -and $r.Out -match 'At reactor root') 'reactor root requires module'

Write-Host 'mvn-build'
$bld = Join-Path $skills 'mvn-build/build.ps1'
$r = Invoke-Script $bld '' $e @('-pl', 'mod-a', '-Dfoo.bar=1') $proj
Assert-Equal 'clean package -pl mod-a -am -DskipTests -Dfoo.bar=1' (Last-Argv) 'dotted -D arg passes intact'
$r = Invoke-Script $bld '' $e @('--reactor') $proj
Assert-Equal 'clean package -DskipTests -T1C' (Last-Argv) 'reactor build args'
$r = Invoke-Script $bld '' (Env-With @{ CLAUDE_PROJECT_DIR = $proj; STUB_EXIT = '1' }) @('mod-a') $proj
Assert-True ($r.Code -eq 1 -and $r.Out -match '--- BUILD FAILED' -and $r.Out -match '\[ERROR\] boom') 'build failure lists [ERROR] lines'

Write-Host 'flyway-check'
$fw = Join-Path $skills 'flyway-check/flyway-check.ps1'
$r = Invoke-Script $fw '' $e @() $proj
Assert-Equal 'flyway:info -Dflyway.url=jdbc:postgresql://localhost:5432/dev -Dflyway.user=dev' (Last-Argv) 'default flyway args'
Assert-True ($r.Out -match 'Version' -and $r.Out -notmatch '---' -and $r.Out -notmatch 'boom') 'output filtered'
$r = Invoke-Script $fw '' (Env-With @{ CLAUDE_PROJECT_DIR = $proj; FLYWAY_MODULE = 'm/x' }) @('other') $proj
Assert-Equal 'flyway:info -pl m/x -am -Dflyway.url=jdbc:postgresql://localhost:5432/other -Dflyway.user=dev' (Last-Argv) 'module + db argument'

Write-Host 'ng-verify'
$ng = Join-Path $skills 'ng-verify/verify.ps1'
$r = Invoke-Script $ng '' $e @($proj) $proj
Assert-True ($r.Code -eq 1 -and $r.Out -match 'not an Angular app root') 'non-angular dir rejected'

Write-Host 'guarded-fs'
$gf = Join-Path $skills 'guarded-fs/guarded-fs.ps1'
$w = Join-Path $root 'work'
New-Item -ItemType Directory -Path (Join-Path $w 'sub'), (Join-Path $w '.git') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $w 'a.txt'), 'a')
[System.IO.File]::WriteAllText((Join-Path $w 'sub/b.txt'), 'b')
[System.IO.File]::WriteAllText((Join-Path $root 'outside.txt'), 'o')
$r = Invoke-Script $gf '' @{} @('cp', 'a.txt', 'c.txt') $w
Assert-True ($r.Code -eq 0 -and (Test-Path (Join-Path $w 'c.txt'))) 'cp inside ok'
$r = Invoke-Script $gf '' @{} @('cp', '-r', 'sub', 'sub2') $w
Assert-True ($r.Code -eq 0 -and (Test-Path (Join-Path $w 'sub2/b.txt'))) 'cp -r dir ok'
$r = Invoke-Script $gf '' @{} @('mv', 'c.txt', 'd.txt') $w
Assert-True ($r.Code -eq 0 -and (Test-Path (Join-Path $w 'd.txt')) -and -not (Test-Path (Join-Path $w 'c.txt'))) 'mv inside ok'
$r = Invoke-Script $gf '' @{} @('rm', 'd.txt', 'sub2') $w
Assert-True ($r.Code -eq 0 -and -not (Test-Path (Join-Path $w 'd.txt')) -and -not (Test-Path (Join-Path $w 'sub2'))) 'rm file + dir ok'
foreach ($case in @(@('rm', '../outside.txt'), @('rm', '.'), @('rm', '.git'), @('rm', '.git/config'), @('mv', 'a.txt', '../moved.txt'), @('mv', '../outside.txt', 'in.txt'), @('cp', '../outside.txt', 'in.txt'), @('cp', 'a.txt', '../x.txt'), @('cp', '-X', 'a.txt', 'z.txt'), @('mv', 'a.txt', 'nodir/a.txt'))) {
    $r = Invoke-Script $gf '' @{} $case $w
    Assert-True ($r.Code -eq 1 -and $r.Err -match 'guarded-fs|usage|blocked') ("blocked: " + ($case -join ' '))
}
Assert-True ((Test-Path (Join-Path $root 'outside.txt')) -and (Test-Path (Join-Path $w 'a.txt')) -and (Test-Path (Join-Path $w '.git'))) 'blocked ops left files untouched'
$r = Invoke-Script $gf '' @{} @('cp', 'sub', 'copy') $w
Assert-Equal 1 $r.Code 'cp dir without -r fails'

$r = Invoke-Script $gf '' @{} @('rm', 'GIT~1') $w
Assert-Equal 1 $r.Code 'rm of 8.3 short name of .git blocked'

if (-not $win) {
    $outDir = Join-Path $root 'outdir'
    New-Item -ItemType Directory -Path $outDir | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $outDir 'keep.txt'), 'k')
    & ln -s $outDir (Join-Path $w 'dirlink')
    $r = Invoke-Script $gf '' @{} @('rm', 'dirlink') $w
    Assert-True ($r.Code -eq 0 -and -not (Test-Path (Join-Path $w 'dirlink')) -and (Test-Path (Join-Path $outDir 'keep.txt'))) 'rm of dir symlink removes only the link'
    New-Item -ItemType Directory -Path (Join-Path $w 'tree') | Out-Null
    & ln -s $outDir (Join-Path $w 'tree/nested')
    $r = Invoke-Script $gf '' @{} @('rm', 'tree') $w
    Assert-True ($r.Code -eq 0 -and -not (Test-Path (Join-Path $w 'tree')) -and (Test-Path (Join-Path $outDir 'keep.txt'))) 'rm of tree containing a link never descends into the link target'
}

if (-not $win) {
    & ln -s (Join-Path $root 'outside.txt') (Join-Path $w 'link.txt')
    $r = Invoke-Script $gf '' @{} @('cp', 'a.txt', 'link.txt') $w
    Assert-True ($r.Code -eq 1 -and $r.Err -match 'outside working dir') 'destination symlink judged by target'
}

$s = Get-TestSummary
Write-Host ("Skills: {0} passed, {1} failed" -f $s.Pass, $s.Fail)
if ($s.Fail -gt 0) { exit 1 }
