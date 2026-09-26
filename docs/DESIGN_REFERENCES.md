# Settings reference study

This study informed the unreleased settings redesign on 2026-09-26. It compares visible app interfaces from official product pages and documentation; Alcove's settings were inspected through a third-party screenshot gallery. Published screenshots may represent different app versions. The comparison concerns composition and materials, not implementation technology or popularity rankings.

| Reference | Visible pattern | Application to Glissform |
| --- | --- | --- |
| [Juicy press screenshots](https://getjuicy.app/press), including [menu-bar settings](https://sevendegrees.dominiksobe.com/juicy-media/juicy-settings-menu-bar.jpg) | Compact controls, expressive coloured icons, and restrained material around settings. | Give each feature an identity while keeping routine controls quiet. |
| [Alcove settings gallery](https://appstacks.club/alcove) | Recognizable macOS sidebar and detail composition, with clear groups and trailing controls. | Keep navigation immediately understandable and settings aligned. |
| [Raycast Settings](https://manual.raycast.com/settings) and [Notes](https://www.raycast.com/core-features/notes) | A softly differentiated sidebar in Settings; a compact floating Notes window with a quiet toolbar and clear title/body hierarchy. | Use material and typography to establish hierarchy without repeating boxes. |
| [CleanShot Settings](https://cleanshot.com/features#settings) | Meaningful coloured navigation icons, compact grouped rows, and consistent trailing controls. | Preserve useful density and predictable control placement. |
| [Screen Studio Background inspector](https://screen.studio/guide/background) | A narrow charcoal inspector, subtle separators, compact labels, and a single purple accent around colourful content. | Keep feature controls legible and restrained. |
| [Supercharge](https://sindresorhus.com/supercharge) | Compact utility settings, aligned rows, faint group boundaries, and strong colour mainly for active controls. | Use as a density reference while developing Glissform's own visual character. |
| [Granola app overview](https://docs.granola.ai/help-center/getting-started/granola-101) | Warm pale surfaces, a softly differentiated sidebar, generous content spacing, and few outlined containers. | Give the whole window a coherent atmosphere and group through space. |
| [Craft 3.2.6](https://www.craft.do/blog/craft-update-3-2-6), [workspace screenshot](https://www.craft.do/images/content/blog/craft-update-3-2-6/image-1.jpg) | A pale continuous workspace, subdued sidebar selection, subtle content borders, and glass concentrated in a top workspace control. | Keep navigation subdued against a continuous window material. |

[Apple's materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) provides the platform context for native materials and readable content. Glissform keeps the navigation background translucent and detail controls on opaque, readable surfaces.

## Glissform's direction

The shared idea is light responding to a familiar physical action. The current settings layout keeps native window controls in the sidebar, compact tabs with quiet selection, saturated sidebar icon tiles, and subtler page tiles. Separate neutral cards make the feature switches and Infinite Screen controls easy to scan. The existing capsule switches retain the app's character.

The implementation uses Glissform artwork and licensed Iconly interface icons. Reference screenshots are research material and are not bundled in the app. Final appearance must be judged in the running app, including native titlebar placement and accessibility appearances.
