# Settings design system

Glissform’s shared settings interface supports a growing collection of animations and quality-of-life features. Its Infinite Screen, Battery Ripple, Privacy & About, and Found a bug pages form a native macOS utility with soft geometry, adaptive surfaces, and restrained visual detail. `Sources/Glissform/SettingsDesign.swift` is the shared source of values. Measurements use macOS points.

## Layout

A 204-point sidebar sits beside a 544-point scrolling detail column, for a 748-point window width. Detail pages use 24-point padding. An empty native unified toolbar places the macOS window controls over the continuous sidebar material. The full-size content is clipped to a continuous 20-point window shape with a fine edge outline. A faint, diffuse custom shadow follows the visible rounded surface in a noninteractive backing window. The Features and More groups have small title-case section headings, with More directly below the feature tabs. Compact rows have 28-point icon tiles, with 4 points between the two feature tabs. Buttons expose the selected page and support Up/Down navigation. Window height stays at 560 points, capped to available screen space. Each detail page starts at the top when selected; page changes and permission cards do not resize the window. Feature cards use 12-point insets and 12-point gaps. The shared source is `SettingsDesign.Metrics` and `SettingsDesign.Spacing`.

Both feature pages have a title and short description. Infinite Screen has an enable card and distinct cards for manual angle, automatic selection, and pause restoration. A permission card appears when access is missing or briefly after a detected grant. Battery Ripple has two independently saved event cards, for power connection and battery reaching 20%, with no overall enable card. Feature pages have no preview illustration or privacy footer. Privacy & About shows the app name/version and separate privacy-information and access cards. Found a bug is an empty placeholder with a short empty-state message.

Use the shared named spacing tokens for related labels, control rows, group insets, and page padding. Small optical offsets may use 2 points. The angle unit retains its 1-point baseline gap and raised position. Symbol geometry, numeric-field width, and native controls are component-specific optical roles.

## Typography

Use compact system typography for page titles, section labels, and settings rows. Rounded page titles lead the hierarchy; supporting descriptions stay secondary. The live lid reading is compact, while the editable angle remains larger. Both use monospaced digits to avoid movement as readings change. The shared source is `SettingsDesign.Typography`.

| Role | Size and weight |
| --- | --- |
| Feature page title | 24 semibold, rounded |
| About title | 24 semibold, rounded |
| Section label | 17 semibold, system |
| Control title | 13 semibold, system |
| Body / supporting text | 13 / 11 regular, system |
| Live lid reading | 13 medium, rounded monospaced digits |
| Editable angle | 20 medium, rounded monospaced digits |

Action labels remain readable without competing with the feature title. Primary text carries titles and values, secondary text carries explanations, and tertiary text is reserved for optional information. Decorative icons have adjacent text labels.

## Colours and materials

- The opaque detail surface uses a very subtle pale or charcoal gradient; settings groups use adaptive neutral surfaces. The user's system accent identifies ordinary controls and links.
- Indigo distinguishes Infinite Screen; emerald identifies Battery Ripple's sidebar tile and power-connection card, while red identifies its low-battery card and effect. Saturated semantic colour fills the compact sidebar tiles with white symbols. Page tiles use a 12%-opacity tint and coloured symbols.
- Selected navigation rows use a compact neutral fill and rounded corners. A standard macOS behind-window material provides the continuous navigation background; the native unified toolbar supplies the window controls. A rounded content clip shapes all four corners without a visible titlebar separator. A faint, diffuse custom shadow follows the visible rounded surface in a noninteractive backing window.
- Keep ordinary settings groups neutral and legible. Do not apply glass to every row, field, or informational card.
- Preserve text, icons, and visible focus states when materials change. Appearance and accessibility fallbacks require visual checks on the actual supported configuration.
- Permission allowed uses a green check; permission required uses an amber attention mark. Colour is always accompanied by a text state and a different icon mark.

Missing permission offers “Open Settings…”; granted permission offers “Manage Access…”. Both open macOS permission management. The Infinite Screen page shows this card only when access is missing or during a three-second confirmation after a detected grant. Privacy & About always includes the same card. Authorized launches omit the main-page card; revocation restores it.

## Components and shape

Separate neutral cards organize each control and feature toggle. Cards use 18-point corners and compact insets. Sidebar icon tiles have an 8-point radius; their rows use equal 7-point insets and a 15-point radius. Shared radii and inset values live in `SettingsDesign.Radius`, `SettingsDesign.Spacing`, and `SettingsDesign.Metrics`.

