# Settings design system

Glissform’s shared settings interface supports a growing collection of animations and quality-of-life features. Its current Infinite Screen and Privacy & About pages form a native macOS utility with soft geometry, adaptive surfaces, and restrained visual detail. `Sources/Glissform/SettingsDesign.swift` is the shared source of values. Measurements use macOS points.

## Layout

The page is a single column, 720 points wide, with 32-point content padding. Its window height follows the measured page content, including the 32-point bottom padding, and is capped to available screen space; both pages scroll when necessary. It resizes when navigating or showing/hiding the permission card. The Infinite Screen page groups its preview and angle controls, automatic starting-angle and pause-to-resume settings, and privacy footer. A permission card appears above the preview only when access is missing or briefly after a detected grant. Privacy & About shows the app name/version and separate privacy-information and access cards, with no introductory description or text below the cards.

| Spacing role | Points |
| --- | ---: |
| Closely related details | 4 |
| Title to supporting text | 8 |
| Related controls | 12 |
| Between cards | 16 |
| Card padding / grouped section spacing | 20 |
| About section groups | 24 |
| Header to cards / cards to footer | 28 |
| Page padding | 32 |

Small optical offsets can use 2 points. The angle unit retains its 1-point baseline gap and raised position. Symbol geometry, numeric-field width, native controls, and illustration coordinates do not need to follow the spacing scale. Slider actions sit 4 points below the slider without negative padding.

## Typography

| Role | Size and weight | Design |
| --- | --- | --- |
| Main page title | 28 semibold | Rounded |
| About headline | 24 semibold | Rounded |
| About section heading | 20 semibold | Rounded |
| Control and card title | 14 semibold | System |
| Body | 13 regular | System |
| Supporting text | 11 regular | System |
| Action label | 11 medium | System |
| Live angle | 28 light | Rounded, monospaced digits |
| Editable angle | 20 medium | Rounded, monospaced digits |

The degree symbol uses a 20-point regular font. Icons are vector artwork rather than font glyphs: angle chevrons and action icons use 16-point canvases, About details 20 points, footer lock 12 points, and feature tiles 24 points. These are component-specific optical roles. Primary text carries titles and values, secondary text carries explanations, and tertiary text is reserved for optional information.

## Colours and surfaces

- Background: macOS text background; controls and links use the user's system accent.
- Card fill: primary colour at 3.5%; outline: primary colour at 4%.
- Divider: native divider with a 2.5% primary overlay, spanning the whole card width.
- Field fill: primary colour at 4.5%; editing outline: accent at 65%.
- Feature icons: automatic angle selection uses a blue-leaning indigo tile and laptop symbol for measured setup; pause-to-resume uses a green tile and pause symbol for desktop restoration. Each tile fill uses its action colour at 16% opacity, while the adjacent toggle communicates its on/off state.
- Permission allowed: green `#30D158` fill at 16% opacity, with a contrasting check.
- Permission required: amber `#FF9F0A` fill at 16% opacity, with a contrasting attention mark.
- Switch and slider thumbs use white. Neutral surfaces adapt to light and dark appearances; the permission tints retain their semantic hue.

Colour is accompanied by a text state and a different icon mark. Missing permission offers “Open Settings…”; granted permission offers “Manage Access…”. Both open macOS permission management. The main page shows this card only when access is missing or during a three-second confirmation after a detected grant. Privacy & About always includes the same card. Authorized launches omit the main-page card; revocation restores it.

## Components and shape

All cards use the same 20-point corner radius, surface and outline, with 20-point inner padding. The preview, permission and settings layouts differ according to their content. Automatic angle and pause restoration each have a separate feature card, spaced 16 points apart. About uses the same card foundation, with separate privacy-information and access cards spaced 16 points apart; there is no divider inside the privacy-information card.

Controls use 8-point corners, the permission icon container uses 12-point continuous corners, and small arrow highlights use 4-point corners. Switches remain capsules. Permission, automatic-angle, and pause icons share a 44 × 44-point tile with a solid 16%-opacity fill and no border. They use Iconly Bold / Regular artwork on a 24-point canvas by default. Custom preserves path geometry and strengthens Iconly secondary layers to 56% in Light Mode and 43% in Dark Mode. Automatic-angle foreground is blue-leaning indigo `#435CCD` / `#667CE7` (Light / Dark), with a `#4E67D8` tile fill; green is `#2AB84D` / `#30D158`, and amber is `#E08C09` / `#FF9F0A`. Light Mode uses a modest darkening of the vivid Dark Mode colours to preserve the colourful appearance; these decorative icons have adjacent text labels and are not claimed to meet 3:1 in every colour. Bold uses the same foreground colours with its original solid artwork; Custom retains the two-tone treatment for comparison. Each feature card has one row with an icon, title, description, and toggle; pause duration remains fixed.

Angle arrows have independent 24 × 20-point targets and repeat while held. The numeric text area remains 38 points wide. Native slider behaviour is retained. Pause-to-resume uses a fixed two-second delay.

## Interaction

Custom buttons and arrows use the same hover and pressed fill strength (10% and 18%) and disabled opacity (45%). Back and Preview motion use the same filled button style; Back keeps a 2-point icon-to-text gap. Filled buttons have a 6% resting surface; button outlines use 18% on hover and 30% on press. Switch feedback is applied to its track. Disabled controls ignore hover and cannot activate.

Hover transitions use 120 ms; pressed feedback uses 80 ms; switch movement uses 160 ms. Reduce Motion removes these interpolations and uses the existing still illustration preview. Native keyboard traversal and button activation remain available; angle editing retains its accent outline. These settings styles do not alter the physical lid effect.

## Iconography

Use **Iconly Bold / Regular** for all interface icons. Preserve the original Bulk and Outline sets and the previous Custom mapping for comparison; the Developer menu in a `--dev` build switches all consumers immediately. Bold is restored on launch. `IconlySymbol`, `IconlyIcon`, and `IconlyLabel` are the shared entry points; do not introduce SF Symbols or hand-drawn replacement UI glyphs. SVG assets are bundled locally, cached, and rendered as templates to inherit foreground colours. Accessible names belong to the associated button or text; decorative glyphs are hidden from VoiceOver.

The up arrow rotates for down and back navigation (the preserved Outline set uses a chevron). Play and stop use solid Bold circular shapes with cutouts. Permission states use Shield Done and Shield information; the pause tile uses Pause Circle. The menu bar uses an 18-point monochrome template derived from the actual Clear app icon at 1× and 2×. ClearDark luminance becomes opacity, preserving its wave and rounded contours without colour. AppKit supplies the foreground colour and selected appearance. It stays unchanged by the developer Iconly selector. The original Glissform brand mark and explanatory animated laptop illustration remain distinct from the interface icon library.

See [Iconly provenance](ICONLY.md) for source names and asset terms.

## App icon

The app's brand icon is a rounded blue glass pane with a sweeping wave in `Artwork/Glissform.icon`. Its foreground texture preserves the soft gradient, convex shading, bright rim and highlight; a centred, smaller inset and continuous corners keep it close to the approved reference. It expresses a surface responding to motion across Glissform's experiences. Default has a pearl-white/light-silver base; Dark has a graphite base. macOS derives clear and tinted styles from the same shaded artwork, preserving material detail instead of substituting a flat wave. The system supplies the outer mask, background material and selected tint. These system icon styles are separate from the window's light/dark appearance and the developer Iconly selector. See [artwork notes](../Artwork/README.md).
