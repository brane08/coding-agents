# Git / PR workflow (full rules)

Read before any commit, push or PR.

- Before a scan or new work: `bash ~/.claude/skills/pr-squash-sync/sync-check.sh <default>`
  (one call: fetch, branch, status, ahead/behind, tree diff, last 3 commits, PR states);
  working tree clean. Current branch already squash-merged (empty tree diff vs
  origin/<default>) → new branch from `origin/<default>`, don't merge/rebase the stale one.
  Verify after switching with the same script.
- Before committing/pushing to an existing branch, check its PR isn't merged
  (`gh pr list --head <branch> --state all --json state`; `gh pr view` can be stale). If
  merged → `pr-squash-sync` skill (new branch from the latest default).
- Commit attribution is exactly one trailer, `Co-Authored-By: Claude <noreply@anthropic.com>` (injected by `attribution.commit` in settings; don't add it by hand). No `by Claude (...)`, no Claude-Session trailer, no URLs/session links, no 'Generated with Claude Code'. PR descriptions carry no attribution. When rewriting a commit (amend/squash), keep exactly one such trailer.
- Before opening a PR, squash to a single commit (`git merge-base HEAD origin/<default>`, then
  `git reset --soft <sha>` and recommit — don't ask first). A PR has 1–2 commits max; 2 only
  for independent changes that must be revertable separately. Re-check the commit count before
  every `gh pr create`/`git push` on a long-lived branch.
- Squashing an unpushed branch isn't amending published work. A "pr"/"squash pr" request is the
  go-ahead to squash: do it with no follow-up question, including amending your own pushed PR
  branch and `git push --force-with-lease`. Ask first only for a branch you didn't create or
  that others share; never force-push `main`/`master` or silently.
- The full test suite runs here, when preparing the PR (not during item work).
