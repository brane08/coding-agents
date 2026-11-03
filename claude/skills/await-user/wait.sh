#!/usr/bin/env bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
# End-of-loop wait: sleeps <seconds> (integer 1..120) and prints "waited N s".
# Usage: wait.sh <seconds>
set -euo pipefail

n="${1:-}"
case "$n" in
  ''|*[!0-9]*) echo "usage: wait.sh <seconds 1-120>" >&2; exit 2 ;;
esac
n=$((10#$n))
if [ "$n" -lt 1 ] || [ "$n" -gt 120 ]; then
  echo "usage: wait.sh <seconds 1-120>" >&2
  exit 2
fi

sleep "$n"
echo "waited $n s"
