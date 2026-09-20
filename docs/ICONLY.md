# Iconly assets

Glissform's default interface set uses **Iconly Bold / Regular** throughout, selected from the project owner's signed-in [Iconly library](https://web.iconly.pro/) on 2026-09-20. Outline / Regular, Bulk / Regular, and the previous Custom mix remain available alongside it.

| Asset | Bold / Bulk name (Outline name if different) | Use |
| --- | --- | --- |
| shieldDone | Shield Done | Granted screen permission |
| shieldInfo | Shield information (shield info) | Required screen permission |
| pause | Pause Circle | Pause-to-resume feature |
| chevronUp | Arrow - Up 2 (Chevron Up) | Angle increment; rotated for decrement and Back |
| play | Play | Preview playback |
| stop | Stop Circle | End preview |
| lock | Lock | Privacy footer and privacy detail |
| copy | Copy 1 | Single-screenshot explanation |
| memory | cpu processor | Temporary in-memory screenshot |
| laptop | mac laptop notebook | Retained original artwork; replaced in the menu bar by Glissform’s brand mark |

The vectors are in the `Bold`, `Bulk`, and `Outline` subdirectories of `Sources/Glissform/Resources/Iconly`. All three sets are retained without changing their asset bytes when switching styles. SVG wrapper metadata and colour declarations were normalised; original path coordinates, transforms, fill rules, and opacity were retained. Bold uses solid geometry with cutouts; Bulk keeps translucent secondary shapes. All sets inherit the surrounding foreground colour. Do not add strokes to these filled vectors.

`IconlyAppearance.shared.style` is the observable session selection, initially `.bold`; `IconlyStyle.current` exposes it to AppKit. Each SwiftUI icon observes the selection without resetting view or animation state. Images are cached by style and symbol. All three source sets remain bundled unchanged. The preserved Custom mix resolves each symbol to a source style in `IconlySymbol.customStyle`; the current product default is Bold. Custom card icons use derived Bulk assets in `CustomCards/Light` and `CustomCards/Dark`. Path geometry is unchanged; the secondary layer is 56% in Light Mode and 43% in Dark Mode, with appearance-specific foreground colours. Only Custom permission and pause card tiles opt into these derived assets; Bold uses the original solid assets with the same appearance-specific card colours. Original Bulk, Bold, and Outline assets, About icons, and other consumers remain unchanged; tile fills stay at 16%. The preview retains its existing Play / Stop behavior and uses Bold for both states.

Build with `bash scripts/build.sh --dev` to enable **Developer → Icon Style → Bulk / Bold / Outline / Custom**. Shortcuts are ⌥⌘1, ⌥⌘2, ⌥⌘3, and ⌥⌘4. Switching immediately updates every Iconly interface icon; the separate branded menu bar glyph stays unchanged. The choice is session-only; restart returns to Bold. A normal build writes `GlissformDeveloperTools=false` and omits the menu. There is no new production settings control or preference.

Swift Package Manager includes the directory as a resource; `scripts/build.sh` copies the resource bundle into the app before signing. `IconlyIcon.swift` supplies cached native template images for SwiftUI and AppKit. All icons work offline. The synthetic material preview reuses this same library.

## Third-party rights

Icon artwork remains copyright Iconly / Piqo. The project owner confirmed that their paid license permits this project's public, commercial, and private use. Inclusion here does not grant an independent license to extract, resell, or redistribute Iconly assets. Consult your applicable purchase agreement and [Iconly's licensing guide](https://iconly.pro/pages/licensing-guide) for reuse. This notice does not assign an open-source license to Glissform or its third-party assets.

The original Glissform brand mark and the animated laptop illustration are project artwork, not Iconly assets.
