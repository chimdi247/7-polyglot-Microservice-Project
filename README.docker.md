# Running the Polyglot Microservices Lab with Docker

One `docker-compose.yml` at the repo root runs everything: Postgres, all 7
backend services (Java, Go, Node.js, Python, C#, Ruby, PHP), and the React
frontend — each in its own container, each still using its own language,
runtime, and database, exactly as the project was designed.

## 1. Prerequisites

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER   # log out/in after this
docker compose version          # should print v2.x
```

That's it — you do **not** need Java, Go, Node, Python, .NET, Ruby, or PHP
installed on the host. Docker builds each service in its own container.

## 2. Build and start

No `.env` file is required — everything has a working default.

```bash
docker compose up -d --build
```

First build takes a while: 7 completely different toolchains are compiling/
installing (Maven, Go modules, npm, pip, NuGet, Bundler) plus the frontend's
`npm run build`. Watch progress:

```bash
docker compose logs -f
```

## 3. Databases and the admin login are created automatically

`docker/postgres/init/` is mounted into the Postgres container at
`/docker-entrypoint-initdb.d`, which Postgres runs automatically — but only
the **first time** it starts with an empty data volume, in filename order:

1. **`01-databases.sql`** — creates the shared `microapp` role and the 7
   per-service databases (`auth_db`, `catalog_db`, `inventory_db`,
   `order_db`, `payment_db`, `notification_db`, `analytics_db`). This
   mirrors `database/bootstrap.sql` from the repo root.
2. **`02-schema.sql`** — creates every table each service needs, and grants
   `microapp` privileges on them (the init scripts run as the Postgres
   superuser, so without this grant the services — which connect as
   `microapp` — couldn't read/write the tables). Every service also runs
   its own `CREATE TABLE IF NOT EXISTS` on startup; since this file matches
   that exactly, the service's own migration is a no-op afterwards.
3. **`03-seed-admin-user.sql`** — inserts a ready-to-use login:

   ```
   email:    admin@example.com
   password: password123
   ```

   Stored as a bcrypt hash, not plaintext — generated the same way
   auth-service hashes passwords (Spring Security's `BCryptPasswordEncoder`),
   so it verifies correctly at login. This exists **alongside** the app's
   own seeded demo account (`admin@devopsshack.com` / `admin123`, created by
   auth-service itself on first boot) — both logins work.

If you need to re-run these scripts (e.g. after editing them), you must wipe
the Postgres volume first — see "Common operations" below.

## 4. Open the app

```
http://localhost:5173
```

Log in with either seeded account above.

## 5. How requests are routed (no API gateway here)

This project has no separate gateway service. Instead, the frontend calls
relative paths like `/api/catalog/products`, and:

- In **dev mode** (`npm run dev`), Vite's own proxy (`frontend/vite.config.js`)
  forwards `/api/<service>/*` to `http://127.0.0.1:<port>/*` on your machine.
- In **this Docker setup**, `frontend/nginx.conf` does the exact same
  prefix-stripping proxy, just pointed at each service's container name
  instead of `127.0.0.1`. No frontend code changes were needed — the app
  already used relative URLs everywhere.

| Frontend path | Proxied to |
|---|---|
| `/api/auth/*` | `auth-service:8081` |
| `/api/catalog/*` | `catalog-service:8082` |
| `/api/inventory/*` | `inventory-service:8083` |
| `/api/orders/*` | `order-service:8084` |
| `/api/payments/*` | `payment-service:8085` |
| `/api/notifications/*` | `notification-service:8086` |
| `/api/analytics/*` | `analytics-service:8087` |

Every backend service's own port is also published to the host (8081-8087)
if you want to `curl` them directly — see the README's API examples.

## 6. Check everything is healthy

```bash
docker compose ps
```

Every service has a `HEALTHCHECK` (each language's Dockerfile hits its own
`/health` endpoint), so `docker compose ps` will show `healthy`/`unhealthy`
once containers finish starting.

## 7. Observability: Grafana, Prometheus, Alertmanager, Loki, Tempo

Also started automatically by `docker compose up`, no extra flags needed:

| What | URL | Login |
|---|---|---|
| Grafana (7 per-service dashboards) | http://localhost:3001 | `admin` / `admin` |
| Prometheus | http://localhost:9091 | -- |
| Alertmanager | http://localhost:9093 | -- |

Every service exports traces (all except analytics-service, which has a
documented exception) and metrics via OpenTelemetry/native Prometheus
clients, and every container's logs flow into Loki. Alerting for node
CPU/memory > 70% is wired through Alertmanager. Full details -- how each
of the 7 languages is instrumented, what each dashboard shows, and a
couple of things worth double-checking -- are in
[observability/README.md](observability/README.md).

## 8. Load, stress, and spike testing

```bash
./test/load-test.sh
./test/stress-test.sh
./test/spike-test.sh
```

See [test/README.md](test/README.md).

## 9. Common operations

```bash
# Rebuild + restart a single service after a code change
docker compose up -d --build catalog-service

# Tear everything down (keeps the Postgres volume/data)
docker compose down

# Tear down AND wipe the database (re-runs docker/postgres/init/* next start)
docker compose down -v
```

## 10. Changing the database password

The `microapp` / `microapp123` credentials are intentionally hardcoded in
three places rather than templated through `.env`, because a mismatch
between them silently breaks every service:

- `docker-compose.yml` — every service's `*_DB_URL`/`*_DB_DSN` env var
- `docker/postgres/init/01-databases.sql` — the `CREATE ROLE` statement

To change it: update the password in both places identically, then
`docker compose down -v && docker compose up -d --build` (a volume wipe is
required — Postgres only applies init scripts to an empty data directory).

## What was added to make this runnable in Docker

The project ran great locally with 8 terminals and manually-installed
toolchains, but had no Dockerfiles or docker-compose.yml at all. Added:

- A `Dockerfile` per service, each using that language's idiomatic
  multi-stage build (Maven → JRE, Go → static binary, npm → node:alpine,
  pip → python:slim, dotnet publish → aspnet runtime, Bundler → ruby:slim,
  a PHP image with `pdo_pgsql`/`curl` extensions built in).
- `frontend/nginx.conf`, replicating the dev-mode Vite proxy for production.
- `docker/postgres/init/*.sql` — table creation and the requested admin
  seed, plus the `GRANT` statements needed because init scripts run as the
  Postgres superuser while the app connects as `microapp`.
- One root `docker-compose.yml` wiring all of it together with proper
  healthchecks and startup ordering.

No application code changes were needed — every service already read its
database connection string and peer-service URLs from environment
variables with sensible localhost defaults, and the frontend already used
relative `/api/*` paths rather than hardcoded ports. This project was
unusually well set up for containerization already.

## What was added for observability

On top of the above, full observability was added across all 7 languages:

- **Traces**: OpenTelemetry in every service except analytics-service
  (documented exception -- see `observability/README.md`), ranging from
  truly zero-code (Java's `-javaagent`, Python's `opentelemetry-instrument`,
  Node's `NODE_OPTIONS=--require`) to a small amount of manual SDK
  registration where a language has no bytecode-weaving equivalent (Go,
  C#, Ruby).
- **Metrics**: each service's own native Prometheus client library,
  exposing `/metrics` directly (rather than trusting 7 different OTel SDK
  versions to name auto-generated metrics consistently). `orders_created_total`
  and `payments_captured_total` were added as explicit business-KPI counters,
  incremented at the actual success point in `order-service`'s and
  `payment-service`'s own code.
- **Logs**: Promtail, tailing every container's stdout via the Docker
  socket -- no per-service code changes.
- A couple of real bugs were caught and fixed while wiring this up: a
  Node.js `--require` bootstrap file needed a `.cjs` extension (not `.js`)
  since `inventory-service`'s `package.json` sets `"type": "module"`, and
  an initial PHP metrics implementation used `apcu_cas()` on a float value,
  which that function doesn't support (fixed to a simpler approach, safe
  since PHP's built-in dev server handles requests one at a time anyway).

Full details in [observability/README.md](observability/README.md).

## Known limitations

- **Single Postgres instance** for all 7 databases — fine for a local lab,
  not how you'd separate blast radius in production.
- **No TLS or reverse proxy in front of the frontend container** — add
  Nginx/Caddy/Traefik or a cloud load balancer for anything beyond local
  use.
- **Backend ports are all published to the host** (8081-8087) for
  convenience/debugging. For a genuinely public deployment you'd likely
  keep those internal-only and route everything through the frontend's
  nginx proxy instead.
