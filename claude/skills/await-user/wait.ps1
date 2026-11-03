#Requires -Version 5.1
# End-of-loop wait: sleeps <seconds> (integer 1..120) and prints "waited N s".
# Usage: wait.ps1 <seconds>
param([string]$Seconds = '')

$n = 0
if ($Seconds -notmatch '^[0-9]+$' -or -not [int]::TryParse($Seconds, [ref]$n) -or $n -lt 1 -or $n -gt 120) {
    [Console]::Error.WriteLine('usage: wait.ps1 <seconds 1-120>')
    exit 2
}

Start-Sleep -Seconds $n
[Console]::Out.WriteLine("waited $n s")
exit 0
