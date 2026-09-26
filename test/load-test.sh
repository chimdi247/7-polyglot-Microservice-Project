#!/usr/bin/env bash
# Steady, realistic traffic across all 7 services. See test/README.md.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_run-k6.sh" load-test.js "$@"
