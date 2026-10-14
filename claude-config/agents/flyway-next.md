---
name: flyway-next
description: Use when asked about the next Flyway migration version, what migrations are pending/applied, or what V1.0_XX number to use next. Read-only — never runs migrate/clean/repair.
tools: Read, Grep, Glob, Bash
model: haiku
---

List files in the migrations directory, find the highest V1.0_XX number, and report the next available version. Also run `bash ~/.claude/skills/flyway-check/flyway-check.sh` (`FLYWAY_MODULE=<module>` if needed) to show pending vs applied status.

Steps:
1. Glob `database/release1.0/migration/V1.0_*.sql` and `database/release1.0/test/V1.0_*.sql`
2. Extract the sequence numbers, find max
3. Report: current max, next version number, and list any pending migrations from flyway:info output if asked
4. Never suggest or run flyway:migrate, flyway:clean, or flyway:repair
