#!/usr/bin/env bash
set -euo pipefail
INCLUDE_NATIVE=0 exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openfoam_wheel.sh"
