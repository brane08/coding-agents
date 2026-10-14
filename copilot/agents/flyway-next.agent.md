---
description: Report the next Flyway migration version and which migrations are pending/applied (V1.0_XX numbering). Read-only — never runs migrate/clean/repair.
model: GPT-5.6 Luna
tools: ['read', 'search', 'execute']
---

List files in the migrations directory, find the highest V1.0_XX number, and report the next available version. Also run `mvn flyway:info` if needed to show pending vs applied status.

Steps:
1. Find `database/release1.0/migration/V1.0_*.sql` and `database/release1.0/test/V1.0_*.sql`
2. Extract the sequence numbers, find max
3. Report: current max, next version number, and list any pending migrations from flyway:info output if asked
4. Never suggest or run flyway:migrate, flyway:clean, or flyway:repair
