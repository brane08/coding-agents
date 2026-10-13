---
applyTo: "**"
---
# Git / PR workflow
Applies to commit, push and PR tasks. Step-by-step: `.github/skills/pr-squash-sync/SKILL.md`.

- Before a codebase scan or new work: `git fetch origin <default>`, then `git rev-list --left-right --count HEAD...origin/<default>`. Working tree must be clean.
- Current branch's commits already squash-merged (empty tree diff vs `origin/<default>`) → `git switch -c <new> origin/<default>`; don't merge/rebase the stale branch. Otherwise merge/ff.
- Verify after switching: `git branch --show-current` and `git log --oneline -3`.
- Before committing/pushing to an existing branch, check its PR isn't merged (`gh pr list --head <branch> --state all --json number,state`; `gh pr view` can be stale). Merged → new branch from `origin/<default>`.
- Before opening a PR: squash to one commit (`git merge-base HEAD origin/<default>`, then `git reset --soft <sha>` and recommit). 2–3 commits only for independently revertable changes.
- Already pushed/shared branch → ask before rewriting; never force-push silently; never force-push the default branch.
- Re-check commit count before every `gh pr create`/`git push` on a long-lived branch.
- No AI/assistant attribution, session links or "Generated with …" in commit messages or PR bodies.
- Git worktrees: `git worktree add <path> -b <branch> origin/<default>` (pass the base explicitly); verify the branch afterwards.
- Plain `git …` from the repo (no `cd`, no `git -C` for the current repo).
