---
name: quarkus-dev
description: >
  Use when asked to start Quarkus, launch dev mode, start the app locally,
  or enable hot reload. Starts quarkus:dev in background.
---
# Quarkus Dev Mode

Run: QUARKUS_PORT=8102 bash ~/.claude/skills/quarkus-dev/dev.sh

App runs at: http://localhost:8102
Dev UI at:   http://localhost:8102/q/dev

Note: runs `mvn quarkus:dev` in `$CLAUDE_PROJECT_DIR` (else cwd); set `CLAUDE_PROJECT_DIR=<abs>/mono-quarkus` rather than `cd`.
Stale JARs → NoSuchMethodError — always full rebuild after module changes.

Report:
- PID
- Listening URL
- Dev UI URL
- Any startup errors from log
