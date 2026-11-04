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

sql=""
nc=0
args=("$@")
n=$#
i=0
while (( i < n )); do
  a="${args[i]}"
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

upper="${body^^}"
first_word="${upper%%[[:space:](]*}"

case "$first_word" in
  SELECT|EXPLAIN|SHOW|WITH)
    PGOPTIONS="${PGOPTIONS:+$PGOPTIONS }-c default_transaction_read_only=on" exec psql "$@"
    ;;
  *)
    echo "psql-select: blocked — SQL starts with '$first_word', not a read-only statement. Use plain psql." >&2
    exit 1
    ;;
esac
