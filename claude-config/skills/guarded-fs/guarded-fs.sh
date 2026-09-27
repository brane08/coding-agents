#!/usr/bin/env bash
# Guarded rm/mv/cp — hard-confined to the current working directory tree.
# Refuses any source/destination that resolves (symlinks included) outside
# the working dir, refuses the working dir root itself, refuses .git.
#
# Usage:
#   guarded-fs.sh rm <path>...
#   guarded-fs.sh mv <src> <dst>
#   guarded-fs.sh cp [-r] <src>... <dst>
set -euo pipefail

root="$(pwd -P)"

resolve() {
  local p="$1" dir base
  if [[ -e "$p" ]]; then
    dir=$(cd "$(dirname "$p")" && pwd -P)
    base=$(basename "$p")
    printf '%s/%s\n' "$dir" "$base"
  else
    dir=$(dirname "$p")
    base=$(basename "$p")
    if [[ -d "$dir" ]]; then
      printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
    else
      echo "__NOPARENT__"
    fi
  fi
}

check_inside() {
  local resolved="$1" label="$2"
  if [[ "$resolved" == "__NOPARENT__" ]]; then
    echo "guarded-fs: blocked — parent directory of '$label' does not exist" >&2
    exit 1
  fi
  if [[ "$resolved" != "$root" && "$resolved" != "$root"/* ]]; then
    echo "guarded-fs: blocked — '$label' resolves to '$resolved', outside working dir '$root'" >&2
    exit 1
  fi
  if [[ "$resolved" == "$root" ]]; then
    echo "guarded-fs: blocked — refusing to operate on the working dir root itself" >&2
    exit 1
  fi
  case "$resolved" in
    */.git|*/.git/*)
      echo "guarded-fs: blocked — refusing to touch .git ('$resolved')" >&2
      exit 1
      ;;
  esac
}

cmd="${1:-}"
shift || true

case "$cmd" in
  rm)
    [[ $# -ge 1 ]] || { echo "usage: guarded-fs.sh rm <path>..." >&2; exit 1; }
    for p in "$@"; do
      r=$(resolve "$p")
      check_inside "$r" "$p"
    done
    exec rm -rf -- "$@"
    ;;
  mv)
    [[ $# -eq 2 ]] || { echo "usage: guarded-fs.sh mv <src> <dst>" >&2; exit 1; }
    src_r=$(resolve "$1")
    dst_r=$(resolve "$2")
    check_inside "$src_r" "$1"
    check_inside "$dst_r" "$2"
    exec mv -- "$1" "$2"
    ;;
  cp)
    args=("$@")
    n=${#args[@]}
    [[ $n -ge 2 ]] || { echo "usage: guarded-fs.sh cp [-r] <src>... <dst>" >&2; exit 1; }
    dst="${args[$((n-1))]}"
    for ((i=0; i<n-1; i++)); do
      p="${args[$i]}"
      [[ "$p" == -* ]] && continue
      r=$(resolve "$p")
      check_inside "$r" "$p"
    done
    dst_r=$(resolve "$dst")
    check_inside "$dst_r" "$dst"
    exec cp -- "$@"
    ;;
  *)
    echo "usage: guarded-fs.sh <rm|mv|cp> ..." >&2
    exit 1
    ;;
esac
