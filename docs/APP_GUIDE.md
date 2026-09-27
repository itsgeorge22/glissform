# Glissform app guide

Glissform brings subtle animations and quality-of-life improvements to everyday interactions on your Mac. It is designed to make familiar gestures and system changes feel more expressive, clear, and enjoyable.

**Seamless Close is its first available feature:** your desktop appears to stay in place as you close your MacBook lid, with perspective, blur, and shadow responding to the movement. Glissform’s scope extends beyond this effect; additional experiences will be introduced as they are designed and validated.

**Current source prerelease: 0.1.0-alpha.9. The app is not yet available for public download.** A `.dmg` and installation instructions will be published on GitHub when ready. Development testing uses a MacBook Air M5 15-inch; wider compatibility is still being evaluated.

This source release includes the capture, motion, material, and Space-change improvements described below. Repeatable physical acceptance remains pending where noted.

Alpha.9 adds Battery Ripple as a second experience, along with the refreshed sidebar and General controls described below. Earlier alpha releases used the name Infinite Screen for Seamless Close.

[Changelog](../CHANGELOG.md) · [Roadmap](../ROADMAP.md) · [Contributing](../CONTRIBUTING.md)

## Current implementation — Seamless Close

- Takes one screenshot per closing attempt. A fast downward movement may request it just before your chosen lid angle; the image remains hidden until that angle is crossed. No continuous screen recording or idle capture.
- Animates that same image through closing, pauses, and eligible reopening, including after lid-close sleep.
- Includes experimental opening after lid-close sleep: it retains the completed closing screenshot and prepared texture in memory through sleep, then reuses them when the desktop is unlocked and opening movement remains. It takes no fresh wake screenshot. Missing closing images, completed openings, and late unlocks skip the effect; the owner confirmed the main opening behavior on the development Mac, with broader wake/unlock validation still pending.
- Closing starts at exactly zero stretch, blur, and shadow, then eases into the current angle. Wake opening prepares the current fold directly and follows the remaining opening movement.
- Follows the full lid rotation around a fixed hinge. A smooth bounded perspective response keeps image content moving through the gesture, with a stronger response in the first degrees and limited vertical stretch near closure. The upper edge begins narrowing immediately and stays visually aligned with the image content through a continuous fold; the hinge stays full width. A low starting angle produces less narrowing than a longer fold. Frost and shadow continue to follow the actual lid angle. The owner approved the revised closing feel on the development Mac on 2026-09-28; deep pauses, reopening, and the new Blur switch still need physical comparison with this geometry.
- Timestamps lid readings when acquired and uses recent reading cadence for critically damped smoothing. It prefers fractional angles when the sensor provides them and otherwise uses whole degrees. Tiny fractional jitter is ignored for animation; consecutive timely sub-degree changes shorten the smoothing delay during steady movement. Fast changes arriving about 100 ms apart use a short motion estimate between reports, limited to half the measured speed for at most 100 ms and no more than six degrees beyond the last reading. Flat is a hard endpoint. A fresh still or reversed reading brakes that estimate. An abrupt stop can therefore produce a small correction when the next reading arrives. Slow whole-degree motion retains its earlier response. Polling requests 60 reads per second during gestures and 30 while idle; the sensor's actual update rate remains a hardware limit. Rendering follows the display's presentation clock and pauses when settled. The revised motion has passed measured-trace and synthetic checks but still needs physical lid comparison.
- On a fast close, requests its single screenshot after confirmed downward movement up to three degrees before the selected start angle, but keeps it hidden until the angle is crossed. Reversing or pausing before the threshold discards that image. It replaces the live desktop with a prepared, full-opacity flat screenshot before a 100 ms geometric entrance. Manual reopening stays on the same lid-driven smoothing through the final degree. It does not start a separate return animation at the starting angle; the snapshot fades out over 50 ms only after the tracked image is flat. Pause restoration uses balanced acceleration without overshoot over 340–600 ms depending on the fold; cached wake opening uses a 50 ms entrance fade. The refined tracking and returns still require physical lid validation.
- Captures the display's backing pixel dimensions, checks that they match the overlay, and preserves known Glissform settings windows while excluding the animation overlay. Display and window metadata may be prepared in advance; no screen pixels are captured while idle.
- With Blur on, diffuses the entire image into a frosted-glass appearance as the lid closes, including the bottom. Fine text and icons soften while larger shapes retain enough definition to show the perspective skew; a smooth vertical gradient keeps the blur lighter at the hinge and heavier at the top. The animation experiment reduces final source blur by 30% at the hinge and 20% at the top, with the finishing blur similarly reduced, and spreads its buildup through the full gesture. Turning Blur off leaves the perspective and shadow active with a sharp image. The projected image fades into the surrounding black through a continuous soft edge. Reopening clears it continuously.
- Builds a Gaussian blur pyramid once from each screenshot, samples finer levels with a wider kernel for smoother bright details, filters and shades in linear light, and uses a subtle fixed dither to reduce visible steps in broad frost and shadow gradients. The flat screenshot remains sharp and unchanged by the material.
- When Blur is on, adds a modest, even Gaussian blur after the perspective render to soften fine texture in bright controls. It blends in more strongly away from the hinge, preserves the existing projected edge, and does not take another screenshot. The owner preferred its appearance on the development Mac; frame pacing remains unmeasured.
- Adds a soft contact shadow directly below the top bezel within the first few degrees of motion, spreading downward as the lid closes. Broader closure shading remains transparent at the bottom, darkest at the top, with only the top 5% reaching full black at the end.
- Provides a native settings window with separate Seamless Close, Battery Ripple, General, Privacy & About, and Send feedback pages, a live lid reading, independent Battery Ripple event switches, and precise starting-angle controls.
- Groups the Seamless Close switch, live lid reading, and manual starting angle in one card; automatic selection, pause restoration, and Blur have separate cards. Blur is on by default and can be changed during a gesture without taking another screenshot. A Lock Screen support card shows an outlined Soon label, with no active control or locked-screen animation yet. Battery Ripple keeps one card per event switch.
- Shows a screen-access card among the Seamless Close controls while permission is required. When access becomes available during the session, the card confirms success for three seconds, then disappears. The same card stays in Privacy & About for access status and management; already-authorized launches start without the main-screen card. Runtime readiness remains in the menu bar.
- Saves the Seamless Close, Blur, and automatic-angle toggles and the manual starting angle. The default manual angle is 100°; a learned angle lasts for the current app session.
- Optionally restores the live desktop after the lid pauses below the starting angle, so you can keep working at that angle. This is off by default and uses a fixed 1-second pause.
- Covers the live Dock and menu bar during the effect so their captured images animate with the desktop. Mouse clicks cannot pass through the snapshot.
- Displays the overlay in another app's full-screen Space with settings open or closed, without activating Glissform or moving keyboard focus from that app.
- Keeps the current effect in its original Space during a Space-switch animation instead of showing the same frozen image on both sides. It then clears the effect; the next animation remains disarmed until you reopen above the active starting angle and close through it in the newly active Space.
- Appears in the Dock while its settings window is open, with standard About, Settings, Edit, and Quit commands. With background running on, closing the window removes Glissform from the Dock while its effects keep running, whether or not the menu bar icon is shown. General can instead quit the app on close or hide the menu bar icon. When both icons are hidden, opening Glissform again restores Settings. The menu bar uses a monochrome template derived from the actual Clear app icon; macOS supplies its foreground colour for the background and selection state.

