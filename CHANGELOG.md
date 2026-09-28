# Changelog

User-visible changes are recorded here. Public versions use prerelease suffixes and Git tags such as `v0.1.0-alpha.1`. Unpublished work belongs under **Unreleased**; released entries remain a historical record.

## Unreleased

### Added

- Preview a compact update-available card at the bottom of the Settings sidebar, with the download icon, a sample version subtitle, and an Update button that responds visually but does not run an update yet.
- Show an Automatic updates card in General with the supplied download icon and an outlined Soon tag. This is a visual placeholder; the app does not check for or install updates.
- Add three selectable gray image placeholders beneath the Blur switch for High, Regular, and Subtle strength. Regular is initially outlined in the system accent color, matching enabled switches, with a 4-point gap around its placeholder; choosing a strength does not change the effect yet.
- Add a saved **Detect above** angle to Seamless Close's automatic-selection card. Automatic detection learns only after the lid rests strictly above this angle; **Begin at** remains the fallback until then, even when the detection threshold is below the manual angle. Set it to 0° to disable the threshold. Changing the threshold while automatic detection is on clears the learned angle and any active snapshot; while it is off, a manual gesture continues. The default is 20°.
- Add independent, saved 0.5–10 second wait controls for automatic starting-angle detection and desktop restoration after a pause. Both default to one second; changing a wait restarts its pending timer.
- Show planned Lock Screen support in Seamless Close settings with a non-interactive outlined Soon chip. The locked-screen animation is not implemented yet.
- Add a saved Blur switch to Seamless Close, on by default. Turning it off skips both blur passes while keeping perspective and shadow, including during the current gesture.

### Changed

- Use the native pointing-hand cursor for active Settings controls, including the visual-only Update button; show the system operation-not-allowed cursor for disabled buttons, switches, and step arrows. Text entry, sliders, and Soon tags retain their usual cursors. Raise the unreleased app's minimum system version to macOS 15.
- Add a softer hover to angle and wait-time fields. Arrow highlights sit flush against the field's left edge without their own rounded corners; the field clips them to its outer shape. Blur strength hover darkens only the placeholder image, while its selection outline stays unchanged. Battery Ripple preview buttons use the same subtle neutral hover as the fields and a slightly darker pressed state. Give the sidebar Update preview hover and pressed states without adding update behavior.
- Give Lock Screen support a neutral gray icon and tile, move Blur to the former light-blue detection color, and give Detect starting angle a muted violet icon and tile.
- Use the supplied raindrop icon for **Blur** and scan-object icon for **Detect starting angle**.
- Separate the starting-angle and desktop-resume switch rows from their wait controls with full-width dividers. Give all three Seamless Close control sections 24-point padding while keeping 24-point trailing padding on switch rows. Use the angle field's paired arrow controls for both wait times, with a title and explanatory subtitle beside each.
- Keep Seamless Close's finishing blur appearance while removing a redundant full-screen alpha erosion and blend. On the development Mac, instrumented closing passes showed fewer late render callbacks with Blur on; the owner found the appearance unchanged but did not notice a clear difference in feel. The motion curve, Blur switch, and one-screenshot capture remain the same.
- Start Seamless Close from a prepared frame at the latest measured lid angle instead of showing a flat screenshot first. Run the one-shot screen capture away from the main queue so lid readings continue during capture. The owner found the entrance sooner and more natural on the development Mac; remaining capture and presentation delay still varies. The screenshot count and privacy behavior are unchanged.
- Use smooth, coordinated geometry for Seamless Close's image content and upper edge, replacing the early/late rotation handoff. Restore a stronger response in the first degrees while keeping the later fold active below a 60° lid angle and limiting deep vertical stretch. Spread blur buildup through the full gesture while reducing its final strength by about 20% at the top and 30% at the hinge. Keep lid-driven timing and the single-screenshot behavior. The owner approved the revised closing feel on the development Mac on 2026-09-28; broader gesture and material checks remain pending.
- Let consecutive fractional lid readings shorten Seamless Close's smoothing delay during steady, slow movement. For fast closes with roughly 100 ms gaps between meaningful readings, carry a short, damped motion estimate through each gap instead of repeatedly accelerating and settling. Whole-degree slow motion retains its earlier response. The measured fast-close replay reduced speed variation, while synthetic abrupt-stop and reversal checks remain bounded; the change still needs physical lid comparison.

### Fixed

