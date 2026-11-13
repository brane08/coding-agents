#!/usr/bin/env bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
#
# uninstall-claude-config.sh
# Rolls back sync-claude-config.sh: deletes the files listed in claude/MANIFEST plus settings.json and
# .profile from ~/.claude, then prunes directories that become empty. Local-only files, state/ and
# backups/ are never touched.
#
# Usage: ./uninstall-claude-config.sh [--restore] [--dry-run]
#   --restore  afterwards copy back the newest ~/.claude/backups/<epoch-minute>/ (what the last sync replaced)
#   --dry-run  list what would happen, change nothing
#   Repo root is one level up from this script; override with REPO_DIR=<path>.

set -euo pipefail

RESTORE=0
DRY=0
for a in "$@"; do
  case "$a" in
    --restore) RESTORE=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "Error: unknown argument: $a" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(dirname "$SCRIPT_DIR")}"
MANIFEST="${REPO_DIR}/claude/MANIFEST"
DEST_DIR="${HOME}/.claude"

if [[ ! -f "$MANIFEST" ]]; then echo "Error: manifest not found: $MANIFEST" >&2; exit 1; fi
if [[ ! -d "$DEST_DIR" ]]; then echo "Nothing to remove: $DEST_DIR does not exist."; exit 0; fi

COUNT=0
DIRS=()
remove_rel() {
  local rel="$1" f="${DEST_DIR}/$1"
  [[ -f "$f" ]] || return 0
  COUNT=$((COUNT + 1))
  if [[ "$DRY" = 1 ]]; then echo "  would remove: $f"; return 0; fi
  rm -f -- "$f"
  DIRS+=("$(dirname "$f")")
}

while IFS= read -r rel; do
  [[ -z "$rel" || "$rel" == \#* ]] && continue
  remove_rel "$rel"
done < "$MANIFEST"
remove_rel settings.json
remove_rel .profile

if [[ "$DRY" = 1 ]]; then
  echo "Dry run: ${COUNT} file(s) would be removed from ${DEST_DIR}"
elif [[ "${#DIRS[@]}" -gt 0 ]]; then
  while IFS= read -r d; do
    while [[ "$d" != "$DEST_DIR" && "$d" == "$DEST_DIR"/* ]]; do
      rmdir -- "$d" 2>/dev/null || break
      d="$(dirname "$d")"
    done
  done < <(printf '%s\n' "${DIRS[@]}" | sort -u | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
fi
[[ "$DRY" = 1 ]] || echo "Removed ${COUNT} file(s) from ${DEST_DIR}"

if [[ "$RESTORE" = 1 ]]; then
  BACKUP_ROOT="${DEST_DIR}/backups"
  LATEST=""
  if [[ -d "$BACKUP_ROOT" ]]; then
    LATEST="$(ls -1 "$BACKUP_ROOT" 2>/dev/null | grep -E '^[0-9]+$' | sort -rn | head -n 1 || true)"
  fi
  if [[ -z "$LATEST" ]]; then echo "No backup found to restore."; exit 0; fi
  BASE="${BACKUP_ROOT}/${LATEST}"
  RESTORED=0
  while IFS= read -r f; do
    rel="${f#"$BASE"/}"
    RESTORED=$((RESTORED + 1))
    if [[ "$DRY" = 1 ]]; then echo "  would restore: ${DEST_DIR}/${rel}"; continue; fi
    mkdir -p "${DEST_DIR}/$(dirname "$rel")"
    cp -p "$f" "${DEST_DIR}/${rel}"
  done < <(find "$BASE" -type f)
  if [[ "$DRY" = 1 ]]; then echo "Dry run: ${RESTORED} file(s) would be restored from ${LATEST}"; else echo "Restored ${RESTORED} file(s) from backups/${LATEST}"; fi
fi
