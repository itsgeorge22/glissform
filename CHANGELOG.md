# Changelog

User-visible changes are recorded here. Public versions use prerelease suffixes and Git tags such as `v0.1.0-alpha.1`. Unpublished work belongs under **Unreleased**; released entries remain a historical record.

## Unreleased

### Added

- A concise GitHub project overview, detailed app guide, and structured forms for bug reports, feature suggestions, and community compatibility reports. Clarify that public app downloads and installation guidance will follow publication of a `.dmg` on GitHub.

### Changed

- Add a top-bezel contact shadow driven by the first few displayed degrees of closure, with a dark upper edge and soft falloff that spreads downward. Preserve the lighter lower image and unchanged flat frame. The owner manually tested and approved its appearance on the development Mac on 2026-09-21; the local build and full regression suite also passed.

- Prepare capture metadata before a gesture without taking idle screenshots. Capture dimensions now follow ScreenCaptureKit's point-to-pixel scale and must match the overlay's backing dimensions. Exclude the animation overlay while preserving known Glissform settings windows, including when the hidden overlay is absent from capture metadata.
- Replace the closing entrance dissolve with a prepared, full-opacity flat frame and a 100 ms geometric handoff. Use one display-driven timeline for motion and opacity, a short cached-opening fade, and a velocity-aware return followed by a 50 ms fade to the live desktop. Deeper pause restorations have a longer, bounded return; a cleanup watchdog restores desktop access if display callbacks stop.
- Timestamp lid readings at acquisition, separate sensor cadence from rendering, and request 60 Hz polling during active gestures while retaining 30 Hz idle polling. Actual sensor updates remain hardware-dependent; smoothing does not invent angles beyond the latest reported reading.
- Prepare a Gaussian blur pyramid once per screenshot, use linear-light filtering and shading, and add fixed spatial dithering to the shadow gradient. The unchanged flat frame, progressive frost, and full-angle projection are retained.
- Add capture-metadata and motion-timing regression coverage, opt-in numeric sensor/presentation diagnostics, and a synthetic GPU benchmark that defaults to the built-in display's current backing dimensions.

### Validation and limitations

- On 2026-09-21, the owner confirmed smoothness, speed, abrupt lid stops, reversals, and opening after sleep without locking on the development Mac. The owner also reported that switching Spaces while a full-screen app is open breaks the animation; this remains unresolved. This confirmation does not cover locked wake or replace automated regression checks.

- After the latest upper-shadow tuning, the build and full automated motion/wake/capture/Metal/lifecycle/overlay checks passed locally on 2026-09-21. The live capture-metadata check and running-app launch passed before that tuning. Repeatable physical acceptance of closing, reopening, pause restoration, wake/unlock, scaled display modes, and performance remains required. Higher polling and display-linked rendering are not guarantees of a higher sensor update rate or invisible screenshot handoff.

## 0.1.0-alpha.6 — 2026-09-20

Sixth public alpha: consistent closing and post-sleep opening using the same screenshot, background operation when settings close, and support for overlays in other apps’ full-screen Spaces. The owner confirmed the cached opening works well on the development MacBook Air M5 15-inch; broader wake, unlock, display, and hardware acceptance remains ongoing. Source release; local builds remain ad-hoc signed and are not notarized.

### Added

- Experimental opening after lid-close sleep: retain the completed closing screenshot and its prepared texture in memory, reconnect immediately, and reuse the same image for remaining upward movement after unlock. No fresh wake capture or texture upload is needed. A three-second wake window rejects late, stale, reversed, or unavailable-desktop attempts; missing closing images skip without recapturing. Opening completion, cancellation, session/display changes, screen-access loss, setting changes, and quit release the image. Privacy & About explains the retention. No extra permission or sleep prevention is introduced; the owner confirmed the main opening behavior on the development Mac, while broader wake and unlock acceptance remains pending.

### Fixed

- A heartbeat queued during sleep now gives the restarted sensor its normal one-second recovery window instead of immediately cancelling wake opening from an old pre-sleep timestamp. Actual sensor loss still clears pending and visible effects; the three-second wake deadline is unchanged.

- Lock notifications around sleep keep the retained closing frame hidden and preserve the original wake deadline. A one-second grace period covers lock arriving just before near-closed sleep; ordinary locks and session switches still discard images. Sensor readings continue to evaluate remaining motion while locked without capturing or revealing pixels. Completed openings skip. Local timing logs distinguish retained-frame preparation, lock/session state, missing evidence, and timeouts. Diagnostic app runs start without a Dock entry and successful UI checks exit through AppKit.

- Infinite Screen's overlay can now appear over another app in a native full-screen Space even while Glissform's settings window is open. The overlay uses a non-activating panel that can join other apps' Spaces, preserving the foreground app, keyboard focus, and background Dock behavior.

### Changed

- Closing the settings window now removes Glissform from the Dock while Infinite Screen and the menu bar keep running. Reopening Settings or opening the app again restores the window and Dock icon. No additional permission is required; Quit still stops the app completely.

- Replaced the laptop menu bar symbol with a monochrome template derived from the actual Clear app icon at 18 points in 1× and 2× resolutions. Its original wave and contours become opacity detail; macOS supplies the foreground colour. Developer icon switching leaves it unchanged. The build validates the encoded template opacity to catch invisible output.

## 0.1.0-alpha.5 — 2026-09-20

