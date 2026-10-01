# Roadmap

Glissform adds subtle animations and quality-of-life improvements to everyday Mac interactions. The product is intended to grow into a cohesive collection of useful visual experiences for familiar gestures and system changes. Seamless Close is the first available feature, not the boundary of the app.

New experiences should feel native, have a clear purpose, stay lightweight, and respect privacy and normal system behaviour. This roadmap separates available work, near-term fixes, and feature ideas without committed release dates.

Glissform is a small passion project. The owner's intended price is $1.90, with occasional improvements and new features after launch. Keep release preparation proportional to that scope; broad hardware certification, formal performance studies, and a fixed tester cohort are not prerequisites.

## Public beta — 0.1.0-beta.1

The first feature, Seamless Close, implements screenshot-based closing animation with continuous hinge perspective and upper-edge narrowing through the full gesture, steadier adaptive smoothing, optional full-image blur and shadow, awake reversal, cached post-sleep opening, native settings with a configurable starting angle, optional desktop restoration after an adjustable still-lid pause, menu bar controls, and lifecycle cleanup. On 2026-09-21, the owner confirmed correct smoothness, speed, abrupt lid stops, reversals, and opening after sleep without locking on the development Mac. On 2026-09-28, the owner confirmed the revised geometry and Blur on/off during everyday gestures, plus the requested Space and sleep/wake checks. Locked-screen animation remains unavailable. See [README](README.md) for current behavior and [CHANGELOG](CHANGELOG.md) for completed work.

## Current priority — Space-change verification

