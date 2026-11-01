#Requires -Version 5.1
# Minimal dependency-free test helpers (Pester 5 is not available on stock Windows 11).
$script:Pass = 0
$script:Fail = 0
$script:HostExe = (Get-Process -Id $PID).Path
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function New-TempDir {
    $d = Join-Path ([System.IO.Path]::GetTempPath()) ('cc-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

function Invoke-Script {
    param(
        [Parameter(Mandatory)][string]$Script,
        [string]$Stdin = '',
        [hashtable]$Env = @{},
        [string[]]$Arguments = @(),
        [string]$WorkDir = (Get-Location).Path
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:HostExe
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $Script + '"')) + @($Arguments | ForEach-Object { '"' + $_ + '"' })
    $psi.Arguments = $argList -join ' '
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $WorkDir
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = [string]$Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    $bytes = $script:Utf8NoBom.GetBytes($Stdin)
    $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $p.StandardInput.Close()
    $p.WaitForExit()
    return [pscustomobject]@{ Out = $out.Result; Err = $err.Result; Code = $p.ExitCode }
}

function Assert-True {
    param([bool]$Cond, [string]$Name, [string]$Detail = '')
    if ($Cond) { $script:Pass++; Write-Host "  ok   $Name" }
    else { $script:Fail++; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    $e = [string]$Expected; $a = [string]$Actual
    if ($e.Length -gt 300) { $e = $e.Substring(0, 300) + '...' }
    if ($a.Length -gt 300) { $a = $a.Substring(0, 300) + '...' }
    Assert-True ($Expected -ceq $Actual) $Name "(expected [$e] got [$a])"
}

function Assert-Match {
    param([string]$Pattern, [string]$Actual, [string]$Name)
    $a = $Actual
    if ($a.Length -gt 300) { $a = $a.Substring(0, 300) + '...' }
    Assert-True ($Actual -match $Pattern) $Name "(pattern [$Pattern] in [$a])"
}

function Get-TestSummary { return [pscustomobject]@{ Pass = $script:Pass; Fail = $script:Fail } }
