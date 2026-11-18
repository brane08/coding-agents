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

protected=${CLAUDE_PROTECTED_BRANCHES:-main master release*}
default_branch=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
default_branch=${default_branch#origin/}
# Entries are shell globs (release* also covers release/1.0); globbing is off so they are never
# expanded against files in the working directory.
is_protected() {
  set -f
  for b in $protected $default_branch; do
    case "$1" in
      $b) set +f; return 0 ;;
    esac
  done
  set +f
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
# Command substitution, backticks and parentheses also start a new command: split on those too.
split_cmd=${cmd//\$\(/$'\n'}
printf '%s\n' "$split_cmd" | tr ';&|`()' '\n\n\n\n\n\n' | while IFS= read -r seg; do
  # shellcheck disable=SC2086
  set -f
  set -- $seg
  set +f
  # drop quotes and a leading ( or { so `git push origin "main"` / `(git push ...)` are seen plainly
  args=()
  for w in "$@"; do w=${w#[\(\{]}; w=${w//[\"\']/}; args+=("$w"); done
  set -- "${args[@]}"
  # skip VAR=x assignments, wrappers (env/command/exec/sudo/nohup/time + their flags) and `sh -c`
  while [ $# -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*) shift ;;
      env|command|exec|sudo|nohup|time)
        shift
        while [ $# -gt 0 ]; do
          case "$1" in
            -u|-g|-h|-p|-C|-D|-R|-T|-U|--user|--group) shift 2 ;;   # flag taking a value (sudo -u root, env -u NAME)
            -*|[A-Za-z_]*=*) shift ;;
            *) break ;;
          esac
        done ;;
      sh|bash|zsh|dash|*/sh|*/bash|*/zsh|*/dash) if [ "${2:-}" = "-c" ]; then shift 2; else break; fi ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || continue
  [ "${1##*/}" = "git" ] || continue
  shift
  set -- git "$@"

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

  # only the "push" subcommand counts (not `git stash push`, `git commit -m push`)
  [ "$(git_subcmd "${@:2}")" = "push" ] || continue

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
