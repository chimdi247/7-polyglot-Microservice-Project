#!/usr/bin/env bash
# Shared runner used by load-test.sh / stress-test.sh / spike-test.sh.
# Not meant to be run directly.
set -euo pipefail

SCRIPT_NAME="$1"
shift

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Scenario: ${SCRIPT_NAME}"
echo "==> Targeting each service's host-published port (override any"
echo "    of AUTH_URL/CATALOG_URL/INVENTORY_URL/ORDER_URL/PAYMENT_URL/"
echo "    NOTIFICATION_URL/ANALYTICS_URL if you changed *_SERVICE_PORT in .env)"
echo

if command -v k6 >/dev/null 2>&1; then
  echo "==> Using locally installed k6"
  k6 run "$@" "${TEST_DIR}/scripts/${SCRIPT_NAME}"
else
  echo "==> k6 not found locally, running via Docker (grafana/k6)"
  echo "    (install k6 natively for faster startup: https://grafana.com/docs/k6/latest/set-up/install-k6/)"
  # host.docker.internal lets the k6 container reach each service's
  # host-published port. Works on Docker Desktop (Mac/Windows) out of
  # the box; --add-host makes it work on Linux too (Docker 20.10+).
  docker run --rm -i \
    --add-host=host.docker.internal:host-gateway \
    -e AUTH_URL="${AUTH_URL:-http://host.docker.internal:8081}" \
    -e CATALOG_URL="${CATALOG_URL:-http://host.docker.internal:8082}" \
    -e INVENTORY_URL="${INVENTORY_URL:-http://host.docker.internal:8083}" \
    -e ORDER_URL="${ORDER_URL:-http://host.docker.internal:8084}" \
    -e PAYMENT_URL="${PAYMENT_URL:-http://host.docker.internal:8085}" \
    -e NOTIFICATION_URL="${NOTIFICATION_URL:-http://host.docker.internal:8086}" \
    -e ANALYTICS_URL="${ANALYTICS_URL:-http://host.docker.internal:8087}" \
    -v "${TEST_DIR}/scripts:/scripts:ro" \
    grafana/k6 run "$@" "/scripts/${SCRIPT_NAME}"
fi
