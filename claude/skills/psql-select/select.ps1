#Requires -Version 5.1
# Auto-approved wrapper for read-only psql queries.
# Allows a single SELECT, EXPLAIN, SHOW or WITH statement via one -c.
# Exits 1 (blocked) for anything else; the server also enforces read-only.
#
# Short form against the local Postgres: select.ps1 "<sql>" | select.ps1 <db> "<sql>"
# (host localhost, user postgres, db prore unless given, unaligned tuples-only output).
# Reads only; never point it at a remote or prod host.
$a = @($args | ForEach-Object { [string]$_ })

if ($a.Count -ge 1 -and -not $a[0].StartsWith('-')) {
    switch ($a.Count) {
        1 { $a = @('-h', 'localhost', '-U', 'postgres', '-d', 'prore', '-A', '-t', '-c', $a[0]) }
        2 { $a = @('-h', 'localhost', '-U', 'postgres', '-d', $a[0], '-A', '-t', '-c', $a[1]) }
        default { [Console]::Error.WriteLine('psql-select: usage: select.ps1 "<sql>" | select.ps1 <db> "<sql>"'); exit 1 }
    }
}

function Stop-Blocked([string]$Why) {
    [Console]::Error.WriteLine("psql-select: blocked -- $Why")
    exit 1
}
function Test-LocalHost([string]$h) {
    if ($h -cnotmatch '^(localhost|127\.0\.0\.1|::1|/.*)$') { Stop-Blocked "host '$h' is not local; this wrapper only queries the local Postgres. Use plain psql." }
}
function Test-DbName([string]$d) {
    if ($d -match '=|://') { Stop-Blocked '-d/--dbname must be a plain database name (no conninfo string or URI).' }
}

$sql = ''
$nc = 0
for ($i = 0; $i -lt $a.Count; $i++) {
    $x = $a[$i]
    $nextVal = if ($i + 1 -lt $a.Count) { $a[$i + 1] } else { '' }
    if ($x -ceq '-h' -or $x -ceq '--host') { Test-LocalHost $nextVal }
    elseif ($x.StartsWith('--host=')) { Test-LocalHost $x.Substring(7) }
    elseif ($x -cmatch '^-h.+') { Test-LocalHost $x.Substring(2) }
    elseif ($x -ceq '-d' -or $x -ceq '--dbname') { Test-DbName $nextVal }
    elseif ($x.StartsWith('--dbname=')) { Test-DbName $x.Substring(9) }
    elseif ($x -cmatch '^-d.+') { Test-DbName $x.Substring(2) }
    if ($x -cmatch '^(-o.*|--output(=.*)?|-L.*|--log-file(=.*)?)$') {
        Stop-Blocked '-o/--output and -L/--log-file write to disk. Use plain psql.'
    }
    if ($x -ceq '-c') {
        $nc++
        $i++
        $sql = if ($i -lt $a.Count) { $a[$i] } else { '' }
    }
    elseif ($x -cmatch '^(-c.+|--command|--command=.*|-f|-f.+|--file|--file=.*)$') {
        [Console]::Error.WriteLine("psql-select: blocked -- use a single '-c <sql>' (no --command/-f/--file/-c<sql>). Use plain psql.")
        exit 1
    }
    elseif ($x -cmatch '^-[a-zA-Z]*c$') {
        [Console]::Error.WriteLine("psql-select: blocked -- combined short flags ending in -c; pass '-c' separately.")
        exit 1
    }
}

if ($nc -ne 1 -or [string]::IsNullOrEmpty($sql)) {
    [Console]::Error.WriteLine('psql-select: need exactly one -c argument; use plain psql for interactive/file mode')
    exit 1
}

$body = $sql.Trim()
if ($body.EndsWith(';')) { $body = $body.Substring(0, $body.Length - 1) }
if ($body.Contains(';')) {
    [Console]::Error.WriteLine("psql-select: blocked -- multiple statements (';') not allowed. Use plain psql.")
    exit 1
}

$first = ($body.ToUpperInvariant() -split '[\s(]', 2)[0]
if ($first -cnotmatch '^(SELECT|EXPLAIN|SHOW|WITH)$') {
    [Console]::Error.WriteLine("psql-select: blocked -- SQL starts with '$first', not a read-only statement. Use plain psql.")
    exit 1
}

$upper = $body.ToUpperInvariant()
foreach ($bad in 'SET_CONFIG', 'PG_READ_', 'PG_LS_', 'PG_STAT_FILE', 'PG_TERMINATE_BACKEND', 'PG_CANCEL_BACKEND', 'PG_RELOAD_CONF',
                 'PG_ROTATE_LOGFILE', 'PG_SWITCH_WAL', 'PG_PROMOTE', 'LO_IMPORT', 'LO_EXPORT', 'DBLINK') {
    if ($upper.Contains($bad)) {
        Stop-Blocked "function that can change settings, read server files, reach other servers or end sessions ($bad). Use plain psql."
    }
}

$ro = '-c default_transaction_read_only=on'
$env:PGOPTIONS = if ($env:PGOPTIONS) { $env:PGOPTIONS + ' ' + $ro } else { $ro }
Import-Module AgentCommon -Force -ErrorAction SilentlyContinue
if (-not (Get-Module AgentCommon)) { Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/Common.psm1') -Force }
$native = Format-NativeArgs (@('-X') + $a)
& psql @native
exit $LASTEXITCODE
