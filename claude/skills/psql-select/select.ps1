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

$sql = ''
$nc = 0
for ($i = 0; $i -lt $a.Count; $i++) {
    $x = $a[$i]
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

$ro = '-c default_transaction_read_only=on'
$env:PGOPTIONS = if ($env:PGOPTIONS) { $env:PGOPTIONS + ' ' + $ro } else { $ro }
Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/Common.psm1') -Force
$native = Format-NativeArgs $a
& psql @native
exit $LASTEXITCODE
