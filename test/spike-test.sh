#!/usr/bin/env bash
# Sudden burst of traffic followed by a sudden drop. See
# test/README.md. Watch Grafana while this runs.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_run-k6.sh" spike-test.js "$@"
