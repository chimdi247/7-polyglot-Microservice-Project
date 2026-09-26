#!/usr/bin/env bash
# Progressively increasing load to find the breaking point. See
# test/README.md. Watch Grafana while this runs.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_run-k6.sh" stress-test.js "$@"
