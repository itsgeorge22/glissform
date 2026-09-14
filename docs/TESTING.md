# Testing

## Automated

Run `bash scripts/build.sh` followed by `bash scripts/test.sh`.

Motion checks exercise thresholds, repeated closure, slow whole-degree readings, reversal, settling, zero-effect entrance, interrupted handoffs, low-lid startup, and reset behavior. Synthetic Metal checks compare projected pixels to a CPU calculation and verify orientation, opacity, zero-angle identity, and the final top shadow.

`bash scripts/test.sh --motion-only` explicitly omits Metal checks. GitHub Actions uses this mode; it does not verify physical lid behavior, permissions, or screen capture.

## Physical acceptance

Record the app version, Mac model, macOS version, display arrangement, start angle, and results:

- Start above and below the selected angle; check that the effect starts only after an eligible close.
- Leave the desktop unchanged, then close slowly and quickly.
- Pause at several angles; check settling and idle behavior.
- Reverse before the screenshot returns, during entrance, midway, and during the exit fade.
- Reclose during the return; check for image jumps or a lingering overlay.
- Let the Mac sleep, wake and unlock, then close again.
- Exercise permission denial/revocation, display changes, and unavailable capture/sensor paths where practical.
- Check external displays, multiple Spaces, full-screen apps, Dock/menu coverage, and restoration of mouse access.
- Reopen and quit. Confirm no overlay remains.

Measure capture delay, frame timing, CPU/GPU use, memory, and power before making performance claims. Hardware tests are not complete merely because synthetic tests pass.
