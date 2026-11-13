#!/usr/bin/env bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
# Rolls back the Unix install of copilot/ (INSTALL.md: a copy of copilot/ in ~/.copilot): removes the
# files copied there (instructions, skills, agents, memory), then prunes directories that become empty.
# Files you added are kept.
# Usage: bash copilot/uninstall.sh [dest] [--dry-run]
set -euo pipefail

DEST="${HOME}/.copilot"
DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    *) DEST="$a" ;;
  esac
done

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -d "$DEST" ]]; then echo "Nothing to remove: $DEST does not exist."; exit 0; fi

COUNT=0
DIRS=()
while IFS= read -r f; do
  rel="${f#"$SRC"/}"
  case "$rel" in
    INSTALL.md|*.snippet.json|install.ps1|uninstall.ps1|uninstall.sh) continue ;;
  esac
  target="${DEST}/${rel}"
  [[ -f "$target" ]] || continue
  COUNT=$((COUNT + 1))
  if [[ "$DRY" = 1 ]]; then echo "  would remove: $target"; continue; fi
  rm -f -- "$target"
  DIRS+=("$(dirname "$target")")
done < <(find "$SRC" -type f -not -path '*/node_modules/*')

if [[ "$DRY" = 1 ]]; then
  echo "Dry run: ${COUNT} file(s) would be removed from ${DEST}"
  exit 0
fi

if [[ "${#DIRS[@]}" -gt 0 ]]; then
  while IFS= read -r d; do
    while [[ "$d" != "$DEST" && "$d" == "$DEST"/* ]]; do
      rmdir -- "$d" 2>/dev/null || break
      d="$(dirname "$d")"
    done
  done < <(printf '%s\n' "${DIRS[@]}" | sort -u | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
fi
rmdir -- "$DEST" 2>/dev/null || true
echo "Removed ${COUNT} file(s) from ${DEST}"
echo 'VS Code: remove the entries you merged from copilot/vscode-settings.snippet.json by hand.'
