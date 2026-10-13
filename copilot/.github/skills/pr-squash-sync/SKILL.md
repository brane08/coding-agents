---
name: pr-squash-sync
description: Sync a branch with origin, squash it to one commit and push or open a PR, and handle the case where the branch's PR is already merged (cut a new branch from origin/<default>). Use for "pr", "squash and push", "pr was merged", "update then fork", or before any push / gh pr create.
---

Run each step as its own terminal command (no `cd`, no chains). Replace `<default>` with the repo's default branch (usually `main`).

1. **Sync check**
   - `git fetch origin <default>`
   - `git status --short` (must be clean; otherwise stop and report)
   - `git rev-list --left-right --count HEAD...origin/<default>`
   - `git branch --show-current`

2. **Is the branch's PR merged?**
   - `gh pr list --head <branch> --state all --limit 5 --json number,state`
   - `gh pr view <branch> --json state` can be stale; trust `gh pr list`/`gh api`.
   - OPEN → continue on this branch. MERGED (and none OPEN) → step 3. None → step 4.

3. **Merged → new branch from the latest default**
   - `git switch -c <new-branch> origin/<default>` (uncommitted edits carry over if the files match)
   - To move already-committed work: `git checkout <old-branch> -- <paths>` then commit. Never merge or rebase the stale branch.
   - Verify: `git branch --show-current`, `git log --oneline -3`.

4. **Squash** (one commit unless 2–3 are independently revertable)
   - Unpushed branch: `git merge-base HEAD origin/<default>` (own call), then `git reset --soft <sha>` and commit.
   - Already pushed/shared: ask before rewriting; use `git push --force-with-lease` only after the user agrees; never force-push `<default>`.

5. **Commit message / PR text**: no AI attribution, no session links, no "Generated with" line.

6. **Push / PR**
   - `git push -u origin <branch>`
   - `gh pr create --base <default> --title … --body …` (see `.github/copilot-instructions.md` for the PR rules)
   - Update an existing PR's text with `gh pr edit <n> --body-file <file>`.

7. **After merge**: `git fetch origin <default>`, `git switch <default>`, `git merge --ff-only origin/<default>`, then `git log --oneline -2`.

Never `git push` or `gh pr create` from a branch whose PR is already merged (step 2 → 3 first).
