# Workflow Async Event Architecture Pattern

## Intent
Workflow threads must not make direct domain writes (Hibernate calls). Workflow state belongs to the workflow transaction; domain state changes belong to a separate domain transaction. Results are delivered via events/channels — not in-process direct calls from within the workflow.

## Architecture principle

```
Copper workflow thread (own transaction)
  │
  ├── workflowStateService.recordStep()  ← MyBatis, workflow_state table only
  ├── wait()                             ← Copper suspends
  ├── workflowStateService.completeStep() ← MyBatis, updates result_payload
  └── eventPublisher.publish(event)      ← fire-and-forget CDI async event
                                              │
                                              ▼
                               @ObservesAsync WorkflowOutcomeEvent
                               @Transactional WorkflowOutcomeConsumer
                                 └── domain service calls (Hibernate tx)
```

## Components

### WorkflowOutcomeEvent (workflow-core — no framework dependency)
```java
public record WorkflowOutcomeEvent(String workflowId, String outcomeType, Serializable data)
        implements Serializable {
    public static final String ENQUIRY_PROCEEDED = "ENQUIRY_PROCEEDED";
    public static final String ADMISSION_COMPLETED = "ADMISSION_COMPLETED";
    // ... one constant per outcome
}
```

### WorkflowEventPublisher SPI (workflow-core)
```java
public interface WorkflowEventPublisher {
    void publish(WorkflowOutcomeEvent event);
}
```

### WorkflowEventPublisherImpl (mono-quarkus — CDI)
```java
@ApplicationScoped
public class WorkflowEventPublisherImpl implements WorkflowEventPublisher {
    @Inject Event<WorkflowOutcomeEvent> cdiEvent;

    @Override
    public void publish(WorkflowOutcomeEvent event) {
        cdiEvent.fireAsync(event).exceptionally(ex -> {
            log.error("Async consumer failed wfId={} type={}", event.workflowId(), event.outcomeType(), ex);
            return null;
        });
    }
}
```

### WorkflowOutcomeConsumer (mono-quarkus — CDI)
```java
@ApplicationScoped
public class WorkflowOutcomeConsumer {
    @Inject AdmissionService admissionService;
    // ... inject all domain SPIs needed

    @Transactional
    public void onOutcome(@ObservesAsync WorkflowOutcomeEvent event) {
        dispatch(event);
    }

    private void dispatch(WorkflowOutcomeEvent e) {
        switch (e.outcomeType()) {
            case WorkflowOutcomeEvent.ADMISSION_COMPLETED -> {
                AdmissionData d = (AdmissionData) e.data();
                long parentId = admissionService.createParent(d);
                d.setParentId(parentId);
                long studentId = admissionService.createStudent(d);
                d.setStudentId(studentId);
                admissionService.enrollStudent(d);
            }
            // ...
            default -> log.warn("Unhandled outcome: {}", e.outcomeType());
        }
    }
}
```

### Workflow def pattern
```java
// In every workflow def — inject publisher, NOT domain service
private transient WorkflowEventPublisher eventPublisher;

@AutoWire
public void setEventPublisher(WorkflowEventPublisher e) { this.eventPublisher = e; }

// In main():
workflowStateService.completeStep(wfId, STEP_APPROVED, "COMPLETED", WorkflowOutcomeEvent.LEAVE_APPROVED);
eventPublisher.publish(new WorkflowOutcomeEvent(wfId, WorkflowOutcomeEvent.LEAVE_APPROVED, data));  // after completeStep: consumer must see the persisted result_payload
```

`CdiDependencyInjector` uses `CDI.current().select(type)` generically — automatically picks up `WorkflowEventPublisherImpl` for the `WorkflowEventPublisher` type. No explicit registration needed.

## Why CDI async events (not other options)

- **In-process sync call from workflow thread** — violates transaction boundary; Copper thread not CDI-managed so `@RequestScoped` proxies go inactive; direct Hibernate writes from workflow thread can create connection contention.
- **CDI `fireAsync()` + `@ObservesAsync`** — decouples workflow transaction from domain transaction; fire-and-forget from workflow thread; consumer runs in thread pool with full CDI context; `@Transactional` works correctly on consumer. ✓
- **Kafka/Artemis JMS** — correct choice for distributed systems or when durability of the event matters. When monolith splits, replace `WorkflowEventPublisherImpl` with a Kafka producer — workflow-core and consumer interfaces don't change.

## Swap path: CDI → Kafka

Only one file changes: `WorkflowEventPublisherImpl`. Replace `Event<WorkflowOutcomeEvent>.fireAsync()` with `KafkaProducer.send(topic, event)`. Consumer side: create a `@Incoming` Kafka consumer that calls the same `dispatch()` logic.

## Testing workflow defs

Mock `WorkflowEventPublisher` and assert `publish()` was called with the right outcome type:

```java
@Mock WorkflowEventPublisher eventPublisher;
// ...
workflow.setEventPublisher(eventPublisher);

// assert
verify(eventPublisher).publish(argThat(e -> WorkflowOutcomeEvent.LEAVE_APPROVED.equals(e.outcomeType())));
verify(workflowStateService).completeStep(eq(wfId), eq(STEP_APPROVED), eq("COMPLETED"), anyString());
```

## completeStep 4-arg overload

```java
// SPI
void completeStep(String workflowId, String stepName, String status, String outcomeType);

// Use 4-arg when the step has a domain outcome (stores in result_payload)
workflowStateService.completeStep(wfId, STEP_APPROVED, "COMPLETED", WorkflowOutcomeEvent.TC_APPROVED);

// Use 3-arg for intermediate steps with no domain outcome
workflowStateService.completeStep(wfId, STEP_REJECTED, status);
```
