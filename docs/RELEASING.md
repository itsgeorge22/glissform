# Releases and distribution

Active development is paused. The current release is 0.1.0 (build 21). Existing release tags and assets remain immutable.

Installers and checksums are public GitHub Release assets. Vercel serves the website at `https://glissform.itsgeorge.pro/` and retains the exact signed legacy feed at `https://glissform.app/updates/appcast.xml`. Existing `/downloads/` addresses redirect to their corresponding GitHub assets. The website source and hosting instructions are maintained in the separate private website repository.

## Existing installations

Keep the feed byte-for-byte intact: Sparkle verifies a signature over the feed as well as the downloaded installer. Preserve `config/sparkle-public-key.txt` and keep the private signing key out of source control. Hosting changes do not remove the app's macOS first-launch warning; 0.1.0 remains unnotarized.

## If development resumes

A new release requires separate authorization, an increasing VERSION and BUILD_NUMBER, version-specific changelog notes, the established build and test suite, and relevant physical checks. Publish its signed DMG and checksum to the exact GitHub tag, preserving prerelease status. Verify public asset bytes and signatures before updating the feed.

Add the new version's download redirects to the website, sign the updated appcast with the existing Sparkle key, then deploy it through Pages. Verify the public feed signature, download checksum, and both installed-app update modes. Do not overwrite existing release assets or move tags.

The former automatic tag-to-VPS release workflow is retired. Its [archived workflow](archive/release-vps-workflow.yml) and [former procedure](archive/RELEASING_VPS.md) are historical reference only and must not be re-enabled unchanged. No workflow currently publishes a new release automatically.