- Apply **Detect above** during pause restoration too. A still lid at or below the threshold restores the desktop without learning or rearming from that angle, and clears any previous learned angle so **Begin at** takes over.

## 0.1.0-alpha.9 — 2026-09-27

Ninth public alpha: Battery Ripple joins Seamless Close, with a reorganized Settings window, new General controls, and further lid-motion and material refinements. Source release; local builds remain ad-hoc signed and are not notarized.

### Added

- Add a General Settings page with saved switches for background running and menu bar icon visibility. Closing Settings while background running is on removes Glissform from the Dock regardless of menu bar icon visibility; opening the app again restores Settings. Turning off background running quits Glissform when Settings closes.
- Add Launch at login to General using macOS’s main-app login service. The switch reflects the system’s current status and explains when approval or setup fails.
- Add Features and More section titles in the Settings sidebar, with a Send feedback tab that opens a placeholder page reading “Nothing here yet.”
- Add Battery Ripple as a second experience: a translucent wave unfurls from the built-in display's lower-left corner when power connects (emerald) or the built-in battery crosses down to 20% while unplugged (red). The events have independent saved Settings and menu-bar switches, with no overall feature switch. Its curling edge and soft internal folds dissolve over 2.15 seconds. It takes no screenshot, needs no new permission, does not take focus or mouse input, and stops on sleep, lock, Space/display change, disable, or quit. Reduce Motion uses a shorter static glow. The owner confirmed one green ripple on one unplug/reconnect trial with the earlier visual design and approved the revised emerald appearance on 2026-09-26. The red ripple and broader interruption and full-screen behavior await physical confirmation.

### Fixed

- Restore the same menu bar status item when its General switch turns back on, so toggling the icon off and on does not lose its menu bar position.
- Link the app against the selected macOS SDK so the Settings window uses current native window controls on newer macOS versions while retaining its macOS 14 minimum.
- Replace the app's copied resource bundle on rebuild so removed icons do not remain in the built app.
- After automatic angle selection restores the desktop at a paused lid angle, closing past the newly learned starting angle starts a fresh animation without first opening the lid farther.
- Spread frost-gradient dithering across neighboring rows and columns to reduce horizontal banding in pale areas caused by the repeated 8-bit output pattern.
- Smooth the projected screenshot's side boundaries as one continuous blurred edge to reduce the parallel dark contours left by separately clipped blur samples.

### Changed

