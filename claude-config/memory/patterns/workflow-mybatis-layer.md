# Workflow MyBatis Data Layer Pattern

## Intent
Keep workflow persistence portable and decoupled from the domain ORM so the workflow module can split into its own service with minimal refactoring.

## Layers

| Data | Technology | Owner |
|------|-----------|-------|
| Domain entities (Student, Grade, etc.) | Hibernate + GenericRepository | data-hibernate module |
| Workflow engine tables (COPPER_*) | Copper-managed | hands off — no Java mapping |
| Workflow state (workflow_state) | MyBatis mapper interfaces | mono-quarkus/workflow/mappers |

## Why MyBatis for workflow infra (alternatives considered)

- **Spring Data JDBC** — Spring-container-dependent; not usable without Spring compatibility layer. Ruled out.
- **Quarkus Panache / Hibernate entity** — CDI + JPA underneath; Copper threads not CDI-managed, `@RequestScoped` proxies die mid-workflow. Ruled out.
- **Vert.x reactive SQL client** — async/reactive, mismatched with Copper's synchronous `wait()` model. Ruled out.
- **JOOQ** — good alternative if schema evolves frequently. Heavier: requires code-gen step. Overkill for 2–3 stable workflow tables.
- **MyBatis** — framework-neutral (`SqlSessionFactory` from plain `DataSource`), mapper interfaces are plain Java. Best fit. ✓

## Structure

```
workflow-core/
  src/main/java/.../workflow/
    data/          ← POJOs for workflow state rows (no @Entity)
    events/        ← WorkflowOutcomeEvent record (Serializable)
    spi/
      WorkflowStateService.java   ← recordStep / completeStep / getCurrentStep
      WorkflowEventPublisher.java ← publish(WorkflowOutcomeEvent)

mono-quarkus/
  pom.xml          ← org.mybatis:mybatis (plain jar, NOT quarkus-mybatis)
  src/main/java/.../workflow/
    mappers/
      WorkflowStateMapper.java    ← @Select/@Insert/@Update annotated interface
    infra/
      MyBatisProducer.java        ← @ApplicationScoped CDI producer for SqlSessionFactory
      WorkflowStateServiceImpl.java
      WorkflowEventPublisherImpl.java
      WorkflowOutcomeConsumer.java
```

## Why plain mybatis jar, NOT quarkus-mybatis

`quarkus-mybatis 2.2.1` uses class-based `MyBatisRuntimeConfig`, but Quarkus 3.x requires `@ConfigMapping` on an interface. The extension fails to start. Use plain `org.mybatis:mybatis` + manual CDI producer instead — same functionality, zero extension version coupling.

```xml
<!-- mono-quarkus/pom.xml — use plain jar -->
<dependency>
    <groupId>org.mybatis</groupId>
    <artifactId>mybatis</artifactId>
    <version>3.5.16</version>
</dependency>
```

## CDI SqlSessionFactory producer

```java
@ApplicationScoped
public class MyBatisProducer {
    @Inject DataSource dataSource;   // Agroal — same pool as Hibernate
    private SqlSessionFactory sqlSessionFactory;

    @PostConstruct
    void init() {
        JdbcTransactionFactory txFactory = new JdbcTransactionFactory();
        Environment env = new Environment("workflow", txFactory, dataSource);
        Configuration config = new Configuration(env);
        config.addMapper(WorkflowStateMapper.class);   // register each mapper
        sqlSessionFactory = new SqlSessionFactoryBuilder().build(config);
    }

    @Produces @ApplicationScoped
    SqlSessionFactory sqlSessionFactory() { return sqlSessionFactory; }
}
```

## Mapper interface (no @Mapper needed — registered programmatically)

```java
public interface WorkflowStateMapper {
    @Select("SELECT id, workflow_id, step_name, corr_id, status, result_payload, created_at, updated_at " +
            "FROM workflow_state WHERE workflow_id = #{workflowId} AND step_name = #{stepName}")
    @Results(id = "workflowStateMap", value = {
        @Result(property = "workflowId", column = "workflow_id"),
        @Result(property = "stepName",   column = "step_name"),
        @Result(property = "corrId",     column = "corr_id"),
        @Result(property = "createdAt",  column = "created_at"),
        @Result(property = "updatedAt",  column = "updated_at"),
        @Result(property = "resultPayload", column = "result_payload")
    })
    WorkflowStateRow findByWorkflowAndStep(@Param("workflowId") String workflowId,
                                           @Param("stepName") String stepName);

    @Insert("INSERT INTO workflow_state (workflow_id, step_name, corr_id, status, created_at) " +
            "VALUES (#{workflowId}, #{stepName}, #{corrId}, #{status}, NOW())")
    void insert(WorkflowStateRow row);

    @Update("UPDATE workflow_state SET status = #{status}, result_payload = #{resultPayload}, " +
            "updated_at = NOW() WHERE workflow_id = #{workflowId} AND step_name = #{stepName}")
    void updateStatusWithPayload(@Param("workflowId") String workflowId,
                                 @Param("stepName") String stepName,
                                 @Param("status") String status,
                                 @Param("resultPayload") String resultPayload);
}
```

## Service usage pattern (autocommit session per method)

```java
@ApplicationScoped
public class WorkflowStateServiceImpl implements WorkflowStateService {
    @Inject SqlSessionFactory sqlSessionFactory;

    @Override
    public void recordStep(String workflowId, String stepName, String corrId) {
        try (SqlSession session = sqlSessionFactory.openSession(true)) {  // autocommit=true
            WorkflowStateMapper mapper = session.getMapper(WorkflowStateMapper.class);
            // ... insert or upsert
        }
        fanOutNotification(workflowId, stepName);
    }
}
```

`openSession(true)` = autocommit. No explicit `session.commit()` needed. Use `openSession()` (no arg) for read-only queries.

## result_payload column

`workflow_state.result_payload TEXT` stores the outcome type constant (e.g. `"ADMISSION_COMPLETED"`). Enables manual replay identification — query `result_payload IS NOT NULL` to find completed steps that may need domain reprocessing on crash recovery.

Migration: `ALTER TABLE workflow_state ADD COLUMN IF NOT EXISTS result_payload TEXT;`

## Portability checklist when extracting workflow service

- [ ] Copy workflow-core module (data POJOs, events, SPI interfaces)
- [ ] Copy mapper interfaces to new service
- [ ] Add `org.mybatis:mybatis` to new service pom
- [ ] Wire `MyBatisProducer` CDI producer
- [ ] No Hibernate entities needed — pure SQL via MyBatis
- [ ] Copper engine config moves as-is
