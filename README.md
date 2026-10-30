# Glissform

**Seamless Close for your MacBook.**

Your desktop appears to stay in place as you close the lid, with perspective, frost and shadow responding to its movement. Glissform is a free macOS app built around this small everyday interaction.

[Download for Mac](https://glissform.app/downloads/Glissform-0.1.0-rc.2.dmg) · [Website](https://glissform.app/) · [App guide](docs/APP_GUIDE.md) · [Release notes](https://github.com/itsgeorge22/glissform/releases/tag/v0.1.0-rc.2)

## Project status

Glissform is a personal passion project. Active development is paused; the website and the latest release remain available. There is no committed schedule for updates or support.

The current release is **0.1.0-rc.2**, a release candidate. It is free to use, with no trial limits or payment requirement.

## What it does

- Folds a single desktop screenshot with your MacBook lid, then returns to the live desktop when you reopen it.
- Lets you choose a starting angle or detect it automatically, with an adjustable dead zone.
- Offers three blur strengths, optional connection glow and sound, and restoration after a pause or with Esc.
- Provides menu bar controls, background operation and launch-at-login settings.
- Adapts to external displays: extended desktops animate on the MacBook; mirroring pauses the effect.

Normal system sleep remains enabled. Opening after lid-close sleep is experimental, and animation while the Mac is locked is unavailable. See the [app guide](docs/APP_GUIDE.md) for controls and behaviour in detail.

## Install

1. [Download Glissform 0.1.0-rc.2](https://glissform.app/downloads/Glissform-0.1.0-rc.2.dmg), open the DMG and drag Glissform into Applications.
2. Open Glissform. This release is **not Apple notarized**. If macOS blocks the first launch, follow [Apple’s instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac) and use **System Settings → Privacy & Security → Open Anyway** if you trust the download.
3. Grant Screen Recording permission when prompted, then enable Seamless Close.

Installed release builds check for updates through glissform.app. **Automatic updates** controls whether available updates download and install automatically; manual checking remains available.

## Compatibility

| Requirement | Details |
| --- | --- |
| macOS | 15 or later |
| Hardware | A Metal-capable MacBook with a compatible lid-angle sensor |
| Tested Mac | MacBook Air M5 15-inch (Mac17,4) |
| Permission | Screen Recording, for individual desktop screenshots |

The lid sensor uses an undocumented protocol. Other Mac models and broader display configurations are unverified; the minimum macOS version is not a compatibility guarantee.

## Privacy

Glissform takes one screenshot per closing attempt and keeps it in memory. Screen images are never saved or transmitted. There is no continuous recording or audio capture.

Optional usage sharing is off until you allow it. When enabled, installation identifiers, running days and daily Seamless Close counts go to PostHog EU. You can turn sharing off in **Settings → Privacy & about**, which also clears unsent counts. [Privacy policy](https://glissform.app/privacy/) · [Analytics details](docs/ANALYTICS.md)

## Feedback and development

[Report a bug or compatibility result](https://github.com/itsgeorge22/glissform/issues) or contact [support@glissform.app](mailto:support@glissform.app). Please include your app version, macOS version and Mac model; do not include serial numbers or credentials. Responses and fixes are not guaranteed while development is paused.

[Contributing](CONTRIBUTING.md) · [Testing](docs/TESTING.md) · [Architecture](docs/ARCHITECTURE.md) · [Design system](docs/DESIGN_SYSTEM.md) · [Changelog](CHANGELOG.md) · [Roadmap](ROADMAP.md)

Build instructions are in [Contributing](CONTRIBUTING.md). Local builds use a separate **Glissform Dev** identity, red icon and settings, with public update checks disabled. The downloadable release uses the blue icon. Automated tests do not replace physical lid, sleep and wake checks.

## Credits and licensing

[LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) and [Clamshell](https://github.com/danielradosa/clamshell) informed the HID report research; Glissform’s sensor implementation and visual effect were written independently.

Updates use [Sparkle](https://sparkle-project.org/), with its [license and notices](docs/SPARKLE_LICENSE.txt) included in the app. Interface icons include [Iconly](https://iconly.pro) artwork under a paid license; see [asset provenance and reuse restrictions](docs/ICONLY.md). The connection click is adapted from [“Videogame Menu BUTTON CLICK” by Christopherderp](https://freesound.org/people/Christopherderp/sounds/342200/), licensed CC0. See [app artwork](Artwork/README.md) for the native icon sources.

**No open-source license has been selected.** Public availability of the source does not grant an open-source license. Third-party assets retain their own terms.