## Battery Ripple

When the built-in MacBook changes from battery to external power while the desktop is active, a translucent emerald wave unfurls from the built-in display's lower-left corner. When the built-in battery crosses down to 20% or less while unplugged, the same wave plays in red. A curling edge and soft folds spread and dissolve over 2.15 seconds. Repeated power-source notifications, launching while already plugged in, or launching at or below 20% do not replay an effect. The Battery Ripple page has two independent saved switches, **Power connection** and **Battery at 20%**, both on by default; matching menu-bar switches work while Settings is closed. Each card has a play button beside its switch to preview that event's color even when its automatic trigger is off. Preview uses the same screen and session safety checks as the automatic effect. There is no overall switch for the page. Neither effect takes screenshots, blocks clicks, moves keyboard focus, or requires Screen Recording access.

The Battery Ripple page shows one card for each event. Opening it does not start an overlay or capture screen content.

The active effect stops if the display sleeps, the session locks, the active Space or display changes, its switch is turned off, or Glissform quits. It does not draw over the login screen. Reduce Motion replaces the moving wave with a static glow that fades over 0.75 seconds. Automated checks cover both event transitions, both colors, transparent rendering, the corner origin, and the static reduced-motion shape. The owner confirmed one green unplug/reconnect trigger on the development Mac with the earlier visual design and approved the revised emerald appearance on 2026-09-26. The red event, refreshed settings interface, full-screen, lock, and reduced-motion behavior still need physical confirmation.

