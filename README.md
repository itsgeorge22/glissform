# Glissform

A small macOS menu bar app that makes your desktop appear to stay in place as you close your MacBook lid. The moving screen reveals a gradually blurred, shadowed image behind it.

**Current version: 0.1.0-alpha.1.** This is an experimental first public version, built and physically tested during development on a MacBook Air M5 15-inch. Wider hardware compatibility and performance are still being evaluated.

[Changelog](CHANGELOG.md) · [Roadmap](ROADMAP.md) · [Contributing](CONTRIBUTING.md)

## What it does today

- Takes one screenshot when closing crosses your chosen lid angle. No continuous screen recording or idle capture.
- Animates that same image through closing, pauses, and reopening before sleep.
- Starts at exactly zero stretch, blur, and shadow, then eases into the current angle.
- Uses adaptive smoothing for the sensor's whole-degree readings and gradual entrance and return transitions.
- Builds a shadow over the full animation: transparent at the bottom, darkest at the top, with only the top 5% reaching full black at the end.
- Lets you choose a starting angle from 20° to 130° in the menu bar. The default is 100°; your choice is saved.
- Covers the live Dock and menu bar during the effect so their captured images animate with the desktop. Mouse clicks cannot pass through the snapshot.
- Runs in the background with a menu bar icon and Quit command.

## Requirements

- macOS 14 or later and a Metal-capable MacBook with a compatible lid-angle sensor.
- Development target: MacBook Air M5 15-inch, model identifier Mac17,4. Other Macs are **not yet verified**.
- Screen Recording permission, even though Glissform takes individual screenshots.
- To build: Apple's Command Line Tools or Xcode, with Swift 5.9 or later. Local development has used Swift 6.4.

The macOS minimum is the software deployment target, not a claim that every MacBook running it has a supported sensor.

## Build and run

Clone this repository, then run from its directory:

```sh
git clone https://github.com/itsgeorge22/glissform.git
cd glissform
bash scripts/build.sh
open build/Glissform.app
```

The build script creates a locally ad-hoc-signed app. This alpha is **not Developer ID signed or notarized**; building from source is the supported installation path for now.

Allow **Glissform** in System Settings → Privacy & Security → Screen & System Audio Recording. The setting's label can vary by macOS version. If macOS asks you to quit and reopen the app, do so. The menu reports readiness and your current lid angle.

Open the menu bar icon and adjust **Start animation at …°**. Begin above that angle and close through it. If you start the app or change the setting while already below the threshold, open above the chosen angle first.

Reopen to the chosen angle to restore the live desktop. To stop the app, reopen the lid and choose **Quit Glissform** from its menu bar icon. Normal sleep stays enabled.

## Privacy and system behavior

Desktop screenshots stay in memory. The app does not save or transmit them, capture audio, or include networking or analytics. The rendering test saves only synthetic test images under `build/render-test/`.

Only the built-in display receives an overlay. The app does not change Dock/menu bar hiding preferences or take keyboard focus from your current application. Sleep, display changes, sensor loss, and quitting clear the overlay. The app does not prevent system sleep or alter lock-screen behavior.

## Known alpha limitations

- The lid sensor exposes an undocumented protocol and whole-degree readings. Smoothing improves the appearance but cannot recover motion the sensor never reported.
- Reopening during an awake gesture reverses the animation. An opening animation after actual sleep is not implemented.
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

Tests cover motion, thresholds, reversals, boundary transitions, and Metal rendering against synthetic pixels. `--probe` reads the actual lid sensor. For a machine without Metal rendering support:

```sh
bash scripts/test.sh --motion-only
```

GitHub Actions builds the app and runs motion checks. GPU rendering and physical lid behavior are separate local checks; a green CI run does not verify those.

See [testing notes](docs/TESTING.md) and [implementation notes](docs/ARCHITECTURE.md).

## Versions

Public versions follow `0.1.0-alpha.1` → subsequent alpha builds → `0.1.0-beta.1` → `1.0.0-rc.1` → `1.0.0`. Progression depends on the readiness criteria in the roadmap, not a promised date.

`VERSION` is the public version; `BUILD_NUMBER` is the increasing macOS build number. The app bundle uses a numeric short version (`0.1.0`) and stores the complete prerelease version separately for the menu and `--version`. Git tags use the `v` prefix.

## Acknowledgment and licensing

The [LidAngleSensor project](https://github.com/samhenrigold/LidAngleSensor) was consulted for the HID protocol. Glissform's sensor implementation and visual effect were written independently; no competitor animation code or assets are bundled.

An open-source license has not been selected. Public availability of this repository does not itself grant an open-source license.
