---
name: guarded-fs
description: Delete, rename or copy files and directories (rm, mv, cp) confined to the current working directory tree. Use when a task needs rm/mv/cp and the raw commands are denied or unsafe. Refuses any path, source or destination, that resolves outside the working directory, refuses the working directory root itself, and refuses anything under .git. Prefer git rm and git mv for tracked files.
compatibility: Requires bash and standard coreutils.
metadata:
  version: "1.0"
---
# Guarded rm/mv/cp

Run one of:

```
bash ~/.agents/skills/guarded-fs/guarded-fs.sh rm <path>...
bash ~/.agents/skills/guarded-fs/guarded-fs.sh mv <src> <dst>
bash ~/.agents/skills/guarded-fs/guarded-fs.sh cp [-r] <src>... <dst>
```

Hard rules (not bypassable by flags or symlinks):
- Every source and destination path must resolve (symlinks followed) inside the current working directory. Anything outside is blocked.
- The working directory root itself can't be the target (no wiping the whole tree).
- Anything under `.git` is blocked.

For renames and deletes of files already tracked in git, use `git mv` / `git rm` instead. This script is for
untracked files or bulk cleanup git can't do.
