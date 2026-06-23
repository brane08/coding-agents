---
name: flyway-check
description: >
  Use when asked about DB migrations, Flyway status, schema version, pending migrations, or schema drift.
---
# Flyway Status Check

Run: DB_URL=jdbc:postgresql://127.0.0.1:5432/prore DB_USER=postgres DB_PASS=postgres \
     bash ~/.claude/skills/flyway-check/flyway-check.sh

Must be run from htmx-quarkus/ (where pom.xml has flyway config).

Report: current schema version, count + names of pending migrations, any failures/checksum mismatches.
Never delegate flyway:migrate, flyway:clean, or flyway:repair to this skill.
