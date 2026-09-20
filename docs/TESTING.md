# Testing

Glissform’s current feature-specific checks cover Infinite Screen. Shared UI checks cover settings, permissions, and appearance. Add appropriate behavioural, interruption, accessibility, and performance checks as new experiences are implemented; passing the lid-animation suite is not validation of a different feature.

## Automated

Run `bash scripts/build.sh` followed by `bash scripts/test.sh`.

Motion checks exercise thresholds, repeated closure, slow whole-degree readings, reversal, settling, zero-effect entrance, interrupted handoffs, low-lid startup, and reset behavior. Quantized 30 Hz sensor traces run on 60/120 Hz frame clocks at nine speeds from 2 to 90 degrees/second, including uneven report intervals and mixed one/two-degree reports. Both tracking error and frame-to-frame speed ripple are bounded; checking delay alone can reward visibly uneven movement. Full-angle checks cover starting angles from 20° to 130°.

Synthetic Metal checks compare projected pixels to independent CPU ray/plane intersections at 16°, 40°, 90° and 120° of physical rotation, and verify orientation, opacity, zero-angle identity and the final top shadow. Matching sharp/blurred frames at 40° verify that frost softens grid edges at the bottom of the image as well. Lifecycle checks use the real gesture coordinator and a synthetic capture source: a screenshot arriving after reversal, sleep, display change or shutdown must be rejected. An overlapping entrance, reclose during return, single-snapshot reuse and final desktop-access cleanup are also exercised. These checks briefly create a small synthetic Metal window; no desktop pixels are captured.

For a local GPU rendering measurement using synthetic pixels at 2880 × 1864:

```sh
build/Glissform.app/Contents/MacOS/Glissform --render-benchmark
```

The benchmark reports mean, 95th-percentile and maximum GPU command duration over 120 closing/reopening frames after warmup. It excludes screenshot capture, the window compositor, sensor delivery and actual display frame pacing, so it cannot establish end-to-end smoothness or a guaranteed frame rate. Generated images stay under `build/`.

`bash scripts/test.sh --motion-only` explicitly omits Metal and AppKit lifecycle checks. GitHub Actions uses this mode; it does not verify physical lid behavior, permissions, or screen capture.

### Full-screen overlay

The full local suite also builds and runs `build/tests/overlay-checks`. It displays a small solid-colour panel through the production overlay class, checks active-Space membership and compositor visibility with both regular and accessory app activation, verifies that the foreground app stays unchanged, and checks dismissal. It takes no screenshots and requires no screen access. Running it on an ordinary desktop does not establish full-screen behavior.

For the full-screen regression, run `sleep 5 && build/tests/overlay-checks`, then switch to another app in native full screen before the five-second delay ends. Leave that app active until both checks finish. A separate synthetic full-screen host reproduced the old failure in regular activation (the overlay was absent from the active Space and compositor); the updated panel passed both activation modes without changing the foreground app.

For physical acceptance, repeat a close/reopen gesture over a full-screen app with Glissform settings open on another Space, then with settings closed. Check screenshot content, animation, reversal, pause restoration, sleep cleanup, and restored mouse access. Repeat with Split View and Space changes. The synthetic overlay checks verify window placement, not physical lid motion, screen-capture content, or protected video compatibility.

## Physical acceptance

### Wake-opening prototype

Automated checks cover recent near-closed eligibility, duplicate notifications, opening direction, completed openings, unavailable desktops, stale samples, deadlines, and explicit below-threshold arming. The Metal identity check pauses a prepared screenshot, verifies the original buffer and filtered texture survive, and compares its flat output with the original pixels. Synthetic lifecycle checks now use one capture across closing, sleep, and opening, then require a new capture for the next cycle. They assert hidden/paused retention; no fresh wake capture; rejection of late or failed closing captures; normal-lock cleanup; lock-before-sleep grace and repeated hints; lock before/after wake; completed/late unlocks; and cached-frame cleanup on session/display changes, access loss, disable/threshold changes, quit, sensor loss, and another sleep. Pending and visible opening interruptions must not resurrect an overlay. Cleanup checks explicitly pump synthetic rendering because MetalKit may suspend display callbacks while occluded/asleep. They do not establish physical compositor delivery, wake latency, or OS lock-detection correctness.

On the target Mac, keep normal lock and sleep settings. With a static foreground window, close fully, wait for sleep, then reopen slowly and quickly. Verify the closing and opening show the same window and the logs say `retainedFrame=true` and `cached frame prepared; reveal requested`, with no fresh wake capture. Repeat with a password prompt, settings open/closed, fullscreen, long sleep, and display changes. The overlay must remain hidden until unlocked and only animate remaining upward movement within the original three-second deadline. A completed opening, missing closing screenshot, or late unlock must skip with no replay. Check normal sleep, restored mouse access, cache release after completion/cancellation, and a fresh screenshot on the next closing gesture. Content that changes during sleep may differ at the final handoff. After trying the cached-frame revision, the owner reported “Now it works great” on the development MacBook Air M5 15-inch. This confirms the reported everyday opening experience, not the full speed/lock/display matrix or measured latency. Those broader checks remain pending.

