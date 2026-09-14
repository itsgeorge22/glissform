# Contributing to Glissform

Glissform is an early alpha. Small, focused bug reports and proposed changes are useful; discuss major feature work before implementing it. No open-source license has been selected yet.

## Report an issue

Include your Mac model, macOS version, Glissform version, chosen start angle, steps to reproduce, and expected versus actual behavior. Mention external displays, full-screen apps, and whether the Mac slept. Remove private desktop content from any media you choose to share.

## Propose a change

1. Keep the change focused and explain the user-visible problem.
2. Build with `bash scripts/build.sh`.
3. Run `bash scripts/test.sh` on a Mac with Metal; use `--motion-only` only when GPU testing is unavailable and say so.
4. Perform relevant checks in [docs/TESTING.md](docs/TESTING.md).
5. Review README.md, CHANGELOG.md, and ROADMAP.md. Update affected documents with the change; record completed work under Unreleased.
6. Describe checks performed and remaining limitations in the pull request.

Do not submit generated app bundles, screen captures, logs containing private information, credentials, or signing certificates. See [AGENTS.md](AGENTS.md) for project maintenance and release conventions.
