#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "" && "${1:-}" != "--motion-only" ]]; then
    echo "Usage: bash scripts/test.sh [--motion-only]" >&2
    exit 1
fi
mkdir -p build/tests
swiftc -swift-version 5 Sources/Glissform/ClosingMotion.swift Sources/Glissform/MotionSmoothing.swift Tests/MotionChecks.swift -o build/tests/motion-checks
build/tests/motion-checks
if [[ "${1:-}" == "--motion-only" ]]; then
    echo "SKIP: Metal rendering checks (--motion-only requested)"
elif [ -x build/Glissform.app/Contents/MacOS/Glissform ]; then
    build/Glissform.app/Contents/MacOS/Glissform --render-test
else
    echo "Build the app before running Metal checks: bash scripts/build.sh" >&2
    exit 1
fi
