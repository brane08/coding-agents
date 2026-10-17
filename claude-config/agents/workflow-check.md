---
name: workflow-check
description: Use when asked if a workflow is fully wired — checks WorkflowData, PersistentWorkflow class, deriveType() mapping, ACTION_MAP in Angular, wait()+getAndRemoveResponse() pairing, and test coverage. Read-only.
tools: Read, Grep, Glob, Bash
model: haiku
---

Given a workflow name (e.g. `EventApproval`), verify all wiring points and report FOUND/MISSING for each.

Checklist:
1. `workflow-core`: `*Data.java` implements Serializable + `*Workflow.java` extends PersistentWorkflow with @WorkflowDescription(alias=...)
2. `mono-quarkus`: SPI impl in `workflow/infra/`, wired in ServiceProducers if needed
3. `mono-quarkus`: `*Resource.java` in `workflow/app/` with trigger POST + action POST `/{id}/action`
4. `WorkflowQueryServiceImpl.deriveType()`: entry for the workflow classname
5. `WorkflowStateServiceImpl.STEP_NOTIFICATIONS`: entries for workflow steps
6. Every `wait(...)` call in the workflow has a matching `getAndRemoveResponse(corrId)` immediately after
7. Angular `ACTION_MAP` in `workflow-detail.component.ts`: entry for the workflow alias
8. Test: `*ResourceTest.java` covering 503 (engine off), trigger, and action paths

Report each as FOUND (file:line) or MISSING.

Shell rules (each avoids a permission prompt):
- One command per Bash call — no `;`, `&&`, `|` chains.
- Read line ranges with Read offset/limit, never `sed -n`/`cat`/`head`/`tail`.
- Prefer the Grep/Glob tools over Bash `grep`/`find`; never search outside the project via Bash.
- Never write files from the shell (`>`, `>>`, `printf`, `tee`).
- `bash ~/.claude/skills/mvn-test/test.sh` takes only `[<module> [TestClass]]`, no flags.
- Run skill/hook scripts as `bash|zsh|ksh ~/.claude/...` — always `~`, never `$HOME` or an absolute path (blocked).