## Current alpha requirements

- macOS 14 or later and a Metal-capable MacBook with a compatible lid-angle sensor.
- Development target: MacBook Air M5 15-inch, model identifier Mac17,4. Other Macs are **not yet verified**.
- Screen Recording permission for Seamless Close's individual screenshots. Battery Ripple needs no screen access.
- To build: Xcode 26 or later, opened once to finish setup. Its asset compiler is required for the native app icon; Command Line Tools alone are insufficient. Swift 5.9 or later is required by the package.

The macOS minimum is the software deployment target, not a claim that every MacBook running it has a supported sensor.

## Interface and behaviour

The app icon uses a centred rounded blue glass wave on a pearl-white/light-silver base in Default and a graphite base in Dark. On macOS 26 or later, **System Settings → Appearance → Icon & widget style** controls its default, dark, clear, or tinted appearance. Clear and tinted preserve the same wave shading and glass highlights; macOS supplies the selected tint and outer material. Glissform has no separate icon-style setting. Earlier macOS versions use the compiler-generated legacy icon. See [app icon artwork](../Artwork/README.md) for editable sources and verification guidance.

Seamless Close requires Screen Recording access. The screen-access card shows permission status and remains available in Privacy & About. Battery Ripple works without this permission.

Opening Glissform presents its settings window. The sidebar groups **General**, **Seamless Close**, and **Battery Ripple** under Features, and **Privacy & About** and **Send feedback** under More. Select a page to view its content; switching pages does not toggle either feature. The window keeps the same size across pages and scrolls when needed. You can reopen it later from the menu bar icon with **Settings…**, or by opening Glissform again if the menu bar icon is hidden, returning to the selected page.

Turn **Seamless Close** on or off in the same card that holds **Current lid angle** and **Begin at**. A subtle divider separates the switch from the angle controls. Separate cards hold **Detect starting angle** and pause restoration. Adjust **Begin at** with the slider, number field, or stepper; higher angles start the effect sooner. Typed angles apply on Return or when you leave the field. Clicking outside the field clears focus and applies the entered value; values are limited to 20–130°. **Use current angle** copies the live angle when it is within that range; **Reset** restores 100°.

Turn on **Detect starting angle** to learn a starting angle one degree below the open lid angle after it stays within one degree for one second. The learned angle overrides **Begin at** for the next gesture, while **Begin at** remains the fallback until an angle is learned. Once learned, the saved **Begin at** controls dim and cannot be edited until automatic selection is turned off. The setting and manual value are saved; the learned angle lasts for the current app session and stays fixed through a gesture and eligible wake opening. Turning automatic selection off returns to the manual angle. The automatic-selection row shows the learned angle when available.

The **Current lid angle** reading sits below the Seamless Close switch in the combined card. For the actual Seamless Close effect, begin above the selected angle and close through it. In manual mode, if you start the app or change the setting while already below the threshold, open above the chosen angle first.

**Resume desktop after pause** restores the live desktop when the lid stays still below the starting angle for 1 second. For example, with a 95° start and a 1-second pause, closing to 80° and holding there returns the effect to zero and releases the screenshot. Meaningful movement resets the wait; one degree of sensor fluctuation is tolerated. In manual mode, the effect stays inactive until you open strictly above the starting angle, then close again. Changing the pause toggle restarts any pending wait; disabling this option after restoration does not immediately reactivate the effect. The delay is no longer adjustable, and custom delays saved by earlier builds are ignored. The timer relies on fresh sensor readings and does not delay normal sleep. With automatic starting angle also on, restoring the desktop at a paused angle in the 20–130° range adopts a start one degree below it for the next gesture. Closing past that learned angle starts a fresh animation without reopening farther; holding the lid still does not.

The live reading is shown in whole degrees and has the accessibility label **Current lid angle**. To avoid flicker at a whole-degree boundary, the number waits for a one-degree change to persist for 250 ms; changes of two degrees or more appear immediately. This affects the Settings display only: animation, automatic angle selection, and **Use current angle** still use each raw sensor reading. After a relaunch with automatic selection still on, its card asks you to hold the lid still for one second to set a new angle and explains that **Begin at** applies until then.

