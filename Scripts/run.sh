#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/bundle.sh "${1:-debug}"
pkill -x SnapScreen 2>/dev/null || true
open build/SnapScreen.app
