# Glissform

Subtle animations and quality-of-life improvements for everyday interactions on your Mac.

**Seamless Close is the first available feature:** your desktop appears to stay in place as you close your MacBook lid, with perspective, frost, and shadow responding to the movement. Glissform is designed to grow into a collection of useful experiences.

[Website](https://glissform.app/) · [Roadmap](ROADMAP.md)

## Project status

**In development — not yet available for public download.** The last tagged source prerelease was 0.1.0-alpha.9; the source repository is now private. Version 0.1.0-beta.1 is being prepared locally.

The app will be available once a `.dmg` is ready and published at [glissform.app](https://glissform.app/). Download links and installation instructions will be added then. Seamless Close settings preview planned Lock Screen support with a Soon label; animation while the Mac is locked is not available yet. The local beta candidate includes signed update checks and a General switch for automatic installation. No public `.dmg` or update feed has been published yet.

Alpha.9 includes **Battery Ripple** and the renamed **Seamless Close** feature. Earlier alpha releases called it **Infinite Screen**. See the [changelog](CHANGELOG.md) for version-specific changes and ongoing limitations.

## Current features

- Experience a lid-driven desktop animation with a continuous perspective fold, an upper edge that narrows throughout closure, optional High, Regular, or Subtle blur (Regular by default), and shadow.
- Reverse the effect by reopening the lid, including experimental opening after lid-close sleep using the same screenshot.
- Choose the starting angle manually or let a still-lid pause set it automatically, one degree below the held angle. Set a minimum lid angle for automatic detection, or set it to 0° to disable the threshold; **Begin at** remains the fallback until an angle is learned. Optionally restore desktop access after a pause. Set each wait independently from 0.5 to 10 seconds (1 second by default).
- Keep Glissform running after its Settings window closes, with menu bar access by default.

Battery Ripple plays a green wave when power connects or a red wave when the built-in battery falls to 20%. The two events have independent saved switches and preview buttons; there is no overall Battery Ripple switch. A compact sidebar groups General, Seamless Close, and Battery Ripple in that order under Features, with Privacy & About and a Send feedback placeholder under More. General controls whether Glissform keeps running after Settings closes, whether its menu bar icon appears, whether macOS launches it at login, and whether updates download and install automatically. With automatic installation off, the sidebar shows the existing Update card only when a newer installable version is found; its button opens the installer. When background running is on, closing Settings removes Glissform from the Dock even if its menu bar icon is hidden; opening the app again restores Settings. Seamless Close keeps its switch, live lid reading, and manual angle together in one card, with separate automatic-selection and pause cards and a page reset for its settings. Battery Ripple uses no screenshot or additional permission.

## Compatibility

| Requirement | Current status |
| --- | --- |
| macOS | 15 or later is the deployment minimum; this is not a guarantee of compatibility on every version. |
| Hardware | A Metal-capable MacBook with a compatible lid-angle sensor. |
| Tested hardware | MacBook Air M5 15-inch (Mac17,4), the development machine. Other models are unverified. |
| Permission | Seamless Close needs Screen Recording access for individual desktop screenshots. Battery Ripple does not. |

The lid sensor uses an undocumented protocol. Glissform tries fractional angle readings and falls back to whole degrees when unavailable. Other Mac configurations remain unverified; future compatibility reports can help build coverage, but they are not hardware certification.

## Privacy

One screenshot is taken per closing attempt and kept in memory. On a fast close it may be requested just before the selected start angle; if the lid reverses or stops before that angle, the hidden image is discarded. A completed closing image may remain through lid-close sleep for the following opening; it stays hidden while locked or asleep and is released after completion or cancellation. There is no continuous recording, audio capture, screenshot saving, or analytics. Update checks and downloads use glissform.app; screen images are never sent. Normal system sleep remains enabled.

Battery Ripple reads the Mac's power-source and built-in battery charge state. It does not capture screen content and stops when the display sleeps or the session locks.

## Feedback and support

The source repository and its [issue tracker](https://github.com/itsgeorge22/glissform/issues) are private, so public bug reports and feature suggestions are not available there. The in-app Send feedback page is a placeholder; a public contact method is planned. For detailed feature behaviour, see the [app guide](docs/APP_GUIDE.md).

## Development

[Contributing](CONTRIBUTING.md) · [Testing](docs/TESTING.md) · [Releasing](docs/RELEASING.md) · [Architecture](docs/ARCHITECTURE.md) · [Design system](docs/DESIGN_SYSTEM.md) · [Changelog](CHANGELOG.md)

Developer build and verification steps are documented in [Contributing](CONTRIBUTING.md). CI does not verify physical lid behaviour.

## Credits and licensing

The [LidAngleSensor project](https://github.com/samhenrigold/LidAngleSensor) and [Clamshell](https://github.com/danielradosa/clamshell) were consulted for the HID reports. Glissform's sensor implementation and visual effect were written independently. Updates use [Sparkle](https://sparkle-project.org/), whose [license and notices](docs/SPARKLE_LICENSE.txt) are included with the app. Some interface icons are by [Iconly](https://iconly.pro), used under the owner's paid license; see [provenance](docs/ICONLY.md). See [app artwork](Artwork/README.md) for the native icon sources.

**No open-source license has been selected.** The source repository is private. Third-party assets retain their own terms.
