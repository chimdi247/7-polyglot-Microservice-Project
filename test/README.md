# test/

Shell scripts for load, stress, and spike testing the running polyglot
stack, using [k6](https://k6.io/). Run these **after**
`docker compose up` is healthy, from the project root or from inside
this folder.

```bash
./test/load-test.sh      # steady realistic traffic
./test/stress-test.sh    # progressively increasing load past normal capacity
./test/spike-test.sh     # sudden burst, then sudden drop
```

Each script targets every service's host-published port (defaults:
auth `:8081`, catalog `:8082`, inventory `:8083`, order `:8084`,
payment `:8085`, notification `:8086`, analytics `:8087` -- override
any of `AUTH_URL`/`CATALOG_URL`/`INVENTORY_URL`/`ORDER_URL`/
`PAYMENT_URL`/`NOTIFICATION_URL`/`ANALYTICS_URL` if you changed the
corresponding `*_SERVICE_PORT` in `.env`). If you have `k6` installed
locally it's used directly; otherwise the scripts fall back to running
it via `docker run grafana/k6` automatically -- no local install
required, just Docker.

While a test runs, open each service's dashboard in Grafana
(http://localhost:3001, "Polyglot Microservices" folder) -- request
rate, error rate, latency percentiles, and node CPU/memory all update
live. See `observability/README.md`.

## What each scenario does

| Script | Pattern | What it's for |
|---|---|---|
| `load-test.js` | Ramp to 20 VUs, hold 2m, ramp down | Baseline: does the stack behave correctly under expected normal traffic? Strict thresholds (p95 < 800ms, p99 < 1.5s, <1% failures) -- meant to pass. |
| `stress-test.js` | Ramp 50 -> 150 -> 300 -> 500 VUs over ~8m, then back to 0 | Where does the stack start degrading? Thresholds are deliberately loose so the run completes; watch error rate/latency climb per-service in Grafana, and whether each service recovers once load drops back to 0. |
| `spike-test.js` | 10 VUs -> sudden jump to 400 VUs in 10s -> hold -> sudden drop back to 10 | Does the stack survive a sudden burst and recover cleanly afterward? |

All three exercise a read-heavy mix across **all 7 services** in
parallel each iteration (`test/scripts/helpers.js`): each service's
`/health` or main read endpoint (`GET /products`, `/inventory`,
`/orders`, `/payments`, `/analytics/summary`). `/analytics/summary` is
worth watching closely -- analytics-service calls all 6 other services
internally to build it, so it's the most expensive endpoint in the
stack and a good early-warning signal under stress.

## Customizing

Any extra arguments are passed straight through to `k6 run`, e.g. to
write a JSON summary:

```bash
./test/load-test.sh --summary-export=load-test-results.json
```