The following dated trials describe the earlier fresh-capture implementation and motivated its replacement.

The first owner trial on 2026-09-20 produced three skipped wake openings despite fresh pre-sleep angles of 6–7°: two logged disabled/missing eligibility and one expired after three seconds. Code inspection found that lock/session events could discard numeric evidence; sensor diagnostics were also omitted while locked. Regression checks now cover lock both before and after wake, preserved deadlines, no capture while locked, remaining movement after unlock, completed movement while locked, and late unlock. Physical confirmation of this correction remains pending. Diagnostics start in accessory activation and successful UI suites terminate through AppKit to avoid leaving test app registrations behind in the Dock.

Follow-up trials at 22:15–22:16 on 2026-09-20 reached reveal requests at 324, 356, 283, 292 ms after wake (four captured attempts in this interval). The owner saw the live-screen blink before the effect and missed/late animation at regular opening speed. Capture itself took 91–227 ms; the subsequent 80 ms fade adds visible handoff time. These timestamps measure submission/readiness, not physical scanout. Two additional openings were cancelled at 0 and 4 ms because the heartbeat tested the old pre-sleep reading before sensor restart could deliver a sample. Synthetic regression checks now cover both heartbeat timings, successful subsequent delivery, duplicate wake notifications, and genuine sensor loss after one second. First-frame continuity remains an unresolved acceptance failure.

At 22:52 on 2026-09-20, the owner reproduced a faded-looking foreground ChatGPT window throughout the opening effect. A temporary 60 Hz window-metadata probe reported ChatGPT's window alpha as 1 throughout; Glissform reached alpha 1 at 22:52:01.906 and stayed there until the normal exit fade at 22:52:03.275. Capture was requested 2 ms after the unlock hint and completed 59 ms after it. This rules out a sustained half-alpha overlay for that trial.

A second trial at 22:58 sampled the existing closing and opening screenshots before rendering, with no additional captures or retained pixels. All 37,440 sampled pixels in both buffers had alpha 255. Mean encoded luminance fell from 234.687 before sleep to 59.599 in the wake capture; standard deviation fell from 51.600 to 28.226. That capture started 8 ms after the unlock hint and completed 159 ms after it; both apps' window alpha remained 1 during the body of the effect. These measurements locate a substantial appearance change in the source screenshot before the shader. Capturing an unsettled unlock composition is the leading explanation; the measurements do not distinguish macOS's composition from ScreenCaptureKit's internal first-frame handling, or prove that every pixel changed uniformly. Desktop availability is not a guarantee of visually settled pixels. The temporary pixel probe was removed after this trial; no animation or capture-timing fix was applied.

The owner's screenshot taken mid-opening at 23:02:36 shows prominent wallpaper with only faint window-like detail near the bottom, under the projected/blurred effect. The preceding wake log requested capture at 23:02:34.124, 17 ms after the unlock hint; capture completed 94 ms after that hint. This strengthens the incomplete-composition hypothesis and corrects an overly narrow interpretation of the earlier brightness average: replacing a bright window with wallpaper can lower that average without uniformly dimming the same desktop. Fully opaque output pixels can also contain a window already blended with its background. This is an image of the animated output, not the raw source buffer, so it cannot isolate capture composition from all rendering effects by itself. The screenshot remains outside the repository; no app behavior changed in this follow-up.

Read local timing events after a trial:

```sh
log show --last 10m --style compact --predicate 'subsystem == "com.george.glissform.mvp" AND category == "WakeOpening"'
```

Logs contain event names, elapsed times, and numeric pre-sleep sensor evidence, with no screenshot content, titles, or captured app names. A missing recent 0–20° sample or completed closing image explains a skipped attempt. The prototype waits at most three seconds from the first wake notification; it requires fresh upward evidence, a usable desktop, and more than three degrees remaining below the selected start angle. Retained-frame and GPU readiness are rechecked before reveal. A `cached frame prepared; reveal requested` log is not proof of physical presentation. Record the logs together with perceived onset and lock state before changing these provisional timing bounds. There is no new permission card: the existing screen-access card still owns the only required user grant.

### Motion and material

For a repeatable material review with original synthetic desktop artwork (text, widgets, window panels and Dock icons):

```sh
build/Glissform.app/Contents/MacOS/Glissform --material-preview
```

This writes sharp and 12°/24°/40°/60° rotated frames to `build/material-preview/` through the production renderer. It does not capture the screen. Compare the shapes, diffusion and retained colour with the supplied reference stills; these images cannot establish the reference animation's timing or physical viewing geometry.

Record the app version, Mac model, macOS version, display arrangement, start angle, and results:

