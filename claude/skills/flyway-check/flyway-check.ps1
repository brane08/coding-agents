#Requires -Version 5.1
# Usage: flyway-check.ps1 [database]
# Database precedence: argument > $env:DB_NAME > "dev". $env:DB_URL, if set, is used as-is
# and the database argument is ignored. Local DBs use trust auth: no password handling.
# Maven runs from the project root ($env:CLAUDE_PROJECT_DIR, else the current directory);
# set FLYWAY_MODULE to a module path to pass -pl <module> -am.
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/Common.psm1') -Force

$proj = Get-ProjectDir
Set-Location -LiteralPath $proj

$arg = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
$dbName = if ($arg -ne '') { $arg } elseif ($env:DB_NAME) { $env:DB_NAME } else { 'dev' }
$dbHost = if ($env:DB_HOST) { $env:DB_HOST } else { 'localhost' }
$dbPort = if ($env:DB_PORT) { $env:DB_PORT } else { '5432' }
$default = "jdbc:postgresql://${dbHost}:${dbPort}/${dbName}"
$dbUrl = if ($arg -eq '' -and $env:DB_URL) { $env:DB_URL } else { $default }
$dbUser = if ($env:DB_USER) { $env:DB_USER } else { 'dev' }

$mvnArgs = @('flyway:info')
if ($env:FLYWAY_MODULE) {
    if ($env:FLYWAY_MODULE -cnotmatch '^[A-Za-z0-9._,:/-]+$') { Write-Host "ERROR: invalid FLYWAY_MODULE: $($env:FLYWAY_MODULE)"; exit 2 }
    $mvnArgs += @('-pl', $env:FLYWAY_MODULE, '-am')
}
$mvnArgs += @("-Dflyway.url=$dbUrl", "-Dflyway.user=$dbUser")

$r = Invoke-Logged 'mvn' $mvnArgs -Quiet
$out = @($r.Lines | Where-Object { $_ -cmatch 'Version|State|Pending|current|Failed|Checksum' } | Where-Object { $_ -cnotmatch '^\[INFO\] ---' })
$out | ForEach-Object { Write-Host $_ }
if ($r.Code -ne 0) { exit $r.Code }
if ($out.Count -eq 0) { exit 1 }
exit 0
