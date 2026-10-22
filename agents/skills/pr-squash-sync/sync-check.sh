#!/usr/bin/env bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
# Read-only sync check in one call: fetch, branch, status, ahead/behind, tree diff vs
# origin/<default>, last commits, PR states for the branch.
# Usage: sync-check.sh [default-branch]   (default: main)
set -uo pipefail

d="${1:-main}"
if ! [[ "$d" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "ERROR: invalid branch name: $d"
  exit 2
fi

git fetch origin "$d" 2>&1 | tail -2
branch=$(git branch --show-current)

echo "== branch: ${branch:-(detached)}"
echo "== status (must be clean)"
st=$(git status --short)
echo "${st:-clean}"
echo "== HEAD...origin/$d (ahead<TAB>behind)"
git rev-list --left-right --count "HEAD...origin/$d"
echo "== tree diff HEAD vs origin/$d"
df=$(git diff --stat HEAD "origin/$d")
echo "${df:-empty (identical tree: squash-merged or no changes)}"
echo "== log"
git log --oneline -3
if [ -n "$branch" ] && command -v gh >/dev/null 2>&1; then
  echo "== PRs for $branch"
  gh pr list --head "$branch" --state all --limit 5 --json number,state
fi
