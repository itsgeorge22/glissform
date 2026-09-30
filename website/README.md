# Glissform website

The website is a Vite, React, TypeScript, and SCSS project. Its desktop page follows the [Figma design](https://www.figma.com/design/IkSrf5xF80j0PeRMzPytZ8/Untitled?node-id=56-2717) and adds fixed Customisable, Private, and F.A.Q navigation. As soon as scrolling begins, the same navbar smoothly gains a translucent, blurred material and removes it again at the top. The selected link follows the linked section occupying the largest visible area; the brand returns to the top and clears the selection. Below 1156px, the site shows only the Glissform logo and a MacBook viewing message. The clickable feature cards switch between still previews every ten seconds, with a slim progress bar, smooth automatic and manual preview transitions, and matching hover, pressed, and keyboard-focus feedback. The Customisable grid has interactive blur choices, a starting-angle slider, and switches; timing values are illustrations. Broader website animations are deferred.

Run `npm ci` and `npm run dev` here to preview it, or `npm run build` to create `dist/`.

The public server serves `/var/www/glissform.app`. Publish `dist/assets/` before replacing `index.html`, so the new page never refers to files that are not yet available. Preserve the existing `downloads/` and `updates/` directories: they contain the public DMG and signed app update feed. Update the download URL in `src/App.tsx` only when a new public version and its DMG are available.

Inter is included as a local web font under its [SIL Open Font License](public/assets/inter-license.txt). This license applies to the font, not to the Glissform source repository.
