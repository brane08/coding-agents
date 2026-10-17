#!/usr/bin/env zsh
# Auto-approved wrapper for read-only psql queries.
# Allows a single SELECT, EXPLAIN, SHOW or WITH statement via one -c.
# Exits 1 (blocked) for anything else; the server also enforces read-only.
[ -n "${ZSH_VERSION-}" ] || exec zsh "$0" "$@"

sql=""
nc=0
args=("$@")
i=1
while (( i <= $# )); do
  a="${args[i]}"
  case "$a" in
    -c)
      (( nc++ ))
      (( i++ ))
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
  (( i++ ))
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

first_word="${${(U)body}%%[[:space:](]*}"

case "$first_word" in
  SELECT|EXPLAIN|SHOW|WITH)
    PGOPTIONS="${PGOPTIONS:+$PGOPTIONS }-c default_transaction_read_only=on" exec psql "$@"
    ;;
  *)
    echo "psql-select: blocked — SQL starts with '$first_word', not a read-only statement. Use plain psql." >&2
    exit 1
    ;;
esac
