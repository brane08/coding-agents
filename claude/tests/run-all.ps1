#Requires -Version 5.1
# Runs every *.Tests.ps1 in this directory in a child process of the same PowerShell host.
$host_exe = (Get-Process -Id $PID).Path
$failed = 0
foreach ($t in (Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' | Sort-Object Name)) {
    Write-Host "=== $($t.Name) ==="
    & $host_exe -NoProfile -ExecutionPolicy Bypass -File $t.FullName
    if ($LASTEXITCODE -ne 0) { $failed++ }
}
if ($failed -gt 0) { Write-Host "$failed test file(s) failed"; exit 1 }
Write-Host 'All test files passed'
exit 0
