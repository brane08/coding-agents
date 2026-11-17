# Spring Cloud Gateway Server WebMVC 5.0.3

## FilterFunctions

**Two Host-related methods:**
- `preserveHost()` → delegates to `preserveHostHeader()` (shortcut)
- `preserveHostHeader()` → wraps `BeforeFilterFunctions.preserveHostHeader()` as `HandlerFilterFunction`

**@Shortcut methods related to Host/Location:**
- `preserveHost()`
- `preserveHostHeader()`
- `setRequestHostHeader(String)`
- `rewriteLocationResponseHeader(String, String, String, String)`

## BeforeFilterFunctions.preserveHostHeader()

Sets attribute `MvcUtils.PRESERVE_HOST_HEADER_ATTRIBUTE` to `Boolean.TRUE` on the ServerRequest.
Bytecode: `MvcUtils.putAttribute(request, PRESERVE_HOST_HEADER_ATTRIBUTE, true); return request;`

## HttpHeadersFilter Implementations

Both registered in `GatewayServerMvcAutoConfiguration` and enabled by default:

### ForwardedRequestHeadersFilter (RFC 7239)
- **Headers added:** `Forwarded` header
- **Conditions:** 
  - `@ConditionalOnProperty(prefix="spring.cloud.gateway.server.webmvc", name="forwarded-request-headers-filter.enabled", matchIfMissing=true)`
- **Trusted proxies:** From `GatewayMvcProperties.getTrustedProxies()` (required)
- **Config:** Respects `isForwardedByEnabled()` flag

### XForwardedRequestHeadersFilter
- **Headers added:** X-Forwarded-For, X-Forwarded-Host, X-Forwarded-Port, X-Forwarded-Proto, X-Forwarded-Prefix
- **Conditions:**
  - `@ConditionalOnProperty(prefix="spring.cloud.gateway.server.webmvc", name="x-forwarded-request-headers-filter.enabled", matchIfMissing=true)`
  - `@Conditional(TrustedProxies$XForwardedTrustedProxiesCondition)` — requires non-empty trusted proxies
- **Properties:** `XForwardedRequestHeadersFilterProperties` with enabled flags per-header + append mode (for/host/port/proto/prefix)
- **Trusted proxies:** From `GatewayMvcProperties.getTrustedProxies()` (required)

**Default enabled:** Both filters enabled by default if `trustedProxies` is configured in `spring.cloud.gateway.server.webmvc`.
