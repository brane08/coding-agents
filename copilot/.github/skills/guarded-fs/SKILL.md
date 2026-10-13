---
name: guarded-fs
description: >
  Use when a task needs to delete, rename, or copy files/dirs (rm/mv/cp)
  and raw rm/mv/cp are denied. Confines the operation to the current
  working directory tree — refuses any path (source or destination) that
  resolves outside it, refuses the working dir root itself, refuses .git.
---
# Guarded rm/mv/cp

Run one of:
  bash .github/skills/guarded-fs/guarded-fs.sh rm <path>...
  bash .github/skills/guarded-fs/guarded-fs.sh mv <src> <dst>
  bash .github/skills/guarded-fs/guarded-fs.sh cp [-r] <src>... <dst>

Hard rules (cannot be bypassed by flags or symlinks):
- Every source and destination path must resolve (symlinks followed) inside
  the current working directory. Anything outside is blocked, no exceptions.
- The working dir root itself can't be the target (no wiping the whole tree).
- Anything under .git is blocked.

For renames/deletes of files already tracked in git, prefer `git mv`/`git rm`
instead — this script is for untracked files or bulk cleanup git can't do.
