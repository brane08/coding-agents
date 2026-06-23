#!/usr/bin/env bash
#
# save-claude-config.sh
# Copies ~/.claude/ config INTO the repo's claude-config/ (local -> repo).
# Copies ONLY: settings.json, CLAUDE.md, skills/, agents/, memory/
# Nothing else is touched. Always overwrites (merges into existing dirs).
# Uses plain cp (no rsync). No rm -rf — never deletes anything in claude-config/.
#
# This script lives inside claude-config/, so repo root = parent dir.
#
# Usage: ./save-claude-config.sh [path-to-repo]
#   If path-to-repo is omitted, repo root is inferred as one level up
#   from this script's own location (i.e. claude-config/..).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:-$(dirname "$SCRIPT_DIR")}"
DEST_DIR="${REPO_DIR}/claude-config"
SRC_DIR="${HOME}/.claude"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Error: source dir not found: $SRC_DIR" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

echo "Saving: $SRC_DIR  ->  $DEST_DIR"

# Files: plain cp, overwrite
for f in settings.json CLAUDE.md; do
  if [[ -f "${SRC_DIR}/${f}" ]]; then
    cp -p "${SRC_DIR}/${f}" "${DEST_DIR}/${f}"
    echo "  saved file: $f"
  else
    echo "  skip (not found locally): $f"
  fi
done

# Folders: copy contents in, overwriting matching files, without deleting destination first
for d in skills agents memory; do
  if [[ -d "${SRC_DIR}/${d}" ]]; then
    mkdir -p "${DEST_DIR}/${d}"
    cp -rp "${SRC_DIR}/${d}/." "${DEST_DIR}/${d}/"
    echo "  saved dir:  $d/"
  else
    echo "  skip (not found locally): $d/"
  fi
done

echo "Done."
echo "Review changes with: cd $REPO_DIR && git status claude-config/"