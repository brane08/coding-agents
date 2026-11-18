# Hooks, denies and guards (what the harness enforces)

Read when a call is denied/prompted and you need to know why, or before editing hooks/settings.

- `cd <dir> &&` / `;` prefix is denied.
- Admin profile also denies the 7th consecutive lookup (Bash/Grep/Glob) with no Edit/Write/Agent
  between → use one `code-search`.
- Reminders (not denies): read-only psql, `git -C`, inline secrets.
- `git push` / `gh pr create` from a merged-PR branch is blocked → `pr-squash-sync` skill.
- Push, delete or force-push to `main`/`master`/the default branch/`release*` is denied by hook
  (`CLAUDE_PROTECTED_BRANCHES`, globs). Elsewhere `git push` and `--force-with-lease` need no
  prompt; plain `--force`/`-f`/`--force-if-includes`/`--tags` still ask. Amend (`git commit --amend`) is allowed.
- Writes outside the project are denied by hook (the session scratchpad passes the hook, but running
  a script from it prompts — use `<project>/.claude/scratch/`). `~/.claude` is an additional directory:
  reads, greps and writes need no prompt, except edits to `settings*.json` and `hooks/**`,
  which ask → use the sync script.
- Unreadable (Read tool and Bash cat/head/tail/grep): `.env`, `*.key`, `*.pem`,
  `application-prod.*`, `~/.kube`, `~/.netrc`, `~/.npmrc`, `~/.m2/settings.xml`.
- Denied Maven: `deploy`, `exec:java|exec`, `release:prepare|perform|rollback|branch|stage`.
- Denied shell: `find -exec/-delete/-fprint`, `sort -o`/`-uo`, `cat f > out`, `grep -R /abs/path`.
- Use `git switch` (allowed), not `git checkout` (asks on admin).
- rm/mv/cp denied (admin profile; sandbox: mv/cp ask, git push and git checkout allowed).
- Delegation hooks (`nudge-delegate`) only nudge; `chain-guard` blocks chained lookups.