- Replace General’s card icons with the supplied checked-window, grid-interface, and user artwork for background running, menu bar access, and login launch.
- Place General first in the Features group in the Settings sidebar.
- Use gray sidebar tiles for General and Privacy & About, gray icon tiles and symbols throughout General, and a muted red sidebar tile for Send feedback.
- Rename the lid-driven desktop feature from **Infinite Screen** to **Seamless Close** in Settings, the menu bar, and current project guidance.
- Align Settings descriptions around short, one-line explanations; use the same “1-second lid pause” wording for both Seamless Close controls. Update Privacy & About to describe Glissform’s local data use and temporary screen images as a whole.
- Add a small circular icon-only preview button beside each Battery Ripple switch to play its green or red ripple on demand, including when that event is off.
- Shorten the still-lid wait for automatic starting-angle detection and pause-to-resume from two seconds to one second.
- Narrow the starting-angle input by 4 points while retaining space for three-digit values.
- Give the combined Seamless Close card’s angle section 20-point padding and scale its angle field, number, degree symbol, and step arrows down together.
- Use a hinge-and-angle icon with a light-blue symbol and tile for automatic starting-angle detection, distinct from Seamless Close’s darker indigo.
- Combine the Seamless Close switch and manual starting-angle controls in one card, with a full-width divider between the enable row and angle settings.
- Loosen 24-point settings headline tracking to −0.24 point, about −1% of the font size.
- Keep sidebar tab labels at medium weight when selected; the row highlight indicates selection.
- Slightly darken and desaturate the Battery Ripple sidebar icon tile.
- Give every switch card 12-point top, bottom, and left padding and 24-point padding beside the switch. Use 16-point corners for all Settings detail cards and 12-point corners for their icon tiles.
- Use the supplied empty-battery, charge-battery, low-battery, monitor, and messages vectors for Battery Ripple, Power connection, Battery at 20%, Seamless Close, and Send feedback in Settings.
- Reduce the gap between the Seamless Close and Battery Ripple sidebar tabs to 4 points.
- Place the More group directly below the feature tabs and use title-case sidebar section headings.
- Keep the Settings window frame the same height as its rounded surface, removing the transparent toolbar-height strip below it. Use a wider, lighter shadow that follows the actual window frame.
- Organize Settings with a persistent sidebar and separate Seamless Close, Battery Ripple, and Privacy & About pages. Keep the window size steady while switching pages, retain each feature’s saved controls, and reset page scrolling on navigation.
- Refine Settings with a native unified toolbar and window controls over a narrower sidebar, compact selected rows, and smaller filled navigation icons. Give sidebar rows equal padding and a radius concentric with their icon tiles, and keep icons at full opacity while pressed. Clip the full-size content to round every window corner, use a fine edge outline. Remove the titlebar separator. Use subtle 12%-opacity icon tiles with coloured symbols inside the pages. Remove both feature preview illustrations and keep the Battery Ripple switches in separate cards. Group Seamless Close’s switch and manual angle in one card; automatic selection and pause remain in their own cards, retaining the live lid reading. Remove feature-page privacy notes; Privacy & About keeps the full explanation.
- Add a modest, even Core Image Gaussian blur after projection, blended more strongly toward the top, to soften fine texture in bright controls. Preserve the original projected edge near transparency and use the same captured frame and source-space frost. The owner preferred the resulting appearance on the development Mac; frame pacing has not been measured.
- Sample finer Gaussian blur levels with a wider 5×5 reconstruction kernel to reduce the blocky texture seen in bright controls while keeping the same nominal blur strength and soft side edges. Owner testing found an overall improvement, though fine texture remains visible on bright controls; frame cost has not been measured.
- On a fast close, request the single screenshot up to three degrees before the selected start angle after confirmed downward movement. Keep it hidden until the threshold is crossed, and discard it if the lid reverses or pauses before the effect begins. Physical validation of the first visible frame remains pending.
- Prefer the lid sensor's hundredths-of-a-degree report when available, with a whole-degree fallback. Ignore tiny sensor jitter in the motion target while keeping manual reopening controlled by the lid through the final angle; the settings reading still displays whole degrees.
- Let slow sub-degree lid changes contribute their actual size to motion smoothing, with a quarter-degree lower bound to limit lag. Whole-degree fallback and fast movement keep their existing response.
- Smooth Seamless Close's degree-to-degree speed using a short cadence history and gradual response changes. Brief one-degree direction chatter no longer triggers a fast reversal; confirmed reversals brake existing momentum instead of resetting velocity.
- Keep manual reopening on the same lid-driven smoothing through the final degree, with no separate return trajectory. Continue sensor updates until the image is flat, and preserve direct tracking if the lid recloses before cleanup. Give pause restoration balanced acceleration and a longer, fold-dependent 340–600 ms return with a lower peak speed. Keep the existing perspective, stretch, blur, gradients, shadow, screenshot model, and final fade.
- Stabilize only the Settings lid-angle number: a one-degree change appears after 250 ms of continuous readings, while a change of two degrees or more appears immediately. Animation, automatic angle selection, and **Use current angle** continue to use raw sensor readings.

### Validation and limitations

- The release build and automated motion, capture, Metal, lifecycle, and overlay checks passed locally on 2026-09-27. Synthetic checks bound tracking delay, speed variation, reversal continuity, return speed, and cleanup; they do not establish physical smoothness or capture timing.
- The owner confirmed one green Battery Ripple trigger with an earlier design and approved the revised emerald appearance on the development Mac. The red 20% event, live interruption and full-screen behavior, refined Seamless Close motion, automatic-angle and pause timing, and broader sleep/wake behavior still need physical confirmation. Other Mac models remain unverified.
- This is a source-only prerelease. No signed, notarized installer or public `.dmg` is available.

## 0.1.0-alpha.8 — 2026-09-26

Eighth public alpha: automatic starting-angle selection, clearer settings states, distinct feature colours, and a smoother pause restoration. Source release; local builds remain ad-hoc signed and are not notarized.

### Added

- Activate **Set starting angle automatically**: a steady open lid for two seconds sets the next closing angle one degree below the held angle, overriding **Begin at**. Until an angle is learned, **Begin at** remains the fallback. Once learned, its saved controls dim and become unavailable until automatic selection is switched off. The learned angle stays fixed through a gesture and eligible wake opening. If pause-to-resume is also on, restoring the desktop at a lower paused angle adopts a threshold one degree below it without immediately rearming; reopening above the held angle permits the next gesture. Switching the option off restores manual control.

