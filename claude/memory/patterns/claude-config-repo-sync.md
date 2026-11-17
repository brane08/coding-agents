# Claude config repo <-> ~/.claude sync

Covers: keeping `~/.claude` versioned in a git repo (`claude/` dir), merging live edits with pulled
changes, and renaming the dir. Permission details: `libs/claude-code-permissions.md`.

## Layout
- `claude/MANIFEST` = the only files copied. `settings.<profile>.json` is handled by the scripts, not listed.
- `sync-claude-config.sh [admin|sandbox]`: repo -> `~/.claude`, overwrites, substitutes `@@REPO_DIR@@`
  in settings with the real repo path. `save-claude-config.sh`: reverse, then `jq -S` sorts.
- Profile is remembered in `~/.claude/.profile`.
- Not tracked on purpose: `~/.claude/skills/synced` (vendor cache written by an external sync), state/, projects/.

## Merge routine (pull + live edits)
1. `sync-check.sh <default>`; if the branch's PR is merged, `git switch -c <new> origin/<default>`.
2. Diff live vs repo per MANIFEST path (normalise: replace `@@REPO_DIR@@`, compare `jq -S` of settings).
3. List live-only edits and port them into the repo copy BEFORE syncing. Never run `save` first:
   it overwrites newer repo files with older live ones.
4. Commit, `sync`, verify settings are sorted: `jq -S . f | diff - f` (empty = sorted).
5. Amending your own pushed branch: `git push --force-with-lease=<branch>:<old-sha>`.

## Renaming the directory (done once: `claude-config/` -> `claude/`)
- `git mv`, then rewrite refs. Keep script file names; replace only `claude-config` not preceded by
  `sync-`/`save-` (scratch script with a lookbehind regex, then `git grep -n <old>` to confirm leftovers).
- Touch points: `.gitignore` negations, scripts' `SRC_DIR`/`DEST_DIR`, settings allow rules and notes
  (`@@REPO_DIR@@/<dir>/…`), `CLAUDE.md`, `MANIFEST` comments, skill docs, `permissions.py` (regex derives the
  repo from the sync allow rule), `copilot/INSTALL.md`.
- Sync afterwards: it rewrites live allow rules to the new path. History and state logs keep the old name.

## Adding a note or file
- Add a `MANIFEST` line, `git add` the file; for a new skill dir add a `!claude/skills/<name>/` negation.
- Index new memory notes in `CLAUDE.md` (Libs/Patterns lists, sessions rule).
