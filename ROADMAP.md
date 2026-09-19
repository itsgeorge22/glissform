# Roadmap

Glissform explores visual responses to the way a MacBook moves and changes state. Its immediate focus is a smooth, reliable lid-closing animation. This roadmap separates committed near-term work from ideas; it is not a release-date promise.

## Current — 0.1.0-alpha.2

Implemented: screenshot-based closing animation with full-angle hinge compensation, steadier adaptive smoothing, progressive full-image frost and shadow, awake reversal, native settings with a configurable starting angle and capture-free preview, menu bar controls, and lifecycle cleanup. Synthetic checks cover projection, tracking, and interrupted gestures; repeatable physical acceptance remains an upcoming gate. See [README](README.md) for current behavior and [CHANGELOG](CHANGELOG.md) for completed work.

## Next alpha iterations

- [x] Correct full-angle hinge compensation, smooth quantized-input tracking speed, reduce entrance delay, and tune progressive full-image frost toward the supplied Duo references; add synthetic desktop material previews alongside projection, tracking and lifecycle regression checks.
- [ ] Evaluate slow/fast closing, pauses, abrupt reversals, and capture handoffs with repeatable physical tests.
- [ ] Investigate any remaining visible angle steps, flashes, or discontinuities with measurements rather than only stronger easing.
- [ ] Measure capture latency, frame pacing, CPU/GPU load, memory use, and idle/battery impact.
- [ ] Strengthen recovery from denied/revoked permissions, unavailable screenshots, sensor disconnects, and display changes.
- [ ] Test full-screen applications, Dock/menu behavior, external displays, multiple Spaces, sleep/wake, and quitting during transitions.
- [ ] Build a compatibility table from additional MacBook testing.
- [x] Refine the native interface with compact navigation, adaptive neutral surfaces, a distinctive perspective illustration, and a clearer control hierarchy.
- [x] Add a capture-free, in-window gesture preview with a still alternative for Reduce Motion and contextual first-gesture guidance.
- [x] Introduce and simplify native settings with a dedicated live-angle display, precise trigger controls, and screen-access status, and an About page with prominent privacy information.
- [ ] Validate the settings, preview, and permission guidance with first-time testers, including keyboard and VoiceOver use, then refine onboarding and diagnostics.
- [ ] Decide the project's license before describing it as open source.

## Beta gate — 0.1.0-beta.1

Move to beta when the intended closing-animation feature set is settled and:

- Core closing/reversal behavior is consistent across the documented supported configurations.
- Capture and sensor failures reliably restore normal desktop interaction.
- Performance and power measurements meet recorded acceptance targets.
- Installation and permission instructions work for testers without developer assistance.
- Known limitations and supported hardware are documented accurately.
- There are no known blockers to broader voluntary testing.

During beta, prioritize bug fixes, compatibility evidence, onboarding, and distribution over expanding the feature set.

## Release candidate and stable — 1.0.0-rc.1 → 1.0.0

- [ ] Complete broader testing with no unresolved release-blocking failures.
- [ ] Establish Developer ID signing, notarization, and a reproducible distribution process.
- [ ] Verify installation, upgrade, and removal on supported macOS versions.
- [ ] Confirm normal desktop access is restored after errors and interruptions.
- [ ] Finalize privacy documentation, support instructions, and release notes.

A release candidate is a complete proposed stable build. Publish 1.0.0 when those checks pass. A wake-opening animation is not a prerequisite.

## Future possibilities — not committed

- Wake/opening animation, only if macOS timing and permissions allow a dependable implementation.
- Optional launch at login; a lightweight enable/pause control is already available in the working settings and menu.
- Carefully bounded blur, shadow, and motion preferences or presets.
- Accessibility options and behavior that respects reduced-motion preferences.
- Broader hardware support and calibration for different viewing angles.
- Other subtle display-state transitions, where they fit the product and can be delivered reliably.
- A signed update experience and additional distribution channels after platform requirements are assessed.

## Version policy

- Alpha: `0.1.0-alpha.1`, `0.1.0-alpha.2`, and so on for public test builds.
- Beta: `0.1.0-beta.1`, then numbered beta builds.
- Release candidate: `1.0.0-rc.1` and subsequent candidates if required.
- Stable: `1.0.0`; fixes become `1.0.1`, compatible feature additions `1.1.0`, and breaking changes `2.0.0`.

Not every commit needs a release. Move shipped work into the changelog and revise this roadmap whenever priorities or readiness criteria change.