- [x] Resolve [#1: Infinite Screen breaks when switching Spaces with a full-screen app open](https://github.com/itsgeorge22/glissform/issues/1) in code: keep visible pixels in their source Space instead of duplicating them across the transition, then cancel the animation, release input and discard its screenshot when the active Space changes; require reopening above the active starting angle before the next gesture.
- [x] Owner confirmed normal and full-screen Space changes on the development Mac, with settings open and closed, on 2026-09-26. Issue #1 was already closed after the code fix; this owner check supplied the remaining physical acceptance.

## Product development

- [x] Implement Battery Ripple with independent power-connection and 20%-battery switches, using public power-source notifications and a reduced-motion fallback. Included in the alpha.9 source prerelease.
- [x] Replace the original concentric connection rings with a fluid emerald light wave, a curling silhouette, and translucent folds; reuse the geometry in red for the 20% battery event. The owner approved the revised emerald appearance on 2026-09-26; the red variant awaits physical approval.
- [ ] Complete physical Battery Ripple checks for both triggers with settings closed, full-screen apps, sleep/wake, lock, and Reduce Motion. On 2026-09-26, the owner confirmed one green ripple on one unplug/reconnect trial with the earlier visual design. The 20% event has only synthetic checks so far.
- [ ] Design and validate additional animation and quality-of-life experiences for everyday Mac interactions.
- [x] Add sidebar navigation with separate Seamless Close, Battery Ripple, and Privacy & About pages, plus a Send feedback placeholder grouped under More.
- [x] Add General as the first page under Features with saved background-running and menu bar icon controls. Background running removes the Dock icon on Settings close even when the menu bar icon is hidden; opening the app again restores Settings.
- [x] Add a Launch at login control to General, backed by the system login-item status with approval feedback.
- [x] Replace the Automatic updates placeholder with a switch backed by Sparkle's download and install preference. Keep update checks active in both modes.
- [x] Apply the native pointing-hand cursor to active Settings controls, use the system unavailable cursor for disabled actions, and raise the unreleased app's minimum deployment target to macOS 15.
- [x] Connect the sidebar Update card to signed update detection and Sparkle's install flow; show it only when Automatic updates is off and a newer installable release is found.
- [x] Prepare the beta.3 update-flow correction: check quietly on app launch and hourly while open, then keep a detected manual-mode update visible until a check finds none. Verify it against the published feed in an installed build; beta.2 does not contain this correction.
- [x] Complete an isolated installed-app trial with a signed local feed and DMG: manual mode showed the existing card and installed through its Update button; automatic mode kept the card hidden and installed on quit. A tampered feed was rejected.
- [x] Provision glissform.app on the release VPS with HTTPS and a restricted release-upload account. Publish the beta.1 DMG, checksum, signed feed, and download page.
- [x] Build the desktop Figma landing page with still feature previews and a MacBook viewing message below 1156px. Add a ten-second feature-card timer, manual selection, smooth preview transitions, interactive feature-card states, and interactive blur choices, starting-angle slider, and switches in the Customisable grid; defer broader website animations.
- [x] Set the release workflow's dedicated VPS deploy secret in the private GitHub repository.
- [x] Check the first public beta.1 DMG download against its published SHA-256 checksum.
- [x] Publish beta.3 to replace the broken beta.2 DMG, whose flat SwiftPM resource directory causes a Settings startup crash. The public DMG checksum, signature, bundle structure, and installed startup were verified on the development Mac on 2026-09-30; Screen Recording access remained allowed after a direct reinstall. The owner confirmed first launch and Seamless Close from the earlier locally packaged beta DMG on the development Mac.
- [x] Refine the compact settings composition with native toolbar controls over a narrower sidebar, concentric navigation rows and icons, subtle page icon tiles, a combined Seamless Close switch-and-angle card, and distinct automatic-selection and pause cards. Remove both feature preview illustrations and feature-page privacy footers.
- [x] Add compact play buttons beside the two Battery Ripple event switches so either color can be previewed on demand.
- [x] Build and run the full regression suite for the card and sidebar revision (2026-09-26). Inspect all three pages in the running app's Light appearance for the earlier separate-card layout, including compact rows, icon tiles, and removal of previews. Live Dark and earlier-macOS checks remain pending.
- [ ] Complete live Dark appearance, Reduce Transparency, Increase Contrast, and earlier-macOS checks. Offscreen samples do not validate native selection, focus, or system accessibility integration. The owner's green Battery Ripple appearance approval covers the desktop effect, not this settings revision or the red variant.
- [ ] Define the purpose, controls, permissions, accessibility behaviour, and performance budget of each new experience before release.
- [ ] Continue improving existing features alongside new work; expansion is not dependent on making Seamless Close the entire product.

## Alpha.9 foundations and Seamless Close follow-up

- [x] Add a saved Blur switch to Seamless Close that disables both blur passes without changing the projection, shadow, or one-screenshot gesture.
- [x] Add a selectable High, Regular, and Subtle row below Blur, save the choice, and apply it to both blur passes. Regular is the default; High retains the previous appearance.
- [x] Add a page-level Reset to defaults action for Seamless Close's saved controls.
- [x] Replace blur placeholders with previews of the supplied wallpaper rendered at the same 42° fold with each strength; retain physical comparison of the live effect as a separate gate.

- [x] Owner approved the revised Seamless Close closing feel on the development Mac on 2026-09-28, including its stronger start and continuing later movement.
- [x] Owner confirmed pauses, reopening, and Blur on/off with the revised geometry on the development Mac on 2026-09-28.
- [x] Add an assisted finish for the last 5° of reopening, with reversal back into the same screenshot and safe rearming after an early return. The owner requested the shorter 5° trigger, then reported braking at takeover. Draw the newest lid-driven frame before continuing, carry its speed and bounded acceleration over up to 80 ms, and use the most recent 80 ms of available readings without braking toward an older estimate or a 120°/s cap. Keep the gentle landing. Accelerating fractional/whole-degree and 60/120 Hz renderer replays cover takeover; physical comparison remains pending.
- [x] Add a soft inner connection glow along all four edges, timed to assisted contact, with smooth corners and no pure white outline. Animate its width inward and outward, keeping the original approach brightness and adding an extra pulse to the inner glow at full connection. Retreat gently afterward and cancel the pulse on reversal. Synthetic motion and Metal checks cover the path.
- [x] Restore the previously used short click at assisted contact without delaying rendering, and release mouse access when the image fades while the glow finishes. Synthetic cue and interruption checks cover the path.
- [x] Share the assisted-opening glow, flat-contact pulse and click with Pause and manual Esc returns. Limit the glow approach to their final 5° of visible fold, including shallow returns. Preserve the existing return motion, release input after the screenshot fade and allow the glow to finish over the live desktop. Cover single-cue, pending-capture silence and interruption cleanup synthetically.
- [x] Schedule the click and glow brightness peak against a shared host clock with output-latency compensation, gesture-scoped audio preparation, natural playback completion, and bounded cancellation/cleanup. Cover delayed startup and 60/120 Hz timing synthetically; three Bluetooth playback trials completed on the development Mac.
- [x] Preserve the scheduled Pause click through fractional lid jitter when automatic angle detection rearms. Add coordinator coverage for continuing sensor delivery and explicit disable/reclose cancellation; physical repetition remains part of feedback acceptance below.
- [x] Move connection audio startup after screenshot/first-frame preparation to remove repeated-close capture contention. On the development Mac, a diagnostic copy reduced median repeated capture time from 300 ms to 42 ms (beta.3: 45 ms), and the owner confirmed the improved start. Coordinator checks enforce preparation order and keep canceled captures silent.
- [x] Default Begin at to 90° and Resume desktop after pause to on for fresh settings and page reset, preserving saved preferences.
- [x] Add one saved Connection effect switch for glow and sound together across assisted opening, Pause and Esc, enabled by default and included in Seamless Close reset. Use the supplied four-corner icon and cover off-state silence, unchanged return motion and live cancellation synthetically.
- [x] Refine the shared connection glow with a wider pearl bloom and continuous corner field. Soften its rhythm with opacity easing, a 65 ms brightness lead-in to the click peak, a stationary crest and a 320 ms fading release with gentle contraction. Physical feel remains pending; the regression suite was not rerun for this refinement.
- [ ] Physically check the refined bloom on light and dark desktops during assisted opening, Pause and Esc; compare the quick, soft snap with the click, the fading tail and corner continuity at normal viewing distance.
- [ ] Physically check Pause and Esc feedback at shallow and deep folds, mouse access during the glow retreat, and peak alignment on built-in speakers and Bluetooth, and cancellation on reversal, sleep, lock, Space/display changes and quit. Already-buffered wireless audio may outlast a late interruption.
- [ ] Physically compare fast and slow assisted opening with the 5° trigger, connection glow and click, a stop in that region, a quick reversal, and another close from a partially open lid on the development Mac. Include accelerating through takeover to compare the momentum correction against the reported braking. Confirm the audible peak feels aligned with the glow peak and pending playback cancels on interruption.

- [x] Add **Detect starting angle** and implement resting-angle selection one degree below the held angle, **Begin at** fallback, gesture and wake reference locking, and adoption of a lower angle after eligible pause restoration. Its saved wait is independently adjustable from 0.5 to 10 seconds, defaulting to one second. A saved 20–130° detection threshold gates learning independently of **Begin at** and restores that fallback after a pause at or below the threshold; 0° disables the threshold.
- [x] Let closing past the learned angle restart the animation after automatic pause restoration, without requiring the lid to open farther first.
- [ ] Physically verify automatic angle learning, changes to the manual fallback, pause restoration, reversal, sleep/wake, and sensor gaps on the development Mac.

- [x] Implement capture metadata preparation, backing-pixel validation, and overlay-only exclusion with a safe hidden-overlay fallback that preserves known settings windows; retain one screenshot per gesture.
- [x] Implement acquisition-timed smoothing, higher active polling, display-linked motion and opacity, a prepared closing entrance at the latest measured angle, velocity-aware returns, and bounded cleanup when display callbacks stop. Keep one-shot screen capture off the main queue so lid delivery continues during capture.
- [x] Implement a reusable Gaussian blur pyramid, linear-light material rendering, and fixed shadow-gradient dithering; add numeric timing diagnostics and a display-sized synthetic GPU benchmark.
- [x] Measure finishing-blur frame pacing on the development Mac and remove a redundant alpha erosion and blend. Repeated instrumented closes reduced late render callbacks; the owner saw the same blur appearance but no clear change in feel. Motion timing and screenshot capture are unchanged.
- [x] Complete local build, motion/capture/Metal/lifecycle/overlay regression checks, capture-metadata validation, and settings-window launch for these changes.
- [x] Obtain owner approval of the top-bezel contact shadow on the development Mac and pass the local build and full regression suite after its tuning (2026-09-21).
- [ ] Compare entrance, awake and cached-wake exit, deep-fold pause restoration, and material quality on the target Mac. Include the adjusted Regular blur at 68°, 50°, and 25° from a 90° start. Measure real sensor changes, presentation intervals, memory, and power before claiming an improvement in physical smoothness.

- [x] Prepare an initial wake-opening prototype with immediate reconnection, remaining-angle motion, bounded eligibility, local timing diagnostics, and synthetic cancellation checks.
- [x] Correct loss of numeric wake eligibility when a lock/session notification follows sleep, and cover lock-before-wake, lock-after-wake, unlock with remaining motion, completed opening and timeout sequences in synthetic checks.
- [x] Correct premature sensor-loss cancellation by a heartbeat delivered immediately after wake, preserving the bounded sensor-recovery and wake deadlines.
- [x] Replace fresh wake capture with the completed closing image and prepared texture, retained in memory through lid-close sleep. Add hidden retention, lock ordering, skipping when no frame is available, cleanup checks, and updated privacy copy.
- [x] Obtain owner confirmation that cached opening works well on the development Mac after the faded-window reports.
- [ ] Measure remaining wake-to-visible delay and repeat appearance checks across lock states and opening speeds. The earlier fresh-capture trials exposed a blink and 283–356 ms preparation latency; cached pixels alone do not establish control of the first visible screen frame. See `docs/TESTING.md`.
- [ ] Physically validate wake timing, quick/slow full-lid reopening, lock/unlock, fullscreen and external-display transitions on the target Mac. Verify the undocumented lock hints on supported macOS versions before describing wake opening as dependable.

- [x] Allow Seamless Close's overlay to join another app's full-screen Space with settings open or closed, without activating Glissform; verify visibility with a separate full-screen app and retain physical acceptance as a separate gate.

- [x] By default, hide the Dock icon when Settings closes, keep Seamless Close and menu bar access running, and restore the window and Dock icon when reopened without adding a permission requirement. General allows quitting on close or hiding the menu bar icon; with background running on, the Dock icon hides on close in either case.

- [x] Integrate the centred, inset blue glass-wave icon with distinct light and dark bases plus native clear and tinted appearances. Preserve the same material shading in every style; verify native compilation, all six rendition exports, Finder style changes, and the running app's Privacy & About icon on macOS 27.
- [x] Correct the Dock placeholder after resetting the native launch icon and refreshing development bundle registration; the owner confirmed the icon displays correctly.
- [x] Use a monochrome menu bar template derived from the actual Clear app icon, sharing the Icon Composer source and using the system foreground colour.
- [ ] Verify the compiler-generated legacy icon on an earlier supported macOS version.

- [x] Bundle interface vectors locally, using supplied feature icons for Seamless Close and Battery Ripple and Iconly Bold / Regular for supporting controls. Retain Iconly Bulk, Outline, and the previous Custom mix as alternatives with live switching in developer builds.

- [x] Establish shared spacing, typography, surfaces, permission-state colours, and control feedback across settings and About.

- [x] Show missing screen access on the main page, briefly confirm detected grants, and keep persistent access status and management in Privacy & About.

- [x] Add optional desktop restoration after a still-lid pause, with a persisted toggle and gesture/cancellation regression checks. Its saved wait is independently adjustable from 0.5 to 10 seconds, defaulting to one second.
- [ ] Physically validate pause-to-resume timing and jitter tolerance during slow movement, lower-angle work, and sleep transitions.

- [x] Correct full-angle hinge compensation, smooth quantized-input tracking speed, reduce entrance delay, and tune progressive full-image frost toward the supplied Duo references; add synthetic desktop material previews alongside projection, tracking and lifecycle regression checks.
- [ ] Evaluate slow/fast closing, pauses, abrupt reversals, and capture handoffs with repeatable physical tests.
- [ ] Investigate any remaining visible angle steps, flashes, or discontinuities with measurements rather than only stronger easing.
- [x] Refine degree-cadence smoothing, reject brief one-degree direction chatter, preserve reversal velocity, keep manual reopening lid-driven through zero, and reduce pause-return peak speed without changing the visual material or projection. Included in alpha.9; see the changelog.
- [x] Prototype a quicker response to sustained fractional lid readings, with synthetic tracking, stop, reversal, and noise checks. Measure a continuous fast close on the development Mac: fractional and whole-degree reports change together about every 100 ms. Add a bounded continuation for fast sparse readings and replay the measured trace alongside abrupt-stop checks. Visual geometry remains unchanged.
- [ ] Physically compare the refined motion against the alpha.8 checkpoint at slow and fast speeds, including the added smoothing delay, deliberate one-degree reversals, abrupt stops, shallow/deep pause returns, reclose during return, and sleep/wake.
- [ ] Physically compare the sparse-reading continuation and the finer slow response with the previous build on the development Mac; check lag, pace evenness, abrupt stops, reversals, final manual opening, and frame pacing before claiming a visible improvement. Compare whole-degree fallback when compatible hardware is available.
- [ ] Compare fast closing before and after early single-screenshot preparation on the development Mac; check time to first visible motion, still or reversing lid cancellation, screenshot freshness, sleep, and Space changes.
- [ ] Measure capture latency, frame pacing, CPU/GPU load, memory use, and idle/battery impact.
- [ ] Strengthen recovery from denied/revoked permissions, unavailable screenshots, sensor disconnects, and display changes.
- [ ] Test full-screen applications, Dock/menu behavior, external displays, multiple Spaces, sleep/wake, and quitting during transitions.
- [x] Prepare structured GitHub submissions for bugs, suggestions, and community compatibility reports, with tested-hardware information and an explicit pre-download status on the project page.
- [ ] Build a compatibility table from owner and community reports, distinguishing reported results from maintainer verification.
- [x] Refine the native interface with compact navigation, adaptive neutral surfaces, a distinctive perspective illustration, and a clearer control hierarchy.
- [x] Add a capture-free, in-window gesture preview with a still alternative for Reduce Motion and contextual first-gesture guidance.
- [x] Introduce and simplify native settings with a dedicated live-angle display, precise trigger controls, and screen-access status, and an About page with prominent privacy information.
- [ ] Validate the settings and permission guidance with first-time testers, including keyboard and VoiceOver use, then refine onboarding and diagnostics.
- [ ] Decide the project's license before describing it as open source.

## Beta gate — 0.1.0-beta.1

Keep this a practical release check for a small passion project:

- Fix the known full-screen Space-switching bug and confirm everyday animation still works on the development Mac.
- Run the existing build and regression checks on the intended release build.
- Check that normal desktop access returns when the effect stops or the app quits, and that sleep and the lock screen behave normally.
- Build and verify a release-tag-specific `.dmg`, then test a fresh installation and both update modes on the development Mac.
- Provide a usable installation and permission flow for an ad-hoc signed download, with honest tested-hardware and known-limitation notes.

The broader investigations below and above are follow-up work, not a requirement to complete every roadmap item before beta. Other additional features are not required for launch; improve the app incrementally after release.

## Beta.3 — 0.1.0-beta.3

- [x] Make bundled interface resources load independently of SwiftPM's Xcode-specific bundle accessor, normalize the release bundle structure, and check that structure in the packaged DMG.
- [x] Check the signed feed at launch and hourly; retain a detected manual update until a later check finds none.
- [x] Confirm the published beta.3 DMG launches, the signed feed includes beta.3, and the website points to its live download. Screen Recording access remained allowed after direct installation on the development Mac.
- [ ] Verify the actual beta.2-to-beta.3 Sparkle upgrade and permission state afterward; manual and automatic update modes still need physical checks.

## Beta.2 — 0.1.0-beta.2

- [x] Make local builds visually distinct as Glissform Dev with a red icon, separate app identity and settings, and no public updates. Keep tagged release builds blue with signed updates.
- [x] Add a Utilities application category to future app builds for Spotlight's app browser. Confirm appearance from an installed build when beta.2 is tested.

- [x] Replace the **Send feedback** placeholder with an email action addressed to support@glissform.app that includes the current app and macOS versions, an icon to copy the address, and concise guidance. The source repository and GitHub forms remain private. The owner confirmed a test email arrived on 2026-09-30.
- [x] Add Escape to exit an active Seamless Close animation whether **Resume desktop after pause** is on or off, with an always-visible shortcut hint in the first Seamless Close card. A visible image uses the pause feature's fold-to-flat return before releasing its capture; a pending capture is canceled immediately. Reopening above the start angle is required before another gesture. Synthetic checks cover pending and visible captures plus return interruption. On 2026-09-30, the owner confirmed the return with Pause enabled, a fresh close after reopening, and stable card layout when toggling Pause. Broader sleep, Space-change, and quit interruptions remain synthetic-only for this shortcut.

## Release candidate and stable — 1.0.0-rc.1 → 1.0.0

- [ ] Confirm everyday use on the documented tested configuration, with no known release-blocking failures.
- [ ] Reassess Developer ID signing and notarization; if the app remains ad-hoc signed, keep the installation warning and permission limitations explicit.
- [ ] Verify the public `.dmg`, download links, installation instructions, and update path for the intended release.
- [ ] Verify installation, upgrade, and removal on supported macOS versions.
- [ ] Confirm normal desktop access is restored after errors and interruptions.
- [ ] Finalize privacy documentation, support instructions, and release notes.

A release candidate is a complete proposed stable build. Publish 1.0.0 when those checks pass. A wake-opening animation is not a prerequisite.

## Further possibilities — not committed

- Lock Screen support for Seamless Close, if a privacy-safe design can be implemented and physically validated. It has no target version or date; the current Settings card says Soon, but no animation plays while the Mac is locked.
- Touch ID feedback: a similar ripple spreading from the bottom-right corner with a red haze. Idea only; the exact Touch ID event and feasibility still need to be determined. Not implemented.
- Broader wake-opening support after the prototype passes timing, privacy, and physical acceptance gates; no first-frame or locked-wake guarantee.
- Carefully bounded blur, shadow, and motion preferences or presets.
- Accessibility options and behavior that respects reduced-motion preferences.
- Broader hardware support and calibration for different viewing angles.
- Other visual feedback and transitions for everyday Mac interactions, where they add clarity or enjoyment and can be delivered reliably.
- Additional distribution channels after platform requirements are assessed.

## Version policy

- Alpha: `0.1.0-alpha.1`, `0.1.0-alpha.2`, and so on for public test builds.
- Beta: `0.1.0-beta.1`, then numbered beta builds.
- Release candidate: `1.0.0-rc.1` and subsequent candidates if required.
- Stable: `1.0.0`; fixes become `1.0.1`, compatible feature additions `1.1.0`, and breaking changes `2.0.0`.

Not every commit needs a release. Move shipped work into the changelog and revise this roadmap whenever priorities or readiness criteria change.
