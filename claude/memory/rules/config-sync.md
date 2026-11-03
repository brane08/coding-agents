# Config sync (claude repo ↔ ~/.claude)

Read before syncing/saving config or tracking a new file.

- Repo → `~/.claude`: `bash <repo>/claude/sync-claude-config.sh [admin|sandbox]`
  (no arg → profile last synced here, per `~/.claude/.profile`, else `admin`; copies only
  `MANIFEST` paths, overwrites; `settings.<profile>.json` → `~/.claude/settings.json`).
- `~/.claude` → repo: `bash <repo>/claude/save-claude-config.sh [admin|sandbox]`
  (refreshes `MANIFEST` paths only; `settings.json` → `settings.<profile>.json`).
- Direction matters: each overwrites the other side. Author in the repo, then sync; if a file
  was edited in `~/.claude`, mirror it into the repo (or save) before syncing.
- New file to track → add a `MANIFEST` line; for a new skill dir also add a
  `!claude/skills/<name>/` negation to `.gitignore`; then `git add`. Scripts never add files.
- `settings.*.json` stay key-sorted (`jq -S`): `save` sorts automatically. After hand-editing a
  repo copy, verify with `jq -S . <file> | diff - <file>` (empty = sorted).
- No explicit reload step; settings are normally picked up live, else restart the session.
- See also `patterns/claude-config-repo-sync.md`.
