#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "" && "${1:-}" != "--motion-only" && "${1:-}" != "--release" ]]; then
    echo "Usage: bash scripts/test.sh [--motion-only|--release]" >&2
    exit 1
fi
APP="build/Glissform Dev.app"
if [[ "${1:-}" == "--release" ]]; then APP="build/Glissform.app"; fi
mkdir -p build/tests
swiftc -swift-version 5 -parse-as-library Sources/Glissform/DisplayConfiguration.swift Tests/DisplayConfigurationChecks.swift -o build/tests/display-configuration-checks
build/tests/display-configuration-checks
swiftc -swift-version 5 -parse-as-library Sources/Glissform/UsageAnalyticsState.swift Tests/AnalyticsChecks.swift -o build/tests/analytics-checks
build/tests/analytics-checks
swiftc -swift-version 5 -parse-as-library Sources/Glissform/UsageAnalyticsState.swift Sources/Glissform/UsageAnalytics.swift Tests/AnalyticsTransportChecks.swift -o build/tests/analytics-transport-checks
GLISSFORM_ANALYTICS_TEST=1 build/tests/analytics-transport-checks
swiftc -swift-version 5 -parse-as-library Sources/Glissform/LicenseAccess.swift Sources/Glissform/LicenseController.swift Tests/LicenseChecks.swift -o build/tests/license-checks
build/tests/license-checks
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests -p 'test_license_preview.py'
swiftc -swift-version 5 Sources/Glissform/ClosingMotion.swift Sources/Glissform/MotionSmoothing.swift Sources/Glissform/LidAnglePresentation.swift Sources/Glissform/ScreenProjection.swift Tests/MotionChecks.swift -o build/tests/motion-checks
build/tests/motion-checks
swiftc -swift-version 5 Sources/Glissform/ClosingMotion.swift Sources/Glissform/WakeOpening.swift Tests/WakeOpeningChecks.swift -o build/tests/wake-opening-checks
build/tests/wake-opening-checks
swiftc -swift-version 5 -parse-as-library Sources/Glissform/DesktopCapture.swift Tests/CaptureChecks.swift -o build/tests/capture-checks
build/tests/capture-checks
if [[ "${1:-}" == "--motion-only" ]]; then
    echo "SKIP: Metal rendering checks (--motion-only requested)"
elif [ -x "$APP/Contents/MacOS/Glissform" ]; then
    "$APP/Contents/MacOS/Glissform" --render-test
    "$APP/Contents/MacOS/Glissform" --lifecycle-test
    swiftc -swift-version 5 -parse-as-library Sources/Glissform/OverlayWindow.swift Tests/OverlayChecks.swift -o build/tests/overlay-checks
    build/tests/overlay-checks
else
    echo "Build $APP before running Metal checks." >&2
    exit 1
fi
