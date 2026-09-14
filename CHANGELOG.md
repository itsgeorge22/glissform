# Changelog

User-visible changes are recorded here. Public versions use prerelease suffixes and Git tags such as `v0.1.0-alpha.1`. Unpublished work belongs under **Unreleased**; released entries remain a historical record.

## Unreleased

No unreleased changes yet.

## 0.1.0-alpha.1 — 2026-09-14

First public alpha of **Glissform**. Earlier local prototypes and tuning iterations are consolidated into this release rather than presented as separate published versions.

### Added

- Native macOS background app with a menu bar icon, readiness information, Screen Recording settings shortcut, and Quit command.
- Lid-angle-driven closing animation with a screenshot projected behind the moving display.
- One in-memory, native-resolution screenshot per gesture, reused during pauses and direction changes; no continuous recording.
- Reversal while reopening before sleep, with continuous handling of reclosing during the return transition.
- Persisted start-angle slider from 20° to 130°, defaulting to 100°.
- Adaptive smoothing of whole-degree lid readings and display-paced rendering that pauses when settled.
- A prepared, unchanged first frame, an 80 ms visibility fade, and a 180 ms geometric handoff from zero effect; return-to-flat precedes the exit fade.
- Gentle perspective, progressive frost, and a full-height shadow that builds through 0–100% of the animation, reaching full black only across the top 5% at completion.
- Overlay coverage above the live Dock/menu bar, with click blocking during the effect and cleanup on reopening, sleep, display changes, sensor loss, and quit.
- Standalone motion checks, synthetic Metal rendering checks, sensor probe, and version reporting.
- Repository documentation, contributor guidance, issue templates, macOS build CI, and explicit release version files.

### Known limitations

- Physical development testing is limited to the MacBook Air M5 15-inch (Mac17,4).
- No wake-from-sleep opening animation, notarized installer, automatic updates, login launch, or broader hardware guarantee.
- Whole-degree sensor resolution, screenshot latency, moving content, and fixed-viewpoint projection can remain perceptible.
- GPU/physical verification and battery measurements are not replaced by automated CI.
