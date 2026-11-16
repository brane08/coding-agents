#!/usr/bin/env bash
# Auto-approved wrapper for read-only psql queries.
# Allows a single SELECT, EXPLAIN, SHOW or WITH statement via one -c.
# Exits 1 (blocked) for anything else; the server also enforces read-only.
# Portable bash (works where zsh is not installed).
if [ -z "${BASH_VERSION-}" ]; then
  if command -v bash >/dev/null 2>&1; then exec bash "$0" "$@"; fi
  echo "psql-select: bash not found; install bash (this script is bash-syntax only)" >&2
  exit 127
fi

# Short form against the local Postgres: select.sh "<sql>" | select.sh <db> "<sql>"
# (host localhost, user postgres, db prore unless given, unaligned tuples-only output).
# The local Postgres is trusted: any database on it (prore, prore_test, pagila, sakila, ...)
# is fine to query from any project. Reads only; never point it at a remote or prod host.
if (( $# >= 1 )) && [[ "$1" != -* ]]; then
  case $# in
    1) set -- -h localhost -U postgres -d prore -A -t -c "$1" ;;
    2) set -- -h localhost -U postgres -d "$1" -A -t -c "$2" ;;
    *) echo "psql-select: usage: select.sh \"<sql>\" | select.sh <db> \"<sql>\"" >&2; exit 1 ;;
  esac
fi

block() { echo "psql-select: blocked — $1" >&2; exit 1; }
check_host() {
  case "$1" in
    localhost|127.0.0.1|::1|/*) ;;
    *) block "host '$1' is not local; this wrapper only queries the local Postgres. Use plain psql." ;;
  esac
}
check_db() {
  case "$1" in
    *=*|*://*) block "-d/--dbname must be a plain database name (no conninfo string or URI)." ;;
  esac
}

sql=""
nc=0
args=("$@")
n=$#
i=0
while (( i < n )); do
  a="${args[i]}"
  case "$a" in
    -h|--host) check_host "${args[i+1]-}" ;;
    --host=*) check_host "${a#--host=}" ;;
    -h?*) check_host "${a#-h}" ;;
    -d|--dbname) check_db "${args[i+1]-}" ;;
    --dbname=*) check_db "${a#--dbname=}" ;;
    -d?*) check_db "${a#-d}" ;;
  esac
  case "$a" in
    -c)
      nc=$(( nc + 1 ))
      i=$(( i + 1 ))
      sql="${args[i]-}"
      ;;
    -c?*|--command|--command=*|-f|-f?*|--file|--file=*)
      echo "psql-select: blocked — use a single '-c <sql>' (no --command/-f/--file/-c<sql>). Use plain psql." >&2
      exit 1
      ;;
    -[a-zA-Z]*c)
      echo "psql-select: blocked — combined short flags ending in -c; pass '-c' separately." >&2
      exit 1
      ;;
    -o|-o?*|--output|--output=*|-L|-L?*|--log-file|--log-file=*)
      echo "psql-select: blocked — -o/--output and -L/--log-file write to disk. Use plain psql." >&2
      exit 1
      ;;
  esac
  i=$(( i + 1 ))
done

if (( nc != 1 )) || [[ -z "$sql" ]]; then
  echo "psql-select: need exactly one -c argument; use plain psql for interactive/file mode" >&2
  exit 1
fi

trimmed="${sql#"${sql%%[![:space:]]*}"}"
trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
body="${trimmed%;}"

if [[ "$body" == *";"* ]]; then
  echo "psql-select: blocked — multiple statements (';') not allowed. Use plain psql." >&2
  exit 1
fi

upper=$(printf '%s' "$body" | tr '[:lower:]' '[:upper:]')
first_word="${upper%%[[:space:](]*}"

for bad in SET_CONFIG PG_READ_ PG_LS_ PG_STAT_FILE PG_TERMINATE_BACKEND PG_CANCEL_BACKEND PG_RELOAD_CONF \
           PG_ROTATE_LOGFILE PG_SWITCH_WAL PG_PROMOTE LO_IMPORT LO_EXPORT DBLINK; do
  if [[ "$upper" == *"$bad"* ]]; then
    echo "psql-select: blocked — function that can change settings, read server files, reach other servers or end sessions ($bad). Use plain psql." >&2
    exit 1
  fi
done

case "$first_word" in
  SELECT|EXPLAIN|SHOW|WITH)
    PGOPTIONS="${PGOPTIONS:+$PGOPTIONS }-c default_transaction_read_only=on" exec psql -X "$@"
    ;;
  *)
    echo "psql-select: blocked — SQL starts with '$first_word', not a read-only statement. Use plain psql." >&2
    exit 1
    ;;
esac