### Changed

- Give the two-second pause restoration a longer, front-loaded ease into the live desktop, with an exact flat finish and no bounce.
- Give automatic angle selection a blue-leaning indigo icon tile and desktop restoration a green one, so the two feature actions are easier to distinguish.
- Label the live lid reading, show saved-settings guidance when Infinite Screen is off, and clarify the waiting message before a new automatic angle is learned.
- Clarify that a still lid sets or updates the automatic starting angle, while a lid pause below that angle restores the desktop.

### Validation and limitations

- The release build and automated motion, capture, Metal, lifecycle, and overlay checks passed locally on 2026-09-26. The new pause curve was checked for monotonic motion and an exact flat finish in synthetic tests.
- Automatic-angle learning and the new pause-return feel still need physical lid validation on the development Mac. Prior physical confirmation of closing, reversals, and opening after sleep without locking remains limited to the earlier alpha.7 behavior. Wider hardware compatibility and locked wake remain unverified.

## 0.1.0-alpha.7 — 2026-09-21

Seventh public alpha: smoother display-linked motion and screenshot handoffs, refined frost and contact shadow, safer Space switching, stronger capture validation, and expanded public project guidance. Space changes now keep a visible snapshot in its source Space and cancel the gesture after the transition; physical confirmation of the full-screen transition remains pending. Source release; local builds remain ad-hoc signed and are not notarized.

### Fixed

- Keep a visible Infinite Screen snapshot in the Space where its gesture began so macOS does not duplicate the same frozen image on both sides of a Space-switch animation. Clear it when the active Space changes, release mouse input, discard its capture metadata, and require the lid to reopen above **Begin at** before a fresh animation can start in the new Space.

- Repair the CI icon build configuration: use a macOS 26 runner and its maintained default Xcode, support both Xcode 26 and 27 Icon Composer export commands, and update checkout to Node.js 24. Run motion, wake, and synthetic capture checks before app packaging so icon errors no longer skip those checks.

### Added

- A concise GitHub project overview, detailed app guide, and structured forms for bug reports, feature suggestions, and community compatibility reports. Clarify that public app downloads and installation guidance will follow publication of a `.dmg` on GitHub.

### Changed

- Move active bug tracking to GitHub Issues and remove the README bug/limitations list, keeping a direct issue-tracker link in Feedback and support.

- Add a top-bezel contact shadow driven by the first few displayed degrees of closure, with a dark upper edge and soft falloff that spreads downward. Preserve the lighter lower image and unchanged flat frame. The owner manually tested and approved its appearance on the development Mac on 2026-09-21; the local build and full regression suite also passed.

- Prepare capture metadata before a gesture without taking idle screenshots. Capture dimensions now follow ScreenCaptureKit's point-to-pixel scale and must match the overlay's backing dimensions. Exclude the animation overlay while preserving known Glissform settings windows, including when the hidden overlay is absent from capture metadata.
- Replace the closing entrance dissolve with a prepared, full-opacity flat frame and a 100 ms geometric handoff. Use one display-driven timeline for motion and opacity, a short cached-opening fade, and a velocity-aware return followed by a 50 ms fade to the live desktop. Deeper pause restorations have a longer, bounded return; a cleanup watchdog restores desktop access if display callbacks stop.
- Timestamp lid readings at acquisition, separate sensor cadence from rendering, and request 60 Hz polling during active gestures while retaining 30 Hz idle polling. Actual sensor updates remain hardware-dependent; smoothing does not invent angles beyond the latest reported reading.
- Prepare a Gaussian blur pyramid once per screenshot, use linear-light filtering and shading, and add fixed spatial dithering to the shadow gradient. The unchanged flat frame, progressive frost, and full-angle projection are retained.
- Add capture-metadata and motion-timing regression coverage, opt-in numeric sensor/presentation diagnostics, and a synthetic GPU benchmark that defaults to the built-in display's current backing dimensions.

### Validation and limitations

- On 2026-09-21, the owner confirmed smoothness, speed, abrupt lid stops, reversals, and opening after sleep without locking on the development Mac. Space changes now deliberately cancel the current animation instead of carrying an old screenshot into another Space; the exact full-screen transition still needs physical confirmation. This confirmation does not cover locked wake or replace automated regression checks.

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
