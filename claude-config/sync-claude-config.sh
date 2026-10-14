#!/usr/bin/env bash
#
# sync-claude-config.sh
# Copies Claude Code config from repo's claude-config/ into ~/.claude/
# Copies ONLY the paths listed in claude-config/MANIFEST — an explicit,
# hand-maintained list, not derived from git state at run time. A file only
# moves if it's a line in MANIFEST, regardless of whether it happens to be
# git-tracked, staged, or dirty.
# Always overwrites. Uses plain cp (no rsync). No rm -rf — never deletes
# anything in ~/.claude/, including files ~/.claude/ has that MANIFEST
# doesn't list.
#
# This script lives inside claude-config/, so repo root = parent dir.
#
# settings.json is profile-specific: settings.<profile>.json -> ~/.claude/settings.json.
#
# Usage: ./sync-claude-config.sh [admin|sandbox]
#   admin   regular user with admin rights
#   sandbox low-privilege / sandboxed user
#   No argument: reuse the profile last synced on this machine (~/.claude/.profile), else admin.
#   Repo root is inferred as one level up from this script (claude-config/..);
#   override with REPO_DIR=<path>.

set -euo pipefail

PROFILE_MARKER="${HOME}/.claude/.profile"
PROFILE="${1:-$(cat "$PROFILE_MARKER" 2>/dev/null || echo admin)}"
case "$PROFILE" in
  admin|sandbox) ;;
  *) echo "Error: profile must be 'admin' or 'sandbox', got: $PROFILE" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(dirname "$SCRIPT_DIR")}"
SRC_DIR="${REPO_DIR}/claude-config"
DEST_DIR="${HOME}/.claude"
MANIFEST="${SRC_DIR}/MANIFEST"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Error: source dir not found: $SRC_DIR" >&2
  exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
  echo "Error: manifest not found: $MANIFEST" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

SETTINGS_SRC="${SRC_DIR}/settings.${PROFILE}.json"
if [[ ! -f "$SETTINGS_SRC" ]]; then
  echo "Error: settings profile not found: $SETTINGS_SRC" >&2
  exit 1
fi

echo "Syncing (per MANIFEST, profile: ${PROFILE}): $SRC_DIR  ->  $DEST_DIR"

COUNT=0
MISSING=0
while IFS= read -r rel; do
  [[ -z "$rel" || "$rel" == \#* ]] && continue
  if [[ -f "${SRC_DIR}/${rel}" ]]; then
    mkdir -p "${DEST_DIR}/$(dirname "$rel")"
    cp -p "${SRC_DIR}/${rel}" "${DEST_DIR}/${rel}"
    COUNT=$((COUNT + 1))
  else
    echo "  skip (in MANIFEST but missing from repo): $rel"
    MISSING=$((MISSING + 1))
  fi
done < "$MANIFEST"

cp -p "$SETTINGS_SRC" "${DEST_DIR}/settings.json"
printf '%s\n' "$PROFILE" > "$PROFILE_MARKER"
COUNT=$((COUNT + 1))

echo "Synced ${COUNT} file(s), ${MISSING} listed-but-missing."

# Informational only: local skill/agent dirs not covered by MANIFEST.
# Never touched — just surfaced so they're not silently invisible.
MANIFEST_SKILL_DIRS=$(grep -E '^skills/' "$MANIFEST" | sed -E 's|^skills/([^/]+)/.*|\1|' | sort -u)
MANIFEST_AGENT_NAMES=$(grep -E '^agents/' "$MANIFEST" | sed -E 's|^agents/(.+)\.md$|\1|' | sort -u)

LOCAL_ONLY_SKILLS=$(comm -23 <(ls "${DEST_DIR}/skills" 2>/dev/null | sort -u) <(echo "$MANIFEST_SKILL_DIRS"))
LOCAL_ONLY_AGENTS=$(comm -23 <(ls "${DEST_DIR}/agents" 2>/dev/null | sed 's|\.md$||' | sort -u) <(echo "$MANIFEST_AGENT_NAMES"))

[[ -n "$LOCAL_ONLY_SKILLS" ]] && echo "Local-only skills (not in MANIFEST, untouched): $(echo "$LOCAL_ONLY_SKILLS" | tr '\n' ' ')"
[[ -n "$LOCAL_ONLY_AGENTS" ]] && echo "Local-only agents (not in MANIFEST, untouched): $(echo "$LOCAL_ONLY_AGENTS" | tr '\n' ' ')"

echo "Done."
