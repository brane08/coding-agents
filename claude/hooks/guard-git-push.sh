#!/usr/bin/env bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
# PreToolUse guard: block force-pushing or deleting a protected branch.
#
# Pattern rules cannot express this. "git push --force* origin main*" misses
# `git push origin main --force`, bare `git push --force` while standing on main,
# `git push --force origin HEAD:main`, and `git push origin +main`. This resolves
# the actual target ref instead of matching on spelling.
#
# Also denies any push whose target is a protected branch or the default branch (including
# a plain `git push`/`git push origin` while standing on one) and `git branch -d/-D` of a
# protected branch or the current branch. A plain push from a feature branch passes.
#
# Protected branches: $CLAUDE_PROTECTED_BRANCHES (space separated), default "main master",
# plus origin's default branch (refs/remotes/origin/HEAD) when known.

input=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"guard-git-push: jq missing, cannot inspect the command"}}'
  exit 0
fi
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":%s}}' \
    "$1" "$(printf '%s' "$2" | jq -Rs .)"
}

protected=${CLAUDE_PROTECTED_BRANCHES:-main master}
default_branch=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
default_branch=${default_branch#origin/}
is_protected() {
  for b in $protected $default_branch; do [ "$1" = "$b" ] && return 0; done
  return 1
}

# First non-flag word after `git` (skips -C <dir>, -c <k=v> and other global flags).
git_subcmd() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -C|-c) shift 2 ;;
      -*) shift ;;
      *) printf '%s' "$1"; return ;;
    esac
  done
}

# A compound line may hold several commands; check each git push separately.
# Split on ; && || and newlines.
printf '%s\n' "$cmd" | tr ';&|' '\n\n\n' | while IFS= read -r seg; do
  # shellcheck disable=SC2086
  set -- $seg
  while [ $# -gt 0 ] && printf '%s' "$1" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*='; do shift; done
  [ "${1:-}" = "git" ] || continue

  # git branch -d/-D/--delete of a protected branch or the current branch
  if [ "$(git_subcmd "${@:2}")" = "branch" ]; then
    del=0
    names=""
    seen_branch=0
    for w in "$@"; do
      if [ "$seen_branch" = 0 ]; then
        [ "$w" = "branch" ] && seen_branch=1
        continue
      fi
      case "$w" in
        --delete) del=1 ;;
        --*) ;;
        -[!-]*) case "$w" in *[dD]*) del=1 ;; esac ;;
        *) names="$names $w" ;;
      esac
    done
    if [ "$del" = 1 ]; then
      cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || cur=""
      for t in $names; do
        if is_protected "$t" || { [ -n "$cur" ] && [ "$t" = "$cur" ]; }; then
          emit deny "Refusing to delete the branch '$t' (protected or currently checked out). Protected: $protected${default_branch:+ $default_branch}."
          exit 0
        fi
      done
    fi
    continue
  fi

  # find the "push" subcommand, skipping global flags like -C <dir>
  saw_push=0
  for w in "$@"; do
    [ "$w" = "push" ] && { saw_push=1; break; }
  done
  [ "$saw_push" = 1 ] || continue

  force=0
  delete=0
  refspecs=""
  seen_push=0
  for w in "$@"; do
    if [ "$seen_push" = 0 ]; then
      [ "$w" = "push" ] && seen_push=1
      continue
    fi
    case "$w" in
      --force|--force-with-lease|--force-with-lease=*|--force-if-includes)
        force=1 ;;
      --delete)
        delete=1 ;;
      -[!-]*)
        # combined short flags, e.g. -fu / -uf / -df
        case "$w" in *f*) force=1 ;; esac
        case "$w" in *d*) delete=1 ;; esac ;;
      --mirror)
        # rewrites every ref on the remote, protected ones included
        emit deny "git push --mirror can rewrite protected branches ($protected). Push an explicit refspec instead."
        exit 0 ;;
      -*) ;;                       # any other long flag
      *)  refspecs="$refspecs $w" ;;  # remote, then refspec(s)
    esac
  done

  # +ref is force syntax, e.g. `git push origin +main`
  for r in $refspecs; do
    case "$r" in
      +*) force=1 ;;
      :*) delete=1 ;;               # `git push origin :main` deletes the remote branch
    esac
  done

  # Resolve target branch names. First token after the flags is the remote;
  # anything after that is a refspec. With no refspec, the push targets the
  # current branch.
  targets=""
  n=0
  for r in $refspecs; do
    n=$((n + 1))
    [ "$n" = 1 ] && continue          # remote name
    r=${r#+}                          # strip force marker
    dst=${r##*:}                      # src:dst -> dst; bare ref -> itself
    [ "$dst" = HEAD ] && dst=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    targets="$targets $dst"
  done

  if [ -z "$(printf '%s' "$targets" | tr -d ' ')" ]; then
    cur=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || cur=""
    targets="$cur"
  fi

  for t in $targets; do
    t=${t#refs/heads/}
    if is_protected "$t"; then
      what="push to"
      [ "$force" = 1 ] && what="force-push"
      [ "$delete" = 1 ] && what="delete"
      emit deny "Refusing to $what the protected/default branch '$t'. Protected: $protected${default_branch:+ $default_branch}."
      exit 0
    fi
  done
done

exit 0