Reopen to the active starting angle to restore the live desktop. To stop the app, reopen the lid and choose **Quit Glissform** from the menu bar icon or app menu, or turn off **Run in background** and close Settings. Normal sleep stays enabled.

Select a page in the sidebar to open its settings. General comes first in Features. Seamless Close groups its enable switch and manual angle in one card; Battery Ripple has two event switches with no page-wide switch. The More group sits directly below Features and contains **Privacy & About** and **Send feedback**. The latter currently shows only “Nothing here yet.”; use the README’s GitHub bug-report link to submit a report. Privacy & About is also available through the standard About command. The window keeps a steady size between pages and scrolls when needed.

The refreshed interface uses rounded page titles, small selected sidebar tabs with equal padding, saturated sidebar icon tiles, subtle page icon tiles, and separate neutral cards. Native window controls sit over the continuous sidebar material in a unified toolbar window. All four corners are rounded, with a fine outline and faint, diffuse shadow, without a titlebar separator. The detail surface stays opaque. Live Dark appearance, earlier-macOS appearance, and accessibility fallbacks still need final visual verification. See [the design system](DESIGN_SYSTEM.md) and [reference study](DESIGN_REFERENCES.md).

Remaining supporting interface icons use Iconly Bold / Regular, bundled locally as vectors. The General sidebar uses the supplied Setting icon; its background-running, menu-bar, and login cards use the supplied checked-window, grid-interface, and user icons. The Seamless Close sidebar and enable card use the supplied monitor icon; automatic starting-angle detection uses a hinge-and-angle icon with a light-blue symbol and tile, distinct from Seamless Close’s indigo. Battery Ripple uses the supplied empty-battery icon in the sidebar, charge-battery for Power connection, and low-battery for Battery at 20%. Send feedback uses the supplied messages icon. No icon downloads or account connection are needed at runtime. The previous Outline, Bulk, and Custom Iconly sets remain available for developer comparisons. The screen-access icon is green with a check when allowed and amber with an attention mark when permission is required.

Interactive controls retain hover, pressed, focus, and disabled states. The existing capsule switches use the system accent and expose their state through native toggle accessibility. The angle number and raised degree symbol share one rounded field with up/down arrows on the left. Each arrow has its own hit area and supports holding to repeat. Disabled controls do not react to hover.

## Privacy and system behavior

By default, closing Settings with its close button or ⌘W keeps Glissform running in the background without a Dock icon; reopen it from the menu bar’s **Settings…** command or by opening the app again. In **General**, turning off **Run in background** makes closing Settings quit Glissform and stop its effects. Turning off **Menu bar icon** hides its status item immediately; turning it back on restores the same item. If background running remains on, closing Settings removes the Dock icon even when the menu bar icon is hidden; open Glissform again to restore Settings. **Launch at login** asks macOS to open Glissform when you sign in; the switch reflects macOS’s current registration and shows guidance if approval is needed. A login launch opens the Settings window like a manual launch. The other two switches are saved locally; none requires Screen Recording access.

Seamless Close’s desktop screenshots stay in memory. One completed closing image and its prepared texture may remain through lid-close sleep for the following opening. The overlay stays hidden while asleep or locked; the image is released after the opening, a skipped wake attempt, or cancellation. Session switches, display changes, screen-access loss, disabling the effect, changing the active starting-angle reference, and quitting discard it. There is no capture fallback if a closing image is unavailable. The app does not save or transmit screenshots, capture audio, or include networking or analytics. Privacy & About explains the app’s use of lid angle, power status, and temporary screen images, along with its lack of audio capture, analytics, and network requests. It also provides screen-access status and management; no new permission is needed. The rendering test saves only synthetic test images under `build/render-test/`.

For Seamless Close, only the built-in display receives an overlay. The app does not change Dock/menu bar hiding preferences or take keyboard focus from your current application. A visible screenshot stays in the Space where its gesture began, is not duplicated into the destination side of the switch animation, and is cleared when the active Space changes. Sleep, display changes, sensor loss, and quitting also clear the overlay. The app does not prevent system sleep or alter lock-screen behavior.

## Known Seamless Close alpha limitations

