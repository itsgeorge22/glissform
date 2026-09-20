# Roadmap

Glissform adds subtle animations and quality-of-life improvements to everyday Mac interactions. The product is intended to grow into a cohesive collection of useful visual experiences for familiar gestures and system changes. Infinite Screen is the first available feature, not the boundary of the app.

New experiences should feel native, have a clear purpose, stay lightweight, and respect privacy and normal system behaviour. Additional experiences are part of the product direction; their specific triggers, designs, and release dates are not announced here. This roadmap separates available work, near-term validation, and possibilities.

## Current — 0.1.0-alpha.6

The first feature, Infinite Screen, implements screenshot-based closing animation with full-angle hinge compensation, steadier adaptive smoothing, progressive full-image frost and shadow, awake reversal, cached post-sleep opening, native settings with a configurable starting angle and capture-free preview, optional desktop restoration after a fixed two-second still-lid pause, menu bar controls, and lifecycle cleanup. Synthetic checks cover projection, tracking, and interrupted gestures; repeatable physical acceptance remains an upcoming gate. See [README](README.md) for current behavior and [CHANGELOG](CHANGELOG.md) for completed work.

## Product development

- [ ] Design and validate additional animation and quality-of-life experiences for everyday Mac interactions.
- [ ] Evolve feature discovery and settings as more experiences become available, keeping the interface coherent and easy to understand.
- [ ] Define the purpose, controls, permissions, accessibility behaviour, and performance budget of each new experience before release.
- [ ] Continue improving existing features alongside new work; expansion is not dependent on making Infinite Screen the entire product.

## Next alpha iterations — shared foundations and Infinite Screen

- [x] Prepare an initial unreleased wake-opening prototype with immediate reconnection, remaining-angle motion, bounded eligibility, local timing diagnostics, and synthetic cancellation checks.
- [x] Correct loss of numeric wake eligibility when a lock/session notification follows sleep, and cover lock-before-wake, lock-after-wake, unlock with remaining motion, completed opening and timeout sequences in synthetic checks.
- [x] Correct premature sensor-loss cancellation by a heartbeat delivered immediately after wake, preserving the bounded sensor-recovery and wake deadlines.
- [x] Replace fresh wake capture with the completed closing image and prepared texture, retained in memory through lid-close sleep. Add hidden retention, lock ordering, skipping when no frame is available, cleanup checks, and updated privacy copy.
- [x] Obtain owner confirmation that cached opening works well on the development Mac after the faded-window reports.
- [ ] Measure remaining wake-to-visible delay and repeat appearance checks across lock states and opening speeds. The earlier fresh-capture trials exposed a blink and 283–356 ms preparation latency; cached pixels alone do not establish control of the first visible screen frame. See `docs/TESTING.md`.
- [ ] Physically validate wake timing, quick/slow full-lid reopening, lock/unlock, fullscreen and external-display transitions on the target Mac. Verify the undocumented lock hints on supported macOS versions before describing wake opening as dependable.

- [x] Allow Infinite Screen's overlay to join another app's full-screen Space with settings open or closed, without activating Glissform; verify visibility with a separate full-screen app and retain physical acceptance as a separate gate.

- [x] Hide the Dock icon when settings close, keep Infinite Screen and menu bar access running, and restore the window and Dock icon when reopened without adding a permission requirement.

- [x] Integrate the centred, inset blue glass-wave icon with distinct light and dark bases plus native clear and tinted appearances. Preserve the same material shading in every style; verify native compilation, all six rendition exports, Finder style changes, and the running app's Privacy & About icon on macOS 27.
- [x] Correct the Dock placeholder after resetting the native launch icon and refreshing development bundle registration; the owner confirmed the icon displays correctly.
- [x] Use a monochrome menu bar template derived from the actual Clear app icon, sharing the Icon Composer source and using the system foreground colour.
- [ ] Verify the compiler-generated legacy icon on an earlier supported macOS version.

- [x] Unify interface iconography with locally bundled Iconly Bold / Regular vectors, retaining Bulk, Outline, and the previous Custom mix as alternatives with live switching in developer builds.

- [x] Establish shared spacing, typography, surfaces, permission-state colours, and control feedback across settings and About.

- [x] Show missing screen access on the main page, briefly confirm detected grants, and keep persistent access status and management in Privacy & About.

- [x] Add optional desktop restoration after a fixed two-second still-lid pause, with a persisted toggle and gesture/cancellation regression checks.
- [ ] Physically validate pause-to-resume timing and jitter tolerance during slow movement, lower-angle work, and sleep transitions.

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

Move to beta when the feature set selected for that beta is settled and:

- Each included experience behaves consistently across its documented supported configurations; Infinite Screen includes closing and reversal checks.
- Failures in the resources each feature uses reliably leave or restore normal desktop interaction, including capture and sensor failures in Infinite Screen.
- Performance and power measurements meet recorded acceptance targets.
- Installation and permission instructions work for testers without developer assistance.
- Known limitations and supported hardware are documented accurately.
- There are no known blockers to broader voluntary testing.

Stabilize the selected beta feature set through bug fixes, compatibility evidence, onboarding, and distribution work. Additional experiences can be explored separately without destabilizing the beta.

## Release candidate and stable — 1.0.0-rc.1 → 1.0.0

- [ ] Complete broader testing with no unresolved release-blocking failures.
- [ ] Establish Developer ID signing, notarization, and a reproducible distribution process.
- [ ] Verify installation, upgrade, and removal on supported macOS versions.
- [ ] Confirm normal desktop access is restored after errors and interruptions.
- [ ] Finalize privacy documentation, support instructions, and release notes.

A release candidate is a complete proposed stable build. Publish 1.0.0 when those checks pass. A wake-opening animation is not a prerequisite.

## Further possibilities — not committed

- Broader wake-opening support after the prototype passes timing, privacy, and physical acceptance gates; no first-frame or locked-wake guarantee.
- Optional launch at login; a lightweight enable/pause control is already available in the working settings and menu.
- Carefully bounded blur, shadow, and motion preferences or presets.
- Accessibility options and behavior that respects reduced-motion preferences.
- Broader hardware support and calibration for different viewing angles.
- Other visual feedback and transitions for everyday Mac interactions, where they add clarity or enjoyment and can be delivered reliably.
- A signed update experience and additional distribution channels after platform requirements are assessed.

## Version policy

- Alpha: `0.1.0-alpha.1`, `0.1.0-alpha.2`, and so on for public test builds.
- Beta: `0.1.0-beta.1`, then numbered beta builds.
- Release candidate: `1.0.0-rc.1` and subsequent candidates if required.
- Stable: `1.0.0`; fixes become `1.0.1`, compatible feature additions `1.1.0`, and breaking changes `2.0.0`.

Not every commit needs a release. Move shipped work into the changelog and revise this roadmap whenever priorities or readiness criteria change.
