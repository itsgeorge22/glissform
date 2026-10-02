# Settings design system

Glissform’s shared settings interface supports a growing collection of animations and quality-of-life features. Its Seamless Close, General, Privacy & About, and Send feedback pages form a native macOS utility with soft geometry, adaptive surfaces, and restrained visual detail. `Sources/Glissform/SettingsDesign.swift` is the shared source of values. Measurements use macOS points.

## Layout

A 204-point sidebar sits beside a 544-point scrolling detail column, for a 748-point window width. Detail pages use 24-point padding. An empty native unified toolbar places the macOS window controls over the continuous sidebar material. The full-size content is clipped to a continuous 20-point window shape with a fine edge outline. A faint, diffuse custom shadow follows the visible rounded surface in a noninteractive backing window. The Features group lists General and Seamless Close in that order; More follows directly below with Privacy & About and Send feedback. Both groups have small title-case section headings. Compact rows have 28-point icon tiles, with 4 points between adjacent tabs. Tab labels remain 13-point medium in both selected and unselected states; the row fill indicates selection. Buttons expose the selected page and support Up/Down navigation. When automatic installation is off and an installable update is detected, a compact card appears at the bottom of the sidebar with that version and an Update button. Window height stays at 560 points, capped to available screen space. Each detail page starts at the top when selected; page changes and permission cards do not resize the window. Main card sections use 12-point top, bottom, and left insets, with 24 points on the right; support sections use 24 points on the sides and 20 points on the top and bottom. Cards are separated by 12 points. The shared source is `SettingsDesign.Metrics` and `SettingsDesign.Spacing`.

