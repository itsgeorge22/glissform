# Glissform website

The website is a Vite, React, TypeScript, and SCSS project. Its desktop page follows the [Figma design](https://www.figma.com/design/IkSrf5xF80j0PeRMzPytZ8/Untitled?node-id=56-2717). Below 1156px, it shows only the Glissform logo and a MacBook viewing message. The clickable feature cards switch between still previews every five seconds, with a filling tint showing progress through the interval. Broader website animations are deferred.

Run `npm ci` and `npm run dev` here to preview it, or `npm run build` to create `dist/`.

The public server serves `/var/www/glissform.app`. Publish `dist/assets/` before replacing `index.html`, so the new page never refers to files that are not yet available. Preserve the existing `downloads/` and `updates/` directories: they contain the public DMG and signed app update feed. Update the download URL in `src/App.tsx` only when a new public version and its DMG are available.

Inter is included as a local web font under its [SIL Open Font License](public/assets/inter-license.txt). This license applies to the font, not to the Glissform source repository.
