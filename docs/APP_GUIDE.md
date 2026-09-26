# Glissform app guide

Glissform brings subtle animations and quality-of-life improvements to everyday interactions on your Mac. It is designed to make familiar gestures and system changes feel more expressive, clear, and enjoyable.

**Infinite Screen is its first available feature:** your desktop appears to stay in place as you close your MacBook lid, with perspective, blur, and shadow responding to the movement. Glissform’s scope extends beyond this effect; additional experiences will be introduced as they are designed and validated.

**Development version: 0.1.0-alpha.8. The app is not yet available for public download.** A `.dmg` and installation instructions will be published on GitHub when ready. Development testing uses a MacBook Air M5 15-inch; wider compatibility is still being evaluated.

This source release includes the capture, motion, material, and Space-change improvements described below. Repeatable physical acceptance remains pending where noted.

[Changelog](../CHANGELOG.md) · [Roadmap](../ROADMAP.md) · [Contributing](../CONTRIBUTING.md)

## Current implementation — Infinite Screen

- Takes one screenshot when closing crosses your chosen lid angle. No continuous screen recording or idle capture.
- Animates that same image through closing, pauses, and eligible reopening, including after lid-close sleep.
- Includes experimental opening after lid-close sleep: it retains the completed closing screenshot and prepared texture in memory through sleep, then reuses them when the desktop is unlocked and opening movement remains. It takes no fresh wake screenshot. Missing closing images, completed openings, and late unlocks skip the effect; the owner confirmed the main opening behavior on the development Mac, with broader wake/unlock validation still pending.
- Closing starts at exactly zero stretch, blur, and shadow, then eases into the current angle. Wake opening prepares the current fold directly and follows the remaining opening movement.
- Compensates the full lid rotation around a fixed hinge, including closures that travel more than 90° from the starting angle.
- Timestamps lid readings when acquired and uses those timestamps for critically damped smoothing. Polling requests 60 reads per second during gestures and 30 while idle; the sensor's actual update rate and whole-degree resolution remain hardware limits. Rendering follows the display's presentation clock and pauses when settled.
- Replaces the live desktop with a prepared, full-opacity flat screenshot before a 100 ms geometric entrance. Reopening returns from the current motion to a flat image, then fades it out over 50 ms on the same rendering clock. Pause restoration eases back without overshoot over 260–480 ms depending on the fold; cached wake opening uses a 50 ms entrance fade.
- Captures the display's backing pixel dimensions, checks that they match the overlay, and preserves known Glissform settings windows while excluding the animation overlay. Display and window metadata may be prepared in advance; no screen pixels are captured while idle.
- Diffuses the entire image into a frosted-glass appearance as the lid closes, including the bottom. Fine text and icons soften while larger shapes retain enough definition to show the perspective skew; a smooth vertical gradient keeps the blur lighter at the hinge and heavier at the top. Reopening clears it continuously.
- Builds a Gaussian blur pyramid once from each screenshot, filters and shades in linear light, and uses a subtle fixed dither to reduce visible steps in the shadow gradient. The flat screenshot remains sharp and unchanged by the material.
- Adds a soft contact shadow directly below the top bezel within the first few degrees of motion, spreading downward as the lid closes. Broader closure shading remains transparent at the bottom, darkest at the top, with only the top 5% reaching full black at the end.
- Provides a compact native window with a main experience page and a linked Privacy & About page, a live lid reading, an original perspective illustration, an Infinite Screen switch, and precise starting-angle controls.
- Lets you preview a closing-and-reopening gesture inside the window using synthetic artwork, without taking a screenshot. With Reduce Motion, the preview shows a still illustration instead.
- Shows a screen-access card above the preview while permission is required. When access becomes available during the session, the card confirms success for three seconds, then disappears. The same card stays in Privacy & About for access status and management; already-authorized launches start without the main-screen card. Runtime readiness remains in the menu bar.
- Saves the Infinite Screen and automatic-angle toggles and the manual starting angle. The default manual angle is 100°; a learned angle lasts for the current app session.
- Optionally restores the live desktop after the lid pauses below the starting angle, so you can keep working at that angle. This is off by default and uses a fixed 2-second pause.
- Covers the live Dock and menu bar during the effect so their captured images animate with the desktop. Mouse clicks cannot pass through the snapshot.
- Displays the overlay in another app's full-screen Space with settings open or closed, without activating Glissform or moving keyboard focus from that app.
- Keeps the current effect in its original Space during a Space-switch animation instead of showing the same frozen image on both sides. It then clears the effect; the next animation remains disarmed until you reopen above the active starting angle and close through it in the newly active Space.
- Appears in the Dock while its settings window is open, with standard About, Settings, Edit, and Quit commands. Closing the window removes Glissform from the Dock while Infinite Screen and menu bar access keep running. Reopening Settings restores the window and Dock icon. The menu bar uses a monochrome template derived from the actual Clear app icon; macOS supplies its foreground colour for the background and selection state.

