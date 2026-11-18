#Requires -Version 5.1
# Usage: pull.ps1 <groupId:artifactId:version>
# Pulls <artifactId>-<version>-sources.jar into ~/.m2/repository via dependency:get.
# Every attempt is logged to <project>/.claude/logs/pull-sources.log; after MAX failed
# attempts for the same GAV it refuses (exit 3) so the caller asks the user instead.
# Exit: 0 present/pulled, 1 pull failed, 2 bad usage, 3 attempt limit reached.
Import-Module AgentCommon -Force -ErrorAction SilentlyContinue
if (-not (Get-Module AgentCommon)) { Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/Common.psm1') -Force }

$max = 2
$a = @($args | ForEach-Object { [string]$_ })
if ($a.Count -ne 1) { Write-Host 'Usage: pull.ps1 <groupId:artifactId:version>'; exit 2 }
$gav = $a[0]
if ($gav -cnotmatch '^[A-Za-z0-9._-]+:[A-Za-z0-9._-]+:[A-Za-z0-9._-]+$') { Write-Host "ERROR: expected groupId:artifactId:version, got: $gav"; exit 2 }
$parts = $gav.Split(':')
$group = $parts[0]; $artifact = $parts[1]; $version = $parts[2]

$jar = Join-Path (Get-UserHome) (".m2/repository/" + $group.Replace('.', '/') + "/$artifact/$version/$artifact-$version-sources.jar")
if (Test-Path -LiteralPath $jar) { Write-Host "sources already present: $jar"; exit 0 }

$log = Get-SkillLog 'pull-sources'
$fails = 0
if (Test-Path -LiteralPath $log) {
    $fails = @(Get-Content -LiteralPath $log | Where-Object { $_.Contains(" $gav FAIL") }).Count
}
if ($fails -ge $max) {
    Write-Host "pull failed ${fails}x for $gav (limit $max) - stop and ask the user (javap ok?)."
    exit 3
}

Set-Location -LiteralPath (Get-ProjectDir)
$r = Invoke-Logged 'mvn' @('-B', '-q', 'dependency:get', "-Dartifact=${gav}:jar:sources", '-Dtransitive=false')

$ts = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
if ($r.Code -eq 0 -and (Test-Path -LiteralPath $jar)) {
    Add-Utf8Line -File $log -Line "$ts $gav OK"
    Write-Host "pulled: $jar"
    exit 0
}

Add-Utf8Line -File $log -Line "$ts $gav FAIL"
@($r.Lines | Where-Object { $_ -cmatch '^\[ERROR\]' } | Select-Object -Last 5) | ForEach-Object { Write-Host $_ }
Write-Host ("attempt {0}/{1} failed for {2} (no sources published, or network/repo issue)." -f ($fails + 1), $max, $gav)
exit 1
