#Requires -Version 5.1
# Starts `mvn quarkus:dev` in the background and waits up to 60s for startup.
# Usage: dev.ps1 [port]. Env: CLAUDE_PROJECT_DIR (project root, default cwd), QUARKUS_PORT (default 8080).
# Logs: <project>/.claude/logs/quarkus-dev.log (stdout), quarkus-dev.err.log (stderr).
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/Common.psm1') -Force

$proj = Get-ProjectDir
Set-Location -LiteralPath $proj

$log = Get-SkillLog 'quarkus-dev'
$errLog = $log -replace '\.log$', '.err.log'
$port = if ($args.Count -gt 0) { [string]$args[0] } elseif ($env:QUARKUS_PORT) { $env:QUARKUS_PORT } else { '8080' }
if ($port -notmatch '^\d+$') { Write-Host "ERROR: invalid QUARKUS_PORT: $port"; exit 2 }

$existing = @()
if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
    $existing = @(Get-NetTCPConnection -LocalPort ([int]$port) -State Listen -ErrorAction SilentlyContinue | ForEach-Object { $_.OwningProcess } | Sort-Object -Unique)
} elseif (Get-Command lsof -ErrorAction SilentlyContinue) {
    $existing = @((& lsof -ti "tcp:$port" '-sTCP:LISTEN' 2>$null) | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
}
if ($existing.Count -gt 0) {
    Write-Host ("Killing existing process on port $port (PID " + ($existing -join ' ') + ')')
    foreach ($p in $existing) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
}

$mvn = Get-Command mvn -ErrorAction SilentlyContinue
if ($null -eq $mvn) { Write-Host 'ERROR: mvn not found on PATH'; exit 1 }

$sp = @{
    FilePath               = $mvn.Source
    ArgumentList           = @('quarkus:dev', "-Dquarkus.http.port=$port", '-Dquarkus.live-reload.enabled=true')
    RedirectStandardOutput = $log
    RedirectStandardError  = $errLog
    PassThru               = $true
}
if (Test-WindowsHost) { $sp.WindowStyle = 'Hidden' }
$proc = Start-Process @sp
Write-Host "PID: $($proc.Id)"

function Read-Logs {
    $all = @()
    foreach ($f in @($log, $errLog)) {
        if (Test-Path -LiteralPath $f) {
            try {
                $fs = New-Object System.IO.FileStream($f, 'Open', 'Read', 'ReadWrite')
                $sr = New-Object System.IO.StreamReader($fs)
                $all += @(($sr.ReadToEnd()) -split '\r?\n')
                $sr.Dispose()
            } catch { }
        }
    }
    return , $all
}

for ($i = 0; $i -lt 60; $i++) {
    $lines = Read-Logs
    if (@($lines | Where-Object { $_ -match 'Listening on:' }).Count -gt 0) { break }
    if ($proc.HasExited) {
        Write-Host 'Process exited unexpectedly. Last log lines:'
        $lines | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
        exit 1
    }
    Start-Sleep -Seconds 1
}

Write-Host ''
$hits = @((Read-Logs) | Where-Object { $_ -match 'Listening on:|Dev UI available at|started in|Quarkus .* started' })
if ($hits.Count -gt 0) { $hits | ForEach-Object { Write-Host $_ } }
else { Write-Host "Startup may still be in progress. Check: $log" }
exit 0
