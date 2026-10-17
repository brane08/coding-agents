#!/usr/bin/env bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
# PreToolUse guard for Bash: refuse `git push` / `gh pr create` from a branch whose PR is
# already merged (stale branch). Cut a new branch from origin/<default> instead.
#
# Uses `gh pr list --head <branch> --state all` (API call, not the cached `gh pr view`).
# Allows when: detached HEAD, protected/default branch, an OPEN PR exists, no PR found,
# or gh/network is unavailable (fail open).

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

protected=${CLAUDE_PROTECTED_BRANCHES:-main master}

hit=0
pushed=""
while IFS= read -r seg; do
  # shellcheck disable=SC2086
  set -- $seg
  while [ $# -gt 0 ] && printf '%s' "$1" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*='; do shift; done
  case "${1:-}" in
    git)
      case " $* " in
        *" push "*)
          hit=1
          # first non-flag word after `push` is the remote, the next is the refspec
          seen=0; n=0
          for w in "$@"; do
            if [ "$seen" = 0 ]; then [ "$w" = push ] && seen=1; continue; fi
            case "$w" in -*) continue ;; esac
            n=$((n + 1))
            if [ "$n" = 2 ]; then w=${w#+}; pushed=${w##*:}; fi
          done ;;
      esac ;;
    gh)  case " $* " in *" pr create"*|*" pr  create"*) hit=1 ;; esac ;;
  esac
done <<EOF
$(printf '%s\n' "$cmd" | tr ';&|' '\n\n\n')
EOF
[ "$hit" = 1 ] || exit 0

command -v gh >/dev/null 2>&1 || exit 0
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
[ -n "$pushed" ] && [ "$pushed" != HEAD ] && branch=${pushed#refs/heads/}
[ -z "$branch" ] && exit 0
[ "$branch" = HEAD ] && exit 0
for b in $protected; do [ "$branch" = "$b" ] && exit 0; done

tmo=$(command -v timeout || command -v gtimeout || true)
states=$(${tmo:+$tmo 8} gh pr list --head "$branch" --state all --limit 5 --json state -q '.[].state' 2>/dev/null) || exit 0
printf '%s\n' "$states" | grep -q '^OPEN$' && exit 0
printf '%s\n' "$states" | grep -q '^MERGED$' || exit 0

reason="Branch '$branch' already has a merged PR. Cut a new branch from origin/<default> (git fetch origin <default>; git switch -c <new> origin/<default>) and carry the new commits over instead of pushing or opening a PR from the stale branch."
jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
