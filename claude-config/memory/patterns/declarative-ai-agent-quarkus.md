# Declarative AI agent as a separate Quarkus service

De-identified pattern for wiring an LLM-backed chat/tool-calling agent into a
larger Quarkus system without embedding LLM concerns in the main app.

## Isolate the agent in its own microservice

- Agent logic (prompt, tools, memory) lives in its own Quarkus module/service,
  not inside the main app. The main app talks to it over plain HTTP (blocking
  `HttpClient` is fine — no need for reactive/streaming unless the UI needs
  token-by-token output).
- The agent module depends on the same data-access module the main app uses
  (repositories), not on the main app itself — keeps the dependency direction
  one-way.
- Config-driven endpoint URL (`agent.url` or similar) with an env-specific
  override for tests (point it at a local mock server instead of the real
  service).

## LangChain4j `@RegisterAiService` — minimal-boilerplate declarative agent

- Define an interface, not an implementation:
  ```java
  @RegisterAiService(tools = MyTools.class,
      chatMemoryProviderSupplier = RegisterAiService.BeanChatMemoryProviderSupplier.class)
  public interface MyAssistant {
      @SystemMessage("You are ...")
      String chat(@MemoryId String sessionId, @UserMessage String message);
  }
  ```
- The Quarkus LangChain4j extension generates the implementation at build
  time — scans for `@Tool`-annotated methods on the declared tools class,
  wires memory from CDI, handles all native-image reflection metadata
  automatically. No manual reflection config needed.
- Backend model (Ollama, OpenAI, etc.) is pure config
  (`quarkus.langchain4j.<provider>.*`) — model id, base URL, timeout. Swap
  providers by changing config + one extension dependency, not code.

## Tools are ordinary CDI beans with `@Tool` methods

- Tool methods are plain public methods returning `String`, annotated
  `@Tool("description the model sees")`. No special interface — the
  framework discovers them by classpath scan on the declared tools class.
- Keep tool methods thin: call the domain repository, format a short text
  result. The model does not need structured JSON back — plain text summaries
  work better for chat-style responses.

## Thread request context into tools via a `@RequestScoped` bean

- Tools can't take extra parameters the model doesn't control (like the
  calling user's id/role) — inject a `@RequestScoped` context bean instead
  (e.g. `ToolContext { userId, role }`), populated by the REST resource at
  the top of the request, and have tool methods read it for authorization
  checks (e.g. a customer's "get my orders" tool must not let them fetch
  another user's orders).

## Conversation memory: swappable, session-keyed

- Implement `ChatMemoryProvider` as an `@ApplicationScoped` bean:
  `ConcurrentHashMap<sessionId, ChatMemory>`, lazily created via
  `computeIfAbsent`, each backed by a `MessageWindowChatMemory` capped at N
  messages. Trivial in-memory version is fine for a first pass — the
  interface is the reusable part; swapping in a DB-backed store later is a
  one-class change. Document clearly that in-memory memory does not survive
  a restart.

## Fail soft, everywhere

- Wrap the LLM call and any downstream repository/tool errors so a model
  timeout or backend outage returns a friendly fallback string
  ("Assistant unavailable, try again") instead of propagating a 500 to the
  chat UI. Do this at both the agent service boundary and the calling app's
  HTTP bridge (so a network failure between the two also degrades
  gracefully) — same message pattern, two layers.

## Testing

- Agent service unit tests: `@InjectMock` the generated AI-service interface
  (Mockito can stub it even though it has no hand-written implementation) and
  assert on the REST layer above it — no real LLM calls in tests.
- Calling-app integration tests: stand up a WireMock (or similar) server on
  the port the test config points `agent.url` at, stub the chat endpoint's
  JSON response, and exercise the full HTTP round trip through the calling
  app's bridge controller.
