# Contributing to Glissform

Glissform is an early-stage macOS app for subtle animations and quality-of-life improvements. Seamless Close is its first feature; the product is designed to grow beyond it. The source repository and its issue tracker are private. No open-source license has been selected yet.

## Report an issue

Collaborators with repository access can use the [submission chooser](https://github.com/itsgeorge22/glissform/issues/new/choose) for a bug report, feature suggestion, or compatibility report. Search existing issues before submitting a duplicate; add useful details to an existing report when appropriate. A public contact method is still planned.

Include the affected feature, Mac model, macOS version, Glissform version, steps to reproduce, and expected versus actual behaviour. For Seamless Close, include the chosen start angle, external displays, full-screen apps, and whether the Mac slept. Remove private desktop content from any media you choose to share.

For Battery Ripple, distinguish the manual preview from connecting power, and mention any repeated or missing effect. The red 20% trigger and broader live interruption behavior still need physical confirmation.

## Propose a change

1. Keep the change focused and explain the user-visible problem.
2. Build with `bash scripts/build.sh`. This makes **Glissform Dev** in `build/Glissform Dev.app`, with a red icon, separate app identity, and no public updates. Use `--release` only when preparing a release candidate.
3. Run `bash scripts/test.sh` on a Mac with Metal; use `--motion-only` only when GPU testing is unavailable and say so.
4. Perform relevant checks in [docs/TESTING.md](docs/TESTING.md).
5. Review README.md, CHANGELOG.md, and ROADMAP.md. Update affected documents with the change; record completed work under Unreleased.
6. Describe checks performed and remaining limitations in the pull request.

Do not submit generated app bundles, screen captures, logs containing private information, credentials, or signing certificates. See [AGENTS.md](AGENTS.md) for project maintenance and release conventions.
