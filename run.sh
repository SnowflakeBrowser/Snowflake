#!/bin/bash
# Veil launcher.   Usage:   cd Veil && ./run.sh
# Always does a (fast, incremental) build so you never launch an old version, then opens Veil.app.
set -euo pipefail
cd "$(dirname "$0")"
command -v swift >/dev/null || { echo "Swift not found. Install Xcode or run: xcode-select --install"; exit 1; }
./scripts/build_app.sh
open build/Veil.app
