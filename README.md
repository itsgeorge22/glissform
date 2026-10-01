# Glissform

Subtle animations and quality-of-life improvements for everyday interactions on your Mac.

**Seamless Close is the first available feature:** your desktop appears to stay in place as you close your MacBook lid, with perspective, frost, and shadow responding to the movement. Glissform is designed to grow into a collection of useful experiences.

[Website](https://glissform.app/) · [Roadmap](ROADMAP.md)

Website source and deployment are maintained separately in the private [glissform-website repository](https://github.com/itsgeorge22/glissform-website); its `main` branch publishes through GitHub Actions.

## Project status

**Public beta:** [Download Glissform 0.1.0-beta.5](https://glissform.app/downloads/Glissform-0.1.0-beta.5.dmg) from [glissform.app](https://glissform.app/). The source repository is private.

The website presents the desktop landing page with fixed Customisable, Private, and F.A.Q navigation at widths of 1156px or more. As soon as scrolling begins, the same navbar smoothly gains a translucent, blurred material and removes it again at the top. The selected link follows the linked section occupying the largest visible area; the brand returns to the top and clears the selection. Its feature cards show still previews, cycle every ten seconds, and transition smoothly through automatic and manual selection, with hover, pressed, and keyboard-focus feedback. The Customisable grid provides interactive blur choices, starting-angle slider, and switches; timing values are illustrations. Narrower windows show a MacBook viewing message.

The website also includes a dedicated Seamless Close section with a large centred MacBook. Scrolling pins the preview and folds the physical lid shut, with perspective, blur and shadow following the gesture. It stays closed at the end and reopens only when scrolling back up. The preview uses bundled artwork, with an unpinned still image for Reduce Motion or unavailable graphics. As the lid lowers, it reveals “A Little Magic. Every Time You Close.” The section was published to glissform.app on 2026-10-01.

Open the DMG and drag Glissform into Applications. The beta is not Apple notarized, so macOS may block first launch; after a blocked attempt, use **System Settings → Privacy & Security → Open Anyway** if you trust the download. See [Apple's instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Seamless Close needs Screen Recording permission. Future beta updates are checked through the app; Automatic updates controls whether they download and install automatically. The public DMG and signed update feed are live, while an upgrade against that public feed has not yet been physically verified. Lock Screen animation is not available; Settings shows it as a planned feature.

Beta.5 fixes the installed beta.4 crash when closing starts. Beta.4 adds shared connection feedback, refined opening motion, revised defaults and an About update-check button. Beta.3 repairs launch after the beta.2 packaging defect and improves update discovery. Beta.2 added an Esc return for Seamless Close and an email contact page. Beta.1 added signed updates and configurable Seamless Close blur strength. Earlier alpha releases introduced **Battery Ripple** and renamed **Infinite Screen** to **Seamless Close**. See the [changelog](CHANGELOG.md) for version-specific changes and ongoing limitations.

## Current features

- Experience a lid-driven desktop animation with a continuous perspective fold, an upper edge that narrows throughout closure, optional High, Regular, or Subtle blur (Regular by default), and shadow.
- Reverse the effect by reopening the lid, including experimental opening after lid-close sleep using the same screenshot. The visible image can finish the final 5° automatically, carrying its visible motion and recent lid pace into a soft landing, with a soft inner edge glow that spreads inward, blooms with the contact click, and softly fades over the live desktop. A short click marks that connection. One **Connection effect** switch controls the glow and click together, defaults to on, and preserves the desktop return when off. Pause and Esc show the same glow only during the final 5° of their visible return, with the click scheduled to peak with the glow’s brightness pulse. Audio is prepared during the gesture and adjusted for the selected output’s reported delay; physical alignment on Bluetooth remains subject to device timing.
- Choose the starting angle manually or let a still-lid pause set it automatically, one degree below the held angle. Set a minimum lid angle for automatic detection, or set it to 0° to disable the threshold; **Begin at** remains the fallback until an angle is learned. Begin at defaults to 90° and Resume desktop after pause is enabled by default. Previously saved choices are preserved. Set each wait independently from 0.5 to 10 seconds (1 second by default).
- Keep Glissform running after its Settings window closes, with menu bar access by default.
- Press Esc during Seamless Close to use the same fold-to-flat return as pause restoration, whether the pause feature is on or off. Reopen above the starting angle to start another gesture.

Battery Ripple plays a green wave when power connects or a red wave when the built-in battery falls to 20%. The two events have independent saved switches and preview buttons; there is no overall Battery Ripple switch. A compact sidebar groups General, Seamless Close, and Battery Ripple in that order under Features, with Privacy & About and Send feedback under More. Privacy & About includes **Check for Updates…** beside the app name and current version. General controls whether Glissform keeps running after Settings closes, whether its menu bar icon appears, whether macOS launches it at login, and whether updates download and install automatically. With automatic installation off, the sidebar shows the existing Update card only when a newer installable version is found; its button opens the installer. When background running is on, closing Settings removes Glissform from the Dock even if its menu bar icon is hidden; opening the app again restores Settings. Seamless Close keeps its switch, live lid reading, and manual angle together in one card, with separate automatic-selection and pause cards and a page reset for its settings. Battery Ripple uses no screenshot or additional permission.

Unreleased development work adds the same connection feedback when a quick reopening reaches or passes the starting angle between sensor readings, preserving the existing lid-driven return and timing feedback to visible contact rather than its nearly invisible settling tail. The published beta.5 can still skip feedback on this path; physical validation of the timing refinement is pending.

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

The source repository and its [issue tracker](https://github.com/itsgeorge22/glissform/issues) are private, so public bug reports and feature suggestions are not available there. The Send feedback page opens an email addressed to [support@glissform.app](mailto:support@glissform.app) with the app and macOS versions in its editable body, and has an icon to copy the address for another email service. For detailed feature behaviour, see the [app guide](docs/APP_GUIDE.md).

## Development

[Contributing](CONTRIBUTING.md) · [Testing](docs/TESTING.md) · [Releasing](docs/RELEASING.md) · [Architecture](docs/ARCHITECTURE.md) · [Design system](docs/DESIGN_SYSTEM.md) · [Changelog](CHANGELOG.md)

Developer build and verification steps are documented in [Contributing](CONTRIBUTING.md). CI does not verify physical lid behaviour.

Local builds are **Glissform Dev**, with a red icon, separate app identity and settings, and no public update checks. The installed beta from the DMG remains **Glissform**, with the blue icon and signed updates. Use an explicit release build only when preparing a versioned DMG; avoid running both apps' effects at once.

## Credits and licensing

The [LidAngleSensor project](https://github.com/samhenrigold/LidAngleSensor) and [Clamshell](https://github.com/danielradosa/clamshell) were consulted for the HID reports. Glissform's sensor implementation and visual effect were written independently. Updates use [Sparkle](https://sparkle-project.org/), whose [license and notices](docs/SPARKLE_LICENSE.txt) are included with the app. Some interface icons are by [Iconly](https://iconly.pro), used under the owner's paid license; see [provenance](docs/ICONLY.md). See [app artwork](Artwork/README.md) for the native icon sources.

The assisted-opening click uses a trimmed version of [“Videogame Menu BUTTON CLICK” by Christopherderp](https://freesound.org/people/Christopherderp/sounds/342200/), licensed CC0.

**No open-source license has been selected.** The source repository is private. Third-party assets retain their own terms.
