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

# resolve <path> [follow]: physical path; with follow=1 an existing symlink is judged by its target
# (destinations: writing through a symlink lands at the target).
resolve() {
  local p="$1" follow="${2:-0}" dir base t n=0
  if [[ "$follow" = 1 ]]; then
    while [[ -L "$p" && $n -lt 10 ]]; do
      t=$(readlink "$p")
      case "$t" in
        /*) p="$t" ;;
        *)  p="$(dirname "$p")/$t" ;;
      esac
      n=$((n + 1))
    done
  fi
  if [[ -d "$p" && "$follow" = 1 ]]; then
    printf '%s\n' "$(cd "$p" && pwd -P)"
  elif [[ -e "$p" ]]; then
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
    dst_r=$(resolve "$2" 1)
    check_inside "$src_r" "$1"
    check_inside "$dst_r" "$2"
    if [[ -d "$2" ]]; then
      check_inside "$(resolve "$2/$(basename "$1")" 1)" "$2/$(basename "$1")"
    fi
    exec mv -- "$1" "$2"
    ;;
  cp)
    flags=()
    paths=()
    for a in "$@"; do
      case "$a" in
        -[rRpPfinavL]*|--recursive) flags+=("$a") ;;
        -*) echo "guarded-fs: blocked — unsupported cp flag '$a'" >&2; exit 1 ;;
        *) paths+=("$a") ;;
      esac
    done
    n=${#paths[@]}
    [[ $n -ge 2 ]] || { echo "usage: guarded-fs.sh cp [-r] <src>... <dst>" >&2; exit 1; }
    dst="${paths[$((n-1))]}"
    for ((i=0; i<n-1; i++)); do
      p="${paths[$i]}"
      r=$(resolve "$p")
      check_inside "$r" "$p"
      if [[ -d "$dst" ]]; then
        check_inside "$(resolve "$dst/$(basename "$p")" 1)" "$dst/$(basename "$p")"
      fi
    done
    dst_r=$(resolve "$dst" 1)
    check_inside "$dst_r" "$dst"
    exec cp ${flags[@]+"${flags[@]}"} -- "${paths[@]}"
    ;;
  *)
    echo "usage: guarded-fs.sh <rm|mv|cp> ..." >&2
    exit 1
    ;;
esac
