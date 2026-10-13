---
description: Check whether a workflow is fully wired — WorkflowData, PersistentWorkflow class, deriveType() mapping, ACTION_MAP in Angular, wait()+getAndRemoveResponse() pairing, and test coverage. Read-only.
model: GPT-5.6 Luna
tools: ['read', 'search', 'execute']
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
