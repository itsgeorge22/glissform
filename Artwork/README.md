# Glissform app icon

`Glissform.icon` is the editable Icon Composer source. `Reference/Glissform-approved.png` preserves the owner's selected blue-wave concept for visual comparison; it is not bundled into the app.

The native asset adapts that concept on Icon Composer's 1024 × 1024 canvas. `Assets/BlueGlass.png` isolates the rounded blue pane, preserving its soft blue-to-cyan wave, convex shading, bright rim and top-left highlight. It uses 84% of its imported size, with no horizontal offset and a 3-point downward correction for the artwork's slightly uneven transparent margins. Position is checked against the rendered glass bounds, not just the PNG canvas. The outer background is an Icon Composer fill; macOS supplies the outer mask and background material. The foreground deliberately retains the approved illustration's glass shading instead of replacing it with a flatter system effect. Native rendering remains an adaptation, not a pixel-identical copy of the reference.

- **Default / light:** a pearl-white to light-silver base with the blue glass wave.
- **Dark:** a graphite base with the same blue wave.
- **Mono:** macOS derives clear and tinted appearances from the same shaded PNG. There is no separate flat wave silhouette. The rim, highlight and continuous wave shading remain present, and macOS applies the user's selected tint.

Open `Glissform.icon` in Icon Composer to inspect all appearances. The system's icon style is independent of the app window's appearance. Do not add a custom icon-style preference or assign a raster image to `NSApp.applicationIconImage`: the bundled asset must remain under system control. Launch resets that property to `nil` after foreground activation, which asks AppKit to restore the native bundle icon.

`bash scripts/build.sh` requires Xcode 26 or later. It compiles the source with Apple's `actool`, copies the resulting native icon catalog and legacy `.icns` into the app, and merges the compiler's icon metadata into `Info.plist` before signing. The legacy rendition supports the app's macOS 14 deployment target; native clear/tinted appearances require macOS 26 or later.

Validate the compiled app in the Dock, Finder, and Privacy & About, including default, dark, clear light/dark, and tinted styles. The Icon Composer preview and actual system rendering are the acceptance checks; SVG previews alone do not establish the final material appearance. See [testing](../docs/TESTING.md).

The build updates the `.app` directory's modification date after replacing its icon resources, so Launch Services can detect in-place development changes. Verified with Xcode 27 on macOS 27: native compilation, all six rendition exports, the updated Privacy & About icon, and Finder switching from Default to Clear and Tinted without losing the material shading. The in-app header uses AppKit's application image and does not live-follow the Finder style. The owner confirmed the corrected icon displays properly in the Dock. Older-macOS runtime appearance remains an acceptance check.

## Artwork preparation

Prepared from the owner's approved image with the built-in image editing tool. The extraction prompt was:

> Use case: background-extraction. Edit target: attached approved Glissform app icon. Extract ONLY the existing blue glass rounded-square pane as a precisely faithful isolated artwork layer on a truly transparent RGBA background. Remove the dark graphite outer backplate and the bottom external drop shadow completely. Preserve the blue pane EXACTLY: same very rounded continuous corners, bulging convex glass, cyan rounded thick rim, delicate bright edge, top-left smooth soft white specular highlight, deep cobalt/navy upper-left, glowing cyan lower-right, and the single sweeping soft diagonal wave. Do not flatten the shading, do not replace it with vector shapes, do not remove its own glass bevel or rim. No new shapes, no redesign. Center it with generous transparent padding of about 10 percent on EACH side of a square canvas, so the blue pane occupies 80 percent of canvas width and height. Front view, square aspect ratio, symmetric placement. Crisp clean transparent outside edge, no grey halo or black frame. Preserve all shading and material details inside the blue glass pane. No text, no labels.

References: [Apple's app icon guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons), [Icon Composer workflow](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).
