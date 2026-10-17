#!/usr/bin/env bash
[ -z "$BASH_VERSION" ] && exec bash "$0" "$@"
#
# save-claude-config.sh
# Copies ~/.claude/ config INTO the repo's claude/ (local -> repo).
# Refreshes ONLY the paths listed in claude/MANIFEST — an explicit,
# hand-maintained list, not derived from git state at run time.
# To add a genuinely NEW file to the shared config: copy it in, add a line
# to MANIFEST, and `git add` both the file and MANIFEST. This script only
# updates what MANIFEST already lists — a local-only file never leaks in
# just because it happens to sit in ~/.claude/skills or ~/.claude/agents.
# Always overwrites. Uses plain cp (no rsync). No rm -rf — never deletes
# anything in claude/.
#
# This script lives inside claude/, so repo root = parent dir.
#
# settings.json is profile-specific: ~/.claude/settings.json -> settings.<profile>.json.
#
# Usage: ./save-claude-config.sh [admin|sandbox]
#   admin   regular user with admin rights
#   sandbox low-privilege / sandboxed user
#   No argument: reuse the profile last synced on this machine (~/.claude/.profile), else admin.
#   Repo root is inferred as one level up from this script (claude/..);
#   override with REPO_DIR=<path>.

set -euo pipefail

PROFILE="${1:-$(cat "${HOME}/.claude/.profile" 2>/dev/null || echo admin)}"
case "$PROFILE" in
  admin|sandbox) ;;
  *) echo "Error: profile must be 'admin' or 'sandbox', got: $PROFILE" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(dirname "$SCRIPT_DIR")}"
DEST_DIR="${REPO_DIR}/claude"
SRC_DIR="${HOME}/.claude"
MANIFEST="${DEST_DIR}/MANIFEST"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Error: source dir not found: $SRC_DIR" >&2
  exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
  echo "Error: manifest not found: $MANIFEST" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

if [[ ! -f "${SRC_DIR}/settings.json" ]]; then
  echo "Error: settings not found: ${SRC_DIR}/settings.json" >&2
  exit 1
fi

echo "Saving (per MANIFEST, profile: ${PROFILE}): $SRC_DIR  ->  $DEST_DIR"

COUNT=0
SKIPPED=0
while IFS= read -r rel; do
  [[ -z "$rel" || "$rel" == \#* ]] && continue
  if [[ -f "${SRC_DIR}/${rel}" ]]; then
    mkdir -p "${DEST_DIR}/$(dirname "$rel")"
    cp -p "${SRC_DIR}/${rel}" "${DEST_DIR}/${rel}"
    COUNT=$((COUNT + 1))
  else
    echo "  skip (in MANIFEST but not found locally): $rel"
    SKIPPED=$((SKIPPED + 1))
  fi
done < "$MANIFEST"

sed "s|${REPO_DIR}|@@REPO_DIR@@|g" "${SRC_DIR}/settings.json" | jq -S . > "${DEST_DIR}/settings.${PROFILE}.json"
COUNT=$((COUNT + 1))

echo "Saved ${COUNT} file(s), ${SKIPPED} listed-but-missing."

# Informational only: local skill/agent dirs not covered by MANIFEST.
# Never copied in — surfaced so a local-only addition doesn't go unnoticed,
# and so it's obvious it needs an explicit MANIFEST line + git add to share.
MANIFEST_SKILL_DIRS=$(grep -E '^skills/' "$MANIFEST" | sed -E 's|^skills/([^/]+)/.*|\1|' | sort -u)
MANIFEST_AGENT_NAMES=$(grep -E '^agents/' "$MANIFEST" | sed -E 's|^agents/(.+)\.md$|\1|' | sort -u)

LOCAL_ONLY_SKILLS=$(comm -23 <(ls "${SRC_DIR}/skills" 2>/dev/null | sort -u) <(echo "$MANIFEST_SKILL_DIRS"))
LOCAL_ONLY_AGENTS=$(comm -23 <(ls "${SRC_DIR}/agents" 2>/dev/null | sed 's|\.md$||' | sort -u) <(echo "$MANIFEST_AGENT_NAMES"))

[[ -n "$LOCAL_ONLY_SKILLS" ]] && echo "Local-only skills (not in MANIFEST, not saved): $(echo "$LOCAL_ONLY_SKILLS" | tr '\n' ' ')"
[[ -n "$LOCAL_ONLY_AGENTS" ]] && echo "Local-only agents (not in MANIFEST, not saved): $(echo "$LOCAL_ONLY_AGENTS" | tr '\n' ' ')"

echo "Done."
echo "Review changes with: cd $REPO_DIR && git status claude/"
echo "New file to add to the shared config? cp it in, add a line to MANIFEST, then: git add claude/..."