Fifth public alpha: a new native glass-wave app icon with light, dark, clear and tinted appearances, corrected Dock icon display, and tighter window and Privacy screen layout. Source release; local builds remain ad-hoc signed and are not notarized.

### Changed

- Replaced the runtime-drawn app icon with a centred rounded blue glass wave, a pearl-white/light-silver Default base, and a graphite Dark base. A smaller foreground retains the selected artwork's rim, highlights and soft wave shading; native clear/tinted styles derive from that same artwork instead of a flat vector silhouette. macOS controls the icon appearance through System Settings. The build now requires Xcode 26 or later and packages both the native catalog and a legacy icon; older-macOS runtime appearance remains unverified.

- Refresh the app bundle's modification date after development builds and reset AppKit's Dock icon to the bundled asset after foreground activation, addressing stale placeholder icons without overriding native appearance selection.

- Reduced the Privacy header’s icon-to-text spacing from 16 to 8 points.

- Matched Back to the filled Preview motion button style, retaining its tighter 2-point arrow-to-label spacing.

- Settings window height follows the visible page content, keeping 32-point bottom padding after cards disappear or pages change. Content still scrolls when capped by available screen space.

## 0.1.0-alpha.4 — 2026-09-20

Fourth public alpha: a refined native interface, clearer permission flow, unified Iconly icons, and simpler pause-to-resume controls. Glissform is positioned as a broader app for animations and quality-of-life improvements, with Infinite Screen as its first feature. No additional experience is introduced in this release. Source release; local builds remain ad-hoc signed and are not notarized.

### Added

- Developer builds provide a live Bulk / Bold / Outline / Custom icon style switch in the Developer menu, with keyboard shortcuts and immediate updates across settings, About, and the menu bar. Normal builds hide it; each session starts with Bold.

- A screen-access card above the preview explains required permission and opens macOS settings. After a detected grant it briefly confirms success, then leaves the main screen; the same card remains in Privacy & About for status and management. The card uses one supporting line and an Iconly shield inside a rounded tinted square: green when allowed and amber when required. The settings page scrolls on smaller displays.

### Changed

- Broadened product positioning and the roadmap beyond Infinite Screen, while keeping implemented features and future direction distinct. Updated architecture, design, contribution, and testing guidance to match the current app.

- Simplified Privacy & About to the Glissform name and version above the privacy and access cards; removed the introductory description and text below the cards.

- Replaced the access section inside the privacy information card with the shared standalone access card, removing the old section and divider. Already-authorized launches omit the main-screen access card; revocation brings it back.

- Permission and pause card icons use vivid Dark Mode colours, with a modest darkening in Light Mode; tile backgrounds remain at 16% opacity. The previous Custom Bulk treatment remains available for comparison.

- Replaced permission and pause icon gradients with solid semantic colours at 16% opacity, with appearance-aware icon colours and no decorative border.

- Simplified slider endpoint labels to 20° and 130°, removing “Later” and “Earlier”.

- Removed the angle field’s left inset so the arrow containers sit flush with its left edge. Moved each arrow glyph 2 points toward the centre, tightening their visual gap while preserving the full clickable containers.

- Standardised interface and menu bar icons on Iconly Bold / Regular, including permission states, pause, preview playback, angle arrows, privacy details, and synthetic preview artwork. Bundled SVG vectors work offline and retain adaptive colours and existing control feedback. The complete Outline / Regular and Bulk / Regular sets and previous Custom mix are preserved, with a shared live developer style selector for easy comparison.

- Simplified pause-to-resume into one row with a matching rounded tinted pause icon. Removed the internal divider and delay control; the feature now uses a fixed two-second pause and ignores previously saved custom delays.

- Formalised shared settings styles: a 4-point spacing scale, consistent 14-point control titles, clearer supporting text, unified card surfaces and 8-point control corners, and shared hover, pressed, and disabled treatments.
- Matched the About card to the main cards, removed the negative slider-footer spacing adjustment, and enlarged angle-arrow targets while retaining the compact number field.

## 0.1.0-alpha.3 — 2026-09-19

Third public alpha, adding pause-to-resume desktop access and a refined settings layout. Source release; local builds remain ad-hoc signed and are not notarized.

### Added

- Optional “Resume desktop after a pause,” off by default, with a saved 0.5–10 second delay (default 2 seconds). Holding the lid still below the trigger smoothly restores desktop access. The effect stays inactive until reopening above the trigger; movement restarts the wait, one-degree sensor jitter is tolerated, and normal sleep remains unchanged.
- Regression checks for pause timing, movement, sensor gaps, pending and visible captures, rearming, and interruption during automatic restoration.

### Changed

- Motion preview starts immediately from the illustration's current lid angle and reference plane, then closes and returns to that starting angle.
- Grouped starting-angle controls inside the preview card and pause-to-resume controls in a separate matching card, replacing the status card. Readiness remains in the menu bar; screen-access management remains in Privacy & About.
- Removed extra illustration captions and the live-angle slider marker. Both card dividers span the full width, with controls inset and 20-point spacing around the pause-card divider.
- Refined the angle field, independent arrow hover states, title styling, and text spacing. Kept 16 points between cards, balanced 28-point outer section gaps, and uniform 32-point content padding. About remains scrollable.

### Validation and limitations

- Build, motion, Metal-rendering, and synthetic lifecycle checks passed. The settings layout and preference persistence were checked in the running app.
- Physical pause-to-resume timing, jitter tolerance, and sleep-transition acceptance remain pending; synthetic checks do not establish hardware compatibility or physical smoothness.

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