- Space changes intentionally stop the current animation. Opening above the active starting angle is required before a new closing gesture can animate in the newly active Space; physical confirmation of full-screen transitions remains pending.
- The lid sensor exposes an undocumented protocol. Fractional readings are available on the development Mac, with whole-degree fallback on unsupported hardware; their accuracy and update rate are not guaranteed. During one fast-close trial on the development Mac, both reports changed about ten times per second. The animation estimates some movement between those readings, but cannot know the exact path or an abrupt stop before the next report.
- Reopening during an awake gesture reverses the animation. The experimental wake-opening effect requires a completed closing screenshot, a fresh near-closed reading before sleep, an available unlocked desktop, and upward movement still below the starting angle within three seconds of wake. Ordinary sleep/lock ordering keeps that image hidden in memory; a near-closed lock immediately before sleep has a one-second grace period. Session switches discard it. Fast opening, late unlock, unfinished closing capture, pause restoration before sleep, display changes, or missing sensor readings can skip the effect. It does not animate over the lock screen, replay a completed opening, or guarantee the first visible wake frame.
- Wake desktop availability combines public display/session checks with undocumented macOS lock hints. Those hints need OS-version and physical unlock testing; the overlay retains normal login visibility restrictions and never requests drawing over the lock screen.
- Physical trials of the earlier fresh-capture prototype showed a live-screen blink and incomplete-looking foreground windows after unlock. Retaining the closing image now removes that fresh-capture path and its wait, and the owner reported that the revised opening works well on the development Mac. Broader physical validation is still needed. macOS wake, unlock, sensor delivery, GPU presentation, and the cached-opening entrance fade still affect visible timing.
- The cached image represents the desktop when closing began. Content that changes during sleep can differ when the live desktop returns; caching does not guarantee an invisible final handoff.
- A screenshot freezes moving content. A perfectly invisible handoff is not guaranteed for video, changing windows, protected content, or OS capture indicators.
- The projection assumes a fixed seated viewpoint; it is not head tracking or exact optical compensation.
- Screen capture permission may need renewing after local signing or path changes.
- Full-screen apps, multiple displays, hardware compatibility, and battery impact need broader physical testing.

## Development checks

```sh
bash scripts/build.sh
bash scripts/test.sh
build/Glissform.app/Contents/MacOS/Glissform --version
build/Glissform.app/Contents/MacOS/Glissform --probe
```

Tests cover motion, thresholds, reversals, tracking delay, boundary transitions, wake eligibility and deadlines, Metal rendering against synthetic pixels, snapshot cancellation through the real gesture coordinator using synthetic captures, and overlay visibility without foreground activation. The overlay checks can also run while another app is full screen; see the testing notes for wake diagnostics and physical acceptance. `--probe` reads the actual lid sensor. For a machine without Metal rendering support:

```sh
bash scripts/test.sh --motion-only
```

GitHub Actions builds the app and runs motion checks. GPU rendering and physical lid behavior are separate local checks; a green CI run does not verify those.

See [testing notes](TESTING.md) and [implementation notes](ARCHITECTURE.md).

## Versions

Public versions follow `0.1.0-alpha.1` → subsequent alpha builds → `0.1.0-beta.1` → `1.0.0-rc.1` → `1.0.0`. Progression depends on the readiness criteria in the roadmap, not a promised date.

`VERSION` is the public version; `BUILD_NUMBER` is the increasing macOS build number. The app bundle uses a numeric short version (`0.1.0`) and stores the complete prerelease version separately for the menu and `--version`. Git tags use the `v` prefix.

## Acknowledgment and licensing

The [LidAngleSensor project](https://github.com/samhenrigold/LidAngleSensor) and [Clamshell](https://github.com/danielradosa/clamshell) were consulted for the HID reports. Glissform's sensor implementation and visual effect were written independently; no competitor animation code or assets are bundled.

The remaining Iconly interface icons are by [Iconly](https://iconly.pro), used under the project owner's paid license. These third-party assets retain their own licensing terms; see [icon provenance](ICONLY.md).

An open-source license has not been selected. Public availability of this repository does not itself grant an open-source license.

### Developer icon comparison

Build with `bash scripts/build.sh --dev` to show **Developer → Icon Style** in the app menu bar. Select **Bulk**, **Bold**, **Outline**, or **Custom** (⌥⌘1, ⌥⌘2, ⌥⌘3, ⌥⌘4) to update interface icons immediately. The branded menu bar mark stays unchanged. The choice lasts for this app session; restarting restores Bold. Bold is the default product set; the previous Custom mix and all three original sets stay available. A normal build omits the Developer menu.
