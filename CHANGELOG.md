# Changelog

User-visible changes are recorded here. Public versions use prerelease suffixes and Git tags such as `v0.1.0-alpha.1`. Unpublished work belongs under **Unreleased**; released entries remain a historical record.

## Unreleased

## 0.1.0-alpha.2 — 2026-09-19

Second public alpha, with improved Infinite Screen motion and material, native settings, and expanded synthetic regression checks. Source release; local builds remain ad-hoc signed and are not notarized.

### Added

- Native macOS settings with Experience and About pages, a live lid reading, Infinite Screen enable switch, precise start-angle controls, Use current angle, and reset.
- An in-window motion preview using original vector artwork, with no screen capture, automatic completion, a stop control, and a still alternative for Reduce Motion.
- Contextual readiness and setup guidance for screen access, unavailable sensors, and opening above the start angle.
- A dedicated About page with privacy and alpha-support details, standard app menus, and keyboard shortcuts for settings, editing, closing the window, and quitting.
- Synthetic projection, tracking-speed, and gesture-lifecycle regression checks, plus material previews and a GPU-only rendering benchmark for development.

### Changed

- Corrected Infinite Screen to compensate the full physical lid rotation, removing the reduced rotation gain and the late-closure limit that could make the image drift or stop following the hinge.
- Smoothed changes in tracking speed, preserved velocity when the filter response changes, and shortened entrance/return handoffs to 100 ms. Entrance geometry now blends during the screenshot fade instead of waiting for it. Active rendering requests the display's maximum refresh rate.
- Retuned the material toward the supplied Duo references: soft coloured shapes and less darkening during the middle of the gesture, with blur strength balanced to keep the perspective skew visible. A normalized Gaussian-like sampling kernel replaces concentric blur rings. Frost remains progressive across the entire image, lighter at the hinge and heavier at the top, and clears on reopening.
- Made the switch and slider handles solid white in every state. Hover/press feedback uses the switch track and subtle slider-thumb size changes instead of tinting the handles.
- Removed the redundant Enabled/Paused label beneath the Infinite Screen switch.
- Added consistent hover and pressed feedback to buttons and links, integrated slider-thumb and stepper feedback, an Apple-style capsule switch, and an active outline for angle editing. Slider, switch, and stepper hover states have no outer container or border. Disabled actions stay subdued; feedback transitions respect Reduce Motion.
- Refined settings into a compact window with a perspective illustration, adaptive neutral surfaces, and system-accent controls. Removed the logo header and segmented navigation; Privacy & About opens from the footer and has a Back button (⌘[).
- The angle field now clears focus when clicking outside it and commits on Return or focus loss, so incomplete typing is not clamped mid-entry. Slider and stepper changes remain immediate.
- Opening or reopening Glissform presents its settings window. Closing it keeps the app running. Glissform appears in both the Dock and menu bar, with a restrained graphite app mark.
- Simplified the menu bar to readiness, animation enable, Settings, and Quit. Screen-access status refreshes while the app runs; unavailable sensor readings clear the displayed angle.

### Removed

- Removed the optional menu bar angle and its settings switch. The live angle remains in the settings window.
- Removed the duplicate menu slider and oversized settings sidebar.

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