## Current alpha requirements

- macOS 14 or later and a Metal-capable MacBook with a compatible lid-angle sensor.
- Development target: MacBook Air M5 15-inch, model identifier Mac17,4. Other Macs are **not yet verified**.
- Screen Recording permission, even though Glissform takes individual screenshots.
- To build: Xcode 26 or later, opened once to finish setup. Its asset compiler is required for the native app icon; Command Line Tools alone are insufficient. Swift 5.9 or later is required by the package.

The macOS minimum is the software deployment target, not a claim that every MacBook running it has a supported sensor.

## Interface and behaviour

The app icon uses a centred rounded blue glass wave on a pearl-white/light-silver base in Default and a graphite base in Dark. On macOS 26 or later, **System Settings → Appearance → Icon & widget style** controls its default, dark, clear, or tinted appearance. Clear and tinted preserve the same wave shading and glass highlights; macOS supplies the selected tint and outer material. Glissform has no separate icon-style setting. Earlier macOS versions use the compiler-generated legacy icon. See [app icon artwork](../Artwork/README.md) for editable sources and verification guidance.

Infinite Screen requires Screen Recording access. The screen-access card shows permission status and remains available in Privacy & About. The illustration preview works without this permission.

Opening Glissform presents its settings window. You can reopen it later from the menu bar icon with **Settings…**. Turn **Infinite Screen** on or off and adjust **Begin at** inside the preview card using the slider, number field, or stepper. Higher angles start the effect sooner. The current lid angle appears at the top of the preview; the slider sets the manual trigger. Below the preview are separate cards for Set starting angle automatically and pause-to-resume. Turn on **Set starting angle automatically** to learn a starting angle one degree below the open lid angle after it stays within one degree for two seconds. The learned angle overrides **Begin at** for the next gesture, while **Begin at** remains the fallback until an angle is learned. Once learned, the saved **Begin at** controls dim and cannot be edited until automatic selection is turned off. The setting and manual value are saved; the learned angle lasts for the current app session and stays fixed through a gesture and eligible wake opening. Turning automatic selection off returns to the manual angle. The card shows the learned angle when available. Access and pause card icons use Bold shapes with appearance-specific colours for contrast. Typed angles apply on Return or when you leave the field. Clicking anywhere outside the field clears its focus and applies the entered value; values are limited to 20–130°. **Use current angle** copies your live angle (when it is within 20–130°); **Reset** restores 100°. **Preview motion** immediately plays a short closing-and-reopening illustration from the currently shown lid position; it does not capture or cover your desktop and is not a physical hardware test. Begin above that angle and close through it. In manual mode, if you start the app or change the setting while already below the threshold, open above the chosen angle first.

**Resume desktop after a pause** restores the live desktop when the lid stays still below the starting angle for 2 seconds. For example, with a 95° start and a 2-second pause, closing to 80° and holding there returns the effect to zero and releases the screenshot. Meaningful movement resets the wait; one degree of sensor fluctuation is tolerated. After restoration, the effect stays inactive until you open strictly above the starting angle, then close again. Changing the pause toggle restarts any pending wait; disabling this option after restoration does not immediately reactivate the effect. The delay is no longer adjustable, and custom delays saved by earlier builds are ignored. **Play sound when desktop returns** has its own card directly below the pause option. Its cyan light-blue speaker icon changes to a muted speaker when switched off. The sound option starts on and can be switched off independently. A short click plays as the visible image begins snapping back after you reopen the lid or hold it still to restore the desktop. If no screenshot is visible, no click plays. The timer relies on fresh sensor readings and does not delay normal sleep. With automatic starting angle also on, restoring the desktop at a paused angle in the 20–130° range adopts a start one degree below it for the next gesture. The effect remains inactive until you reopen above the held angle.

