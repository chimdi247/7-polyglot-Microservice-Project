# observability/

Config and provisioning for the monitoring stack in `docker-compose.yml`:
OpenTelemetry Collector, Prometheus, Alertmanager, Grafana, Loki, Promtail,
and Tempo -- instrumenting all 7 polyglot services (Java, Go, Node.js,
Python, C#, Ruby, PHP).

## How telemetry flows

```text
each service ---- OTLP traces -----------------------------------> otel-collector --> Tempo
each service ---- native Prometheus client's own /metrics --------------------------> scraped by Prometheus directly (per service)

host ------------> node-exporter --------------------------------------------------> scraped by Prometheus

every container's stdout ------> Promtail (via Docker socket) ---------------------> Loki

Prometheus -- alert rules (alerts.yml) --> Alertmanager --> email
Prometheus, Loki, Tempo  ---- all three added as Grafana datasources, cross-linked
```

### Why metrics use each language's native Prometheus client, not OTel

With 7 different language runtimes, routing every service's metrics through
OpenTelemetry's own metric SDK/exporter would mean trusting 7 different
libraries' current auto-generated metric *names* to line up with what the
dashboards/alerts expect -- a real risk with no way to verify it without
actually running each service. Instead, every service exposes its own
`/metrics` endpoint directly via that language's standard Prometheus client
library, so the metric names are exact and under our control:

| Service | Language | Metrics library | Traces |
|---|---|---|---|
| auth-service | Java (Spring Boot) | Micrometer + `spring-boot-starter-actuator` (`/actuator/prometheus`) | OpenTelemetry Java agent (`-javaagent`, zero-code) |
| catalog-service | Go | `prometheus/client_golang` | `otelhttp` middleware (manual, ~10 lines -- Go has no bytecode-weaving agent) |
| inventory-service | Node.js | `prom-client` | `@opentelemetry/auto-instrumentations-node` via `NODE_OPTIONS=--require` (zero-code) |
| order-service | Python (FastAPI) | `prometheus-fastapi-instrumentator` | `opentelemetry-instrument` CLI wrapper (zero-code) |
| payment-service | C# (ASP.NET Core) | `prometheus-net.AspNetCore` | `OpenTelemetry.Instrumentation.AspNetCore`/`.Http` (manual registration, ~10 lines in `Program.cs`) |
| notification-service | Ruby (Sinatra) | `prometheus-client` (hand-wired before/after hooks) | `opentelemetry-instrumentation-sinatra`/`-pg` (small `OpenTelemetry::SDK.configure` block) |
| analytics-service | PHP | Hand-rolled, APCu-backed (see below) | **Not instrumented** -- see below |

Every trace-instrumentation setup is wrapped defensively (try/catch,
begin/rescue, or a nil-safe fallback depending on the language) so that if
OpenTelemetry fails to initialize for any reason, the service still starts
normally -- telemetry must never be able to break the actual app.

### analytics-service (PHP): metrics yes, traces no

Two things make PHP different from the other 6 services here:

1. **No persistent process state.** `php -S` (this service's dev server,
   see its Dockerfile) runs each request as a fresh script execution --
   unlike a long-running Node/Java/Go process, a plain PHP variable can't
   accumulate a counter across requests. `router.php` uses **APCu**
   (a PECL extension, installed in the Dockerfile) as shared memory that
   *does* persist across requests within the container, and hand-rolls the
   Prometheus text exposition format from it at `/metrics`.
2. **True zero-code trace auto-instrumentation needs a compiled PHP
   extension** (the `opentelemetry` PECL extension) whose exact build/
   configuration couldn't be verified without actually running it here --
   getting this wrong would risk breaking the container's PHP entirely, a
   worse outcome than simply not tracing this one service. So
   analytics-service has metrics and logs, but not traces. Since it's the
   read-only aggregator that calls the other 6 already-traced services, the
   overall request flow is still visible; only spans that would have
   originated *from* analytics-service itself are missing.

### Logs

`promtail` uses Docker service discovery (`docker_sd_configs`, via a
read-only mount of the Docker socket) to tail **every** container's
stdout/stderr into Loki -- all 7 services regardless of language, the
frontend, and every infra container.

### A metric-name caveat worth knowing (auth-service and payment-service)

- **auth-service (Java)**: uses Spring Boot Actuator/Micrometer's own
  metric name, `http_server_requests_seconds_count`, with an `outcome`
  label (`SUCCESS`/`CLIENT_ERROR`/`SERVER_ERROR`) rather than `status` --
  this is a long-stable, well-documented Spring Boot convention.
- **payment-service (C#)**: `prometheus-net.AspNetCore`'s `UseHttpMetrics()`
  exposes `http_request_duration_seconds_count` with a `code` label. This
  one is worth double-checking once the stack is running (Prometheus ->
  Graph -> search `http_request`) -- if the label name differs from what's
  in `payment-service.json`, it's a quick find-and-replace in that
  dashboard file.

All 5 other services (Go, Node, Python, Ruby, PHP) use the exact same
convention since that code was written for this project:
`http_requests_total{status="..."}` and `http_request_duration_seconds_bucket`.

## Grafana

- URL: http://localhost:3001 (or `${GRAFANA_PORT}`)
- Login: `admin` / `admin` (`GF_ADMIN_USER` / `GF_ADMIN_PASSWORD` in `.env`)
- Datasources (Prometheus, Loki, Tempo) and the 7 dashboards below are
  provisioned automatically on first boot from
  `observability/grafana/provisioning/`.

### Dashboards -- one per service, in the "Polyglot Microservices" folder

Each of the 7 dashboards (`<service>.json`) covers, using that service's
own metrics as described above:

- **Uptime, SLIs & Error Budget**: up/down, availability SLI (non-5xx %),
  request rate, P95 latency
- **HTTP Traffic**: total successful requests (1h), total failed requests
  (1h), error rate %, request rate split success-vs-failure, latency
  percentiles (p50/p95/p99)
- **Business KPI** (order-service and payment-service only): orders
  created / payments captured, both as a 1h total and a live rate --
  sourced from `orders_created_total` and `payments_captured_total`,
  incremented at the actual success point in each service's own code
  (`order-service/app/main.py`'s order-creation handler,
  `payment-service/Program.cs`'s payment-capture handler)
- **Runtime** (auth-service only): JVM heap memory used
- **Node Resource Utilization**: host CPU % and memory % -- the same
  node-exporter query repeated in every dashboard, since you asked for
  node CPU/memory to appear on each individual service's dashboard rather
  than only in one shared place

### Alerting -- via Alertmanager

- `observability/prometheus/alerts.yml` (mounted into `prometheus`, wired
  via `rule_files`), evaluated by Prometheus itself:
  - `NodeCPUHigh` / `NodeMemoryHigh` (> 70%, 5m sustained)
  - `ServiceDown` (any of the 7 services unreachable for 2m) -- uses
    Prometheus's own `up{}` meta-metric, which works identically
    regardless of language, so it's the one alert kept fully
    cross-service despite the metric-naming differences above
- `observability/alertmanager/alertmanager.yml` handles routing/grouping
  and email delivery, with an inhibition rule so `ServiceDown` suppresses
  the noisier node warnings for the same instance.
- Alertmanager UI: http://localhost:9093

**Important:** Alertmanager's config file does **not** support `${VAR}`
environment-variable interpolation the way Grafana's provisioning files
do. The SMTP/email settings in `alertmanager.yml` are literal placeholder
values -- edit that file directly (then
`docker compose restart alertmanager`) to point at real SMTP credentials,
not `.env`.

## Known platform caveat

`node-exporter` is run with bind-mounted `/proc`, `/sys`, `/` (not
`network_mode: host`, which doesn't work on Docker Desktop) so it starts
consistently everywhere; on Docker Desktop (macOS/Windows) this reports
the VM's resources, not literally the physical host's.
