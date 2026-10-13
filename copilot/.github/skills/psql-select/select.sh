#!/usr/bin/env zsh
# Auto-approved wrapper for read-only psql queries.
# Allows SELECT, EXPLAIN, SHOW, WITH.
# Exits 1 (blocked) for anything else.

sql=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-c" ]]; then
    sql="$arg"
    break
  fi
  prev="$arg"
done

if [[ -z "$sql" ]]; then
  echo "psql-select: no -c argument found; use plain psql for interactive/file mode" >&2
  exit 1
fi

first_word=$(echo "$sql" | sed 's/^[[:space:]]*//' | awk '{print toupper($1)}')

case "$first_word" in
  SELECT|EXPLAIN|SHOW|WITH)
    exec psql "$@"
    ;;
  *)
    echo "psql-select: blocked — SQL starts with '$first_word', not a read-only statement. Use plain psql." >&2
    exit 1
    ;;
esac