The live reading is labelled **Current lid angle**. To avoid flicker at a whole-degree boundary, the number and live illustration wait for a one-degree change to persist for 250 ms; changes of two degrees or more appear immediately. This affects the Settings display only: animation, automatic angle selection, and **Use current angle** still use each raw sensor reading. A small **Preview** label appears on the illustration during playback or the Reduce Motion still preview; the live reading continues to show the physical lid angle. When Infinite Screen is off, its header says the effect is off and settings remain saved. After a relaunch with automatic selection still on, the card asks you to hold the lid still for two seconds to set a new angle and explains that **Begin at** applies until then.

Reopen to the active starting angle to restore the live desktop. To stop the app, reopen the lid and choose **Quit Glissform** from its menu bar icon. Normal sleep stays enabled.

Open **Privacy & About** from the main page footer and use **Back** (⌘[) to return. The interface uses a plain system background (white in Light Mode), flat adaptive surfaces, and the macOS accent colour for controls. Both pages share a 4-point spacing scale, consistent text roles, and card styling. Interface icons use Iconly Bold / Regular throughout, bundled locally as vectors; no icon downloads or account connection are needed at runtime. The previous Outline, Bulk, and Custom sets remain available for instant developer comparisons. The screen-access icon is green with a check when allowed and amber with an attention mark when permission is required. See [the design system](DESIGN_SYSTEM.md) for the current UI foundations. Interactive controls have hover feedback: the solid-white slider thumb changes size slightly, each stepper arrow highlights independently within the angle field, and the Apple-style capsule switch highlights its track. Both the slider and switch handles stay pure white, including on hover and press. The slider and switch have no separate hover background or border. The angle number and raised degree symbol share one rounded field with up/down arrows on the left. Each arrow has its own hover and pressed highlight, with no separate background at rest. Buttons have distinct pressed surfaces, and the angle field shows an editing outline. Disabled controls do not react to hover. The illustration follows the live lid reading except while previewing; its synthetic screen artwork is explanatory, not a pixel-accurate simulation of the desktop effect. Reduce Motion removes interpolation from the live illustration and replaces playback with a still preview. The actual desktop effect is unchanged.

## Privacy and system behavior

Closing the settings window with its close button or ⌘W keeps Glissform running in the background without a Dock icon. Reopen it through the menu bar's **Settings…** command or by opening the app again. **Quit Glissform** stops it completely. This background behavior requires no additional permission or access card and does not enable launch at login.

Infinite Screen’s desktop screenshots stay in memory. One completed closing image and its prepared texture may remain through lid-close sleep for the following opening. The overlay stays hidden while asleep or locked; the image is released after the opening, a skipped wake attempt, or cancellation. Session switches, display changes, screen-access loss, disabling the effect, changing the active starting-angle reference, and quitting discard it. There is no capture fallback if a closing image is unavailable. The app does not save or transmit screenshots, capture audio, or include networking or analytics. Privacy & About explains this retention and provides access status and management through the existing screen-access card; no new permission is needed. The rendering test saves only synthetic test images under `build/render-test/`.

For Infinite Screen, only the built-in display receives an overlay. The app does not change Dock/menu bar hiding preferences or take keyboard focus from your current application. A visible screenshot stays in the Space where its gesture began, is not duplicated into the destination side of the switch animation, and is cleared when the active Space changes. Sleep, display changes, sensor loss, and quitting also clear the overlay. The app does not prevent system sleep or alter lock-screen behavior.

## Known Infinite Screen alpha limitations

- Space changes intentionally stop the current animation. Opening above the active starting angle is required before a new closing gesture can animate in the newly active Space; physical confirmation of full-screen transitions remains pending.
- The lid sensor exposes an undocumented protocol and whole-degree readings. Smoothing improves the appearance but cannot recover motion the sensor never reported.
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

The [LidAngleSensor project](https://github.com/samhenrigold/LidAngleSensor) was consulted for the HID protocol. Glissform's sensor implementation and visual effect were written independently; no competitor animation code or assets are bundled.

Interface icons are by [Iconly](https://iconly.pro), used under the project owner's paid license. These third-party assets retain their own licensing terms; see [icon provenance](ICONLY.md).

An open-source license has not been selected. Public availability of this repository does not itself grant an open-source license.

### Developer icon comparison

Build with `bash scripts/build.sh --dev` to show **Developer → Icon Style** in the app menu bar. Select **Bulk**, **Bold**, **Outline**, or **Custom** (⌥⌘1, ⌥⌘2, ⌥⌘3, ⌥⌘4) to update interface icons immediately. The branded menu bar mark stays unchanged. The choice lasts for this app session; restarting restores Bold. Bold is the default product set; the previous Custom mix and all three original sets stay available. A normal build omits the Developer menu.
