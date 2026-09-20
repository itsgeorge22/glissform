# Contributing to Glissform

Glissform is an early-alpha macOS app for subtle animations and quality-of-life improvements. Infinite Screen is its first feature; the product is designed to grow beyond it. Small, focused bug reports and proposed changes are useful; discuss major feature work before implementing it. No open-source license has been selected yet.

## Report an issue

Include the affected feature, Mac model, macOS version, Glissform version, steps to reproduce, and expected versus actual behaviour. For Infinite Screen, include the chosen start angle, external displays, full-screen apps, and whether the Mac slept. Remove private desktop content from any media you choose to share.

## Propose a change

1. Keep the change focused and explain the user-visible problem.
2. Build with `bash scripts/build.sh`.
3. Run `bash scripts/test.sh` on a Mac with Metal; use `--motion-only` only when GPU testing is unavailable and say so.
4. Perform relevant checks in [docs/TESTING.md](docs/TESTING.md).
5. Review README.md, CHANGELOG.md, and ROADMAP.md. Update affected documents with the change; record completed work under Unreleased.
6. Describe checks performed and remaining limitations in the pull request.

Do not submit generated app bundles, screen captures, logs containing private information, credentials, or signing certificates. See [AGENTS.md](AGENTS.md) for project maintenance and release conventions.
