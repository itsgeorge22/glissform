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

## Physical acceptance

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

- Verify Light and Dark appearances, keyboard navigation, focus, disabled controls, and VoiceOver labels on both pages.
- Confirm Bold is the default throughout, with flat 16%-opacity card icon containers and slightly darker icon colours in Light Mode.
- Build with `--dev` to compare Bulk, Bold, Outline, and Custom with ⌥⌘1–4. Check live updates in settings, Privacy & About, and the menu bar; restart returns to Bold. A normal build hides Developer tools.
- Verify Privacy & About has the Glissform name/version and the two cards, with no old descriptive paragraph, alpha text, or footer text beneath them.
- Confirm local icon resources load from the built app bundle without an account connection or network request.