Feature and permission tiles use 12%-opacity semantic fills and coloured Iconly artwork on 44-point tiles with 12-point corners. Sidebar icon tiles keep saturated fills and white artwork at 28 points with 8-point corners. Automatic-angle blue, pause green, and missing-permission amber distinguish their meanings. Decorative tiles have adjacent text labels; colour alone does not convey control state.

Angle arrows retain independent 24 × 20-point targets and repeat while held. The numeric text area remains 38 points wide. Native slider behaviour is retained. The restored custom switches have 44 × 22-point capsule tracks, white 26 × 18-point thumbs, a two-point inset, and system-accent enabled colour. Their accessibility representation is a native Toggle. Pause-to-resume uses a fixed two-second delay. Battery Ripple's two event switches are independently saved, and page selection changes neither state.

## Feature pages

Infinite Screen keeps its live lid reading in the manual-angle card. The separate controls preserve the existing trigger and pause behaviour. Neither feature page includes an illustration or preview action.

Battery Ripple plays green only on a real battery-to-external-power transition and red only when the unplugged built-in battery crosses down to 20% or less, provided the corresponding switch is enabled. Opening its settings page displays no synthetic sample and starts no desktop effect.

## Interaction

Ordinary links and controls retain clear hover, pressed, disabled, and focus states. Native SwiftUI button activation remains responsible for interaction, and decorative overlays must not intercept input. Disabled controls ignore hover and cannot activate.

Custom hover, pressed, and switch timings remain centralized in `SettingsDesign.Feedback`; switch movement uses 0.16 seconds, hover 0.12 seconds, and pressed feedback 0.08 seconds. Sidebar presses change the row fill without dimming the icon tile. Keyboard traversal and button activation remain available; sidebar Up/Down selection and focus must remain aligned. Angle editing retains its accent outline. Page navigation does not change either Battery Ripple event state or Infinite Screen's saved controls.

## Reference study

The [reference study](DESIGN_REFERENCES.md) compares actual app screenshots from Alcove, Juicy, Raycast, CleanShot, Screen Studio, Supercharge, Granola, and Craft alongside [Apple's materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials). The current direction draws on Alcove's compact navigation and native traffic-light placement while retaining Glissform's own coloured tiles and card composition. Glissform uses its own brand artwork and licensed Iconly interface icons. Live Dark appearance and earlier-macOS verification remain pending.

## Iconography

Use **Iconly Bold / Regular** for interface icons, with system bolt and battery symbols for Battery Ripple. Preserve the original Bulk and Outline sets and the previous Custom mapping for comparison; the Developer menu in a `--dev` build switches all consumers immediately. Bold is restored on launch. `IconlySymbol`, `IconlyIcon`, and `IconlyLabel` are the shared entry points; avoid hand-drawn replacement UI glyphs. SVG assets are bundled locally, cached, and rendered as templates to inherit foreground colours. Accessible names belong to the associated button or text; decorative glyphs are hidden from VoiceOver.

The up arrow rotates for down and back navigation (the preserved Outline set uses a chevron). Permission states use Shield Done and Shield information; the pause tile uses Pause Circle. The menu bar uses an 18-point monochrome template derived from the actual Clear app icon at 1× and 2×. ClearDark luminance becomes opacity, preserving the wave and rounded contours without colour. AppKit supplies the foreground colour and selected appearance. It stays unchanged by the developer Iconly selector. The original Glissform brand mark remains distinct from the interface icon library.

See [Iconly provenance](ICONLY.md) for source names and asset terms.

## App icon

The app's brand icon is a rounded blue glass pane with a sweeping wave in `Artwork/Glissform.icon`. Its foreground texture preserves the soft gradient, convex shading, bright rim and highlight; a centred, smaller inset and continuous corners keep it close to the approved reference. It expresses a surface responding to motion across Glissform's experiences. Default has a pearl-white/light-silver base; Dark has a graphite base. macOS derives clear and tinted styles from the same shaded artwork, preserving material detail instead of substituting a flat wave. The system supplies the outer mask, background material and selected tint. These system icon styles are separate from the window's light/dark appearance and the developer Iconly selector. See [artwork notes](../Artwork/README.md).