Seamless Close has a title and short description. Seamless Close combines its enable row and manual angle controls in one card, with a full-width divider; automatic selection and pause restoration use separate cards. A permission card appears when access is missing or briefly after a detected grant. Feature pages have no preview illustration or privacy footer. General uses the same card geometry for its four active switches: its sidebar tile, card icon tiles, and symbols are gray. Automatic updates has a switch; the only remaining outlined Soon tag is on Lock Screen support. Login approval guidance appears beneath its switch when needed. Privacy & About uses a softened red sidebar tile (#ED6258) and shows the app name/version with separate privacy-information and access cards. Send feedback uses a softened green sidebar tile (#4BC76B) and matching green card artwork and offers an email action, a copy-address icon, guidance, and a privacy note.

Use the shared named spacing tokens for related labels, control rows, group insets, and page padding. Small optical offsets may use 2 points. The angle unit retains its 1-point baseline gap and raised position. Symbol geometry, numeric-field width, and native controls are component-specific optical roles.

## Typography

Use compact system typography for page titles, section labels, and settings rows. Rounded 24-point headlines use −0.24-point tracking, about −1% of their font size; supporting descriptions stay secondary. The live lid reading is compact, while the editable angle remains larger. Both use monospaced digits to avoid movement as readings change. The shared source is `SettingsDesign.Typography`.

| Role | Size and weight |
| --- | --- |
| Feature page title | 24 semibold, rounded |
| About title | 24 semibold, rounded |
| Section label | 17 semibold, system |
| Control title | 13 semibold, system |
| Body / supporting text | 13 / 11 regular, system |
| Live lid reading | 13 medium, rounded monospaced digits |
| Editable angle | 17 medium, rounded monospaced digits |

Action labels remain readable without competing with the feature title. Primary text carries titles and values, secondary text carries explanations, and tertiary text is reserved for optional information. Decorative icons have adjacent text labels.
Feature-card descriptions use short, direct present-tense statements that fit one line at the standard window width. Both still-lid controls have separate saved wait controls from 0.5 to 10 seconds, each defaulting to one second. Privacy & About describes Glissform’s data use across its effects, with temporary screen images explained separately from lid angle.

## Colours and materials

- The opaque detail surface uses a very subtle pale or charcoal gradient; settings groups use adaptive neutral surfaces. The user's system accent identifies ordinary controls and links.
- The softened blue (#258DEB in sRGB) distinguishes Seamless Close across its sidebar tile and main feature icon in Light and Dark appearances. Semantic colour fills the compact sidebar tiles with white symbols. Page tiles use a 12%-opacity tint and coloured symbols.
- Selected navigation rows use a compact neutral fill and rounded corners. A standard macOS behind-window material provides the continuous navigation background; the native unified toolbar supplies the window controls. A rounded content clip shapes all four corners without a visible titlebar separator. A faint, diffuse custom shadow follows the visible rounded surface in a noninteractive backing window.
- Keep ordinary settings groups neutral and legible. Do not apply glass to every row, field, or informational card.
- Preserve text, icons, and visible focus states when materials change. Appearance and accessibility fallbacks require visual checks on the actual supported configuration.
- Permission allowed uses a green check; permission required uses an amber attention mark. Colour is always accompanied by a text state and a different icon mark.

Missing permission offers “Open Settings…”; granted permission offers “Manage Access…”. Both open macOS permission management. The Seamless Close page shows this card only when access is missing or during a three-second confirmation after a detected grant. Privacy & About always includes the same card. Authorized launches omit the main-page card; revocation restores it.

## Components and shape

Separate neutral cards organize each control and feature toggle. Every card in the right detail area has a 16-point outer radius, and its 44-point icon tiles have 12-point corners. Main card sections, including the screen-access card, use 12-point top, bottom, and left padding, with 24 points on the right. Support sections, including privacy information, use 24-point side padding and 20-point vertical padding; the privacy-information card keeps 16-point spacing between its contents. Sidebar icon tiles have an 8-point radius; their rows use equal 7-point insets and a 15-point radius. Shared radii and inset values live in `SettingsDesign.Radius`, `SettingsDesign.Spacing`, and `SettingsDesign.Metrics`.

Feature and permission tiles use 12%-opacity semantic fills and coloured vector artwork on 44-point tiles with 12-point corners. Sidebar icon tiles keep saturated fills and white artwork at 28 points with 8-point corners. Seamless Close uses #258DEB blue, automatic angle detection muted violet, Connection effect orange (#FF9500 container tint, #D97706 Light / #FFB340 Dark symbol), Blur light blue, pause green, and missing permission amber. Planned Lock Screen support uses neutral gray. Decorative tiles have adjacent text labels; colour alone does not convey control state.

Angle and wait-time arrows use independent 20 × 17-point targets with 14-point glyphs and repeat while held. The numeric text area is 31 points wide, with a matching 17-point degree or seconds symbol, 7-point vertical inset and radius, and 4-point trailing inset. The wait arrows change the saved time in 0.5-second steps from 0.5 to 10 seconds. Native slider behaviour is retained for the angle. The restored custom switches have 44 × 22-point capsule tracks, white 26 × 18-point thumbs, a two-point inset, and system-accent enabled colour. Their accessibility representation is a native Toggle. Page selection preserves saved controls.

## Feature pages

Seamless Close keeps its switch and live lid reading in the same card as the manual-angle controls. Full-width dividers separate the switch rows from the lower controls in the main, automatic-selection, pause, and Blur cards. Automatic selection has a second divided lower section for **Detect above**, using the same angle field as **Begin at**; its 0° option disables the detection threshold, and the arrows jump between 0° and 20°. Each lower control section has 24-point side padding and 20-point vertical padding; switch rows keep 24-point trailing padding. The Esc hint remains visible below the angle controls with Pause on or off. Blur has three equally spaced rendered preview images with High, Regular, and Subtle captions. Each uses the same supplied wallpaper at a 42° fold. The selected preview has a two-point system-accent outline matching enabled switches, separated from the image by a four-point gap; Regular starts selected, while High preserves the earlier blur. Selecting a strength saves it and changes both blur passes. A quiet Reset to defaults button sits below the Seamless Close cards and is disabled when all controls on that page match their defaults. The wait rows use the same title-and-secondary-caption hierarchy as the switch rows to explain what each timer controls.

## Interaction

Ordinary links and controls retain clear hover, pressed, disabled, and focus states. Native SwiftUI button activation remains responsible for interaction, and decorative overlays must not intercept input. Disabled controls do not show interactive hover feedback or activate.

Active sidebar tabs, switches, buttons, step arrows, selectable Blur previews, and the Update button when available use AppKit's system pointing-hand cursor throughout hover. Disabled controls that would use a pointing hand when enabled instead show the system operation-not-allowed cursor. Angle text fields keep the text cursor, and the AppKit slider keeps its native cursor. The Soon tags retain the default arrow.

Custom hover, pressed, and switch timings remain centralized in `SettingsDesign.Feedback`; switch movement uses 0.16 seconds, hover 0.12 seconds, and pressed feedback 0.08 seconds. Sidebar presses change the row fill without dimming the icon tile. Keyboard traversal and button activation remain available; sidebar Up/Down selection and focus must remain aligned. Angle and wait-time fields use a light neutral hover fill and border; angle editing retains its accent outline. Arrow highlight backgrounds have square corners and no left inset; the rounded field clips their outer edges. Blur strength hover darkens only the rendered preview image; the selected two-point accent outline remains distinct. The sidebar Update button uses a light overlay on hover and darker overlay while pressed without changing its layout; it appears only when automatic updates are off and an installable update is available. Page navigation does not change Seamless Close's saved controls.

## Reference study

The [reference study](DESIGN_REFERENCES.md) compares actual app screenshots from Alcove, Juicy, Raycast, CleanShot, Screen Studio, Supercharge, Granola, and Craft alongside [Apple's materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials). The current direction draws on Alcove's compact navigation and native traffic-light placement while retaining Glissform's own coloured tiles and card composition. Glissform uses its own brand artwork and licensed Iconly interface icons. Live Dark appearance and earlier-macOS verification remain pending.

## Iconography

Use the supplied SVGs for Seamless Close (monitor), Blur (raindrop), automatic starting-angle detection (scan object), Send feedback (messages), and General’s four cards (checked window, grid interface, user, download). Automatic detection has a muted violet tile and symbol, while Blur uses the earlier light blue; the custom hinge-and-angle asset remains available for comparison. The Lock Screen support icon and tile are neutral gray. Remaining interface icons use **Iconly Bold / Regular**. Preserve the original Bulk and Outline sets and the previous Custom mapping for comparison; the Developer menu in the default Dev build switches Iconly consumers immediately. Bold is restored on launch. `FeatureIcon` and `IconlyIcon` are the shared vector entry points. SVG assets are bundled locally, cached, and rendered as templates to inherit foreground colours. Accessible names belong to the associated button or text; decorative glyphs are hidden from VoiceOver.

The up arrow rotates for down and back navigation (the preserved Outline set uses a chevron). Permission states use Shield Done and Shield information; the pause tile uses Pause Circle. The menu bar uses an 18-point monochrome template derived from the actual Clear app icon at 1× and 2×. ClearDark luminance becomes opacity, preserving the wave and rounded contours without colour. AppKit supplies the foreground colour and selected appearance. It stays unchanged by the developer Iconly selector. The original Glissform brand mark remains distinct from the interface icon library.

See [Iconly provenance](ICONLY.md) for source names and asset terms.

## App icon

The app's brand icon is a rounded blue glass pane with a sweeping wave in `Artwork/Glissform.icon`. Its foreground texture preserves the soft gradient, convex shading, bright rim and highlight; a centred, smaller inset and continuous corners keep it close to the approved reference. It expresses a surface responding to motion across Glissform's experiences. Default has a pearl-white/light-silver base; Dark has a graphite base. macOS derives clear and tinted styles from the same shaded artwork, preserving material detail instead of substituting a flat wave. The system supplies the outer mask, background material and selected tint. These system icon styles are separate from the window's light/dark appearance and the developer Iconly selector. See [artwork notes](../Artwork/README.md).
