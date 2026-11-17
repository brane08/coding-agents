---
name: quarkus-dev
description: Start Quarkus dev mode (mvn quarkus:dev) in the background with hot reload and report the PID, listening URL, Dev UI URL and any startup errors. Use when asked to start Quarkus, launch dev mode, start the app locally, or enable hot reload.
compatibility: Requires bash, Maven, lsof, and a project with the Quarkus Maven plugin.
metadata:
  version: "1.0"
---
# Quarkus Dev Mode

Run: `QUARKUS_PORT=8102 bash ~/.agents/skills/quarkus-dev/dev.sh`

App runs at: http://localhost:8102
Dev UI at: http://localhost:8102/q/dev

Runs `mvn quarkus:dev` in `$AGENT_PROJECT_DIR` (else the current directory); set
`AGENT_PROJECT_DIR=<abs>/mono-quarkus` rather than changing directory. A process already listening on the port is killed first.
Output goes to `<project>/.agents/logs/quarkus-dev.log` (self-ignoring dir).

Stale jars cause `NoSuchMethodError`: always do a full rebuild after module changes.

Report:
- PID
- Listening URL
- Dev UI URL
- Any startup errors from the log