- Start above and below the selected angle; check that the effect starts only after an eligible close.
- Leave the desktop unchanged, then close slowly and quickly.
- Check that blur grows across the whole image as the lid closes, stays lighter at the bottom than at the top, and clears smoothly on reopening.
- Pause at several angles; check settling and idle behavior.
- Reverse before the screenshot returns, during entrance, midway, and during the exit fade.
- Reclose during the return; check for image jumps or a lingering overlay.
- Let the Mac sleep, wake and unlock, then close again.
- Exercise permission denial/revocation, display changes, and unavailable capture/sensor paths where practical.
- Check external displays, multiple Spaces, full-screen apps, Dock/menu coverage, and restoration of mouse access.
- Reopen and quit. Confirm no overlay remains.

Measure capture delay, frame timing, CPU/GPU use, memory, and power before making performance claims. Hardware tests are not complete merely because synthetic tests pass.

## Pause-to-resume

Automated checks cover the default-off behavior, 0.5/2/10-second motion-model test delays (the app uses a fixed two seconds), jitter tolerance, gradual movement, reversals, stale and invalid reports, rearming strictly above the threshold, delayed screenshot rejection, visible return-to-flat, and sleep/display/quit interruptions. These use synthetic sensor timestamps and screenshots; they do not replace physical lid testing.

On hardware, enable Resume desktop after a pause, set a 95° trigger, open above 95°, then close to 80° and hold. Confirm the effect returns to zero and the desktop accepts input; subsequent movement below 95° must not retrigger it. Reopen above 95° and close to verify a new gesture. The app uses a fixed two-second delay. Repeat with slow movement, direction changes, sleep, and toggle changes. Check that the toggle survives relaunch and that older saved custom delays have no effect.

### Permission card presentation

- Without permission, the main page shows the access-required card and Open Settings.
- A false-to-true permission update while the main page is visible shows Screen access allowed for three seconds, then removes the card. Relaunch with access already allowed shows no main-page card.
- Privacy & About always shows the shared access card below the privacy information card, with 16-point spacing; the old embedded access section and divider are absent.
- Revocation restores the main-page required card and updates the Privacy card. A rapid grant/revoke must cancel the success dismissal. Leaving the main page cancels the transient confirmation task.
- Reduce Motion suppresses the card transition animation. Opening settings does not itself grant or revoke access.

## Settings and icon verification

- Close settings with the red close button and with ⌘W. Confirm the Dock icon disappears, the menu bar remains available, and Infinite Screen stays enabled. Reopen through menu bar Settings and by opening the app again; the same usable window and native Dock icon must return. Repeat the cycle and check that minimizing keeps the normal Dock entry. Quit from the menu bar while settings are closed and confirm the process exits.
- Synthetic lifecycle checks close and reopen settings during pending and visible screenshots, verify the active gesture survives without another capture, and reverse it while in the background. Existing reversal, sleep, display-change, and quit cleanup checks also run with settings closed. These AppKit checks open settings briefly and use synthetic screenshot pixels; physical lid acceptance remains separate.
- Build with Xcode 26 or later and confirm the bundle includes `Assets.car`, `Glissform.icns`, and the compiler-generated icon keys in `Info.plist`.
- Inspect the brand icon in Icon Composer and in the running app's Dock, Finder, and Privacy & About. Verify the blue wave in default/light and dark, and readable wave separation in clear light/dark and tinted appearances through System Settings → Appearance. Restore the user's original appearance after testing. Check Dock-sized and small Finder renderings for clipped edges or merged layers.
- Check that all styles retain the rounded pane, glass rim, highlight and continuous wave shading; clear/tinted must not collapse into flat two-tone shapes. Rebuild in place and relaunch: the Dock tile should show the bundle icon, including after changing the system icon style. Finder alone is not sufficient evidence for the Dock.
- Inspect the compiler's legacy `.icns`; earlier-macOS appearance still needs an actual supported-OS check. Native clear/tinted styles are only expected on macOS 26 or later.
- Verify Light and Dark appearances, keyboard navigation, focus, disabled controls, and VoiceOver labels on both pages.
- Confirm Bold is the default throughout, with flat 16%-opacity card icon containers and slightly darker icon colours in Light Mode.
- Build with `--dev` to compare Bulk, Bold, Outline, and Custom with ⌥⌘1–4. Check live updates in settings and Privacy & About; the rounded-wave menu bar brand mark must stay unchanged. Restart returns to Bold. A normal build hides Developer tools.
- Verify Privacy & About has the Glissform name/version and the two cards, with no old descriptive paragraph, alpha text, or footer text beneath them.
- Confirm local icon resources load from the built app bundle without an account connection or network request.

- Check the monochrome app-derived icon at native menu bar size on light/dark menu bars and while its menu is open. Confirm the generated 1×/2× template representations load from the asset catalog, preserve the wave detail, and use the system foreground colour. The build rejects templates whose encoded PNG lacks visible opacity; this catches transparent output but does not replace checking the live menu bar. Settings and Quit actions stay unchanged.
