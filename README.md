# Glissform

Subtle animations and quality-of-life improvements for everyday interactions on your Mac.

**Infinite Screen is the first available feature:** your desktop appears to stay in place as you close your MacBook lid, with perspective, frost, and shadow responding to the movement. Glissform is designed to grow into a collection of useful experiences.

[Report a bug](https://github.com/itsgeorge22/glissform/issues/new?template=bug_report.yml) · [Suggest a feature](https://github.com/itsgeorge22/glissform/issues/new?template=feature_request.yml) · [Roadmap](ROADMAP.md)

## Project status

**In development — not yet available for public download.** The current development version is 0.1.0-alpha.8.

The app will be available once a `.dmg` is ready and published on GitHub. Download links and installation instructions will be added then.

The main branch also contains the unreleased **Battery Ripple** experience. It is not part of the published alpha.8 source tag.

See the [changelog](CHANGELOG.md) for released changes and any upcoming work.

## Current features

- Experience a lid-driven desktop animation with full-angle perspective, progressive frost, and shadow.
- Reverse the effect by reopening the lid, including experimental opening after lid-close sleep using the same screenshot.
- Choose the starting angle manually or let a two-second lid pause set it automatically, one degree below the held angle; optionally restore desktop access after a pause.
- Keep Glissform running from the menu bar when its settings window is closed.

On unreleased main, Battery Ripple plays a green wave when power connects or a red wave when the built-in battery falls to 20%. The two events have independent saved switches; there is no overall Battery Ripple switch. A compact sidebar groups Infinite Screen and Battery Ripple under Features, with Privacy & About and a Found a bug placeholder under More. Infinite Screen keeps its live lid reading and separate angle, automatic-selection, and pause cards. Battery Ripple uses no screenshot or additional permission.

## Compatibility

| Requirement | Current status |
| --- | --- |
| macOS | 14 or later is the deployment minimum; this is not a guarantee of compatibility on every version. |
| Hardware | A Metal-capable MacBook with a compatible lid-angle sensor. |
| Tested hardware | MacBook Air M5 15-inch (Mac17,4), the development machine. Other models are unverified. |
| Permission | Infinite Screen needs Screen Recording access for individual desktop screenshots. Battery Ripple does not. |

The lid sensor uses an undocumented protocol. Glissform tries fractional angle readings and falls back to whole degrees when unavailable. If you try Glissform on another configuration, [share a compatibility report](https://github.com/itsgeorge22/glissform/issues/new?template=compatibility_report.yml), whether it works or fails. Community reports help build coverage; they are not hardware certification.

## Privacy

One screenshot is taken per closing attempt and kept in memory. On a fast close it may be requested just before the selected start angle; if the lid reverses or stops before that angle, the hidden image is discarded. A completed closing image may remain through lid-close sleep for the following opening; it stays hidden while locked or asleep and is released after completion or cancellation. There is no continuous recording, audio capture, screenshot saving, networking, or analytics. Normal system sleep remains enabled.

Battery Ripple reads the Mac's power-source and built-in battery charge state. It does not capture screen content and stops when the display sleeps or the session locks.

## Feedback and support

Track bugs and their resolution in [GitHub Issues](https://github.com/itsgeorge22/glissform/issues). For detailed feature behaviour, see the [app guide](docs/APP_GUIDE.md).

A GitHub account is required to submit a report. Check existing issues first; if yours is already reported, add useful details there.

| Submit | Use it for |
| --- | --- |
| [Bug report](https://github.com/itsgeorge22/glissform/issues/new?template=bug_report.yml) | Something fails or behaves unexpectedly. |
| [Feature suggestion](https://github.com/itsgeorge22/glissform/issues/new?template=feature_request.yml) | An improvement or a new experience you would find useful. |
| [Compatibility report](https://github.com/itsgeorge22/glissform/issues/new?template=compatibility_report.yml) | Results from your Mac, including successful use. |

Reports are public. Omit serial numbers, credentials, and private desktop content. Glissform is a small independent project; responses and feature delivery have no guaranteed timeline.

## Development

[Contributing](CONTRIBUTING.md) · [Testing](docs/TESTING.md) · [Architecture](docs/ARCHITECTURE.md) · [Design system](docs/DESIGN_SYSTEM.md) · [Changelog](CHANGELOG.md)

Developer build and verification steps are documented in [Contributing](CONTRIBUTING.md). CI does not verify physical lid behaviour.

## Credits and licensing

The [LidAngleSensor project](https://github.com/samhenrigold/LidAngleSensor) and [Clamshell](https://github.com/danielradosa/clamshell) were consulted for the HID reports. Glissform's sensor implementation and visual effect were written independently. Interface icons are by [Iconly](https://iconly.pro), used under the owner's paid license; see [provenance](docs/ICONLY.md). See [app artwork](Artwork/README.md) for the native icon sources.

**No open-source license has been selected.** Public source availability does not itself grant an open-source license. Third-party assets retain their own terms.
