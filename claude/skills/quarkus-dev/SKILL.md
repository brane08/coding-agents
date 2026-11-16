---
name: quarkus-dev
description: >
  Use when asked to start Quarkus, launch dev mode, start the app locally,
  or enable hot reload. Starts quarkus:dev in background.
---
# Quarkus Dev Mode

Run: bash ~/.claude/skills/quarkus-dev/dev.sh 8102   (port is optional, default 8080; `QUARKUS_PORT` also works)

App runs at: http://localhost:8102
Dev UI at:   http://localhost:8102/q/dev

Note: runs `mvn quarkus:dev` in `$CLAUDE_PROJECT_DIR` (else cwd); set `CLAUDE_PROJECT_DIR=<abs>/mono-quarkus` rather than `cd`.
An existing quarkus/maven process on the port is stopped first; any other process on the port aborts the run.
Stale JARs → NoSuchMethodError — `build.sh` (package) installs nothing to `~/.m2`, so rebuild changed modules with
`mvn install -DskipTests -pl <module> -am` (see mvn-build) before starting.

Report:
- PID
- Listening URL
- Dev UI URL
- Any startup errors from log
