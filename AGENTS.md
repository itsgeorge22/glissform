# Glissform project guidance

## Scope and product

- The product name is Glissform: a macOS app for subtle animations and quality-of-life improvements across everyday gestures and system changes.
- Infinite Screen is the first available feature. Never describe Glissform itself as only a lid-closing or screen-animation app; distinguish the broader product direction from implemented features.
- Do not announce specific future experiences before the owner approves their disclosure. Keep unimplemented ideas clearly separate from current capabilities.
- VERSION is the source for the current release; the first public version was 0.1.0-alpha.1.
- Preserve menu bar access, Infinite Screen’s one-screenshot-per-gesture model, normal system sleep, and privacy behaviour unless the user explicitly changes the scope.
- Do not add continuous recording, networking, analytics, wake guarantees, or broad hardware claims implicitly.
- The source is public, but no open-source license has been selected. Do not add a license without the owner's choice.

## Documentation is part of every change

For every project task, review README.md, CHANGELOG.md, and ROADMAP.md alongside the code:

- README.md describes current behavior, setup, support, permissions, and limitations. Update it when these change.
- CHANGELOG.md records completed user-visible work under Unreleased. Do not retroactively rewrite release history to describe later behavior.
- ROADMAP.md describes upcoming work and readiness gates. Mark completed items and revise plans when priorities change. Keep speculative ideas distinct from commitments.
- If one of the three does not need a change, leave it accurate rather than adding filler. Note the review in the change summary or PR checklist.
- Keep documentation updates in the same commit/PR as the corresponding behavior changes. This is a workflow obligation, not a scheduled background monitor.

## Versions and releases

- VERSION is the public version source; BUILD_NUMBER is a monotonically increasing numeric app build number.
- scripts/build.sh derives the numeric bundle short version and full GlissformVersion from VERSION.
- Increment the public version only for an intended release. Keep unreleased work in the changelog until then.
- Tags are v<VERSION>. Never move an existing public release tag.
- Do not publish future commits, tags, or releases without authorization for that publication task.

## Verification

- Run bash scripts/build.sh and bash scripts/test.sh for app changes.
- CI uses --motion-only because hosted runners are not hardware/GPU acceptance tests. Never describe CI as physical lid verification.
- Test snapshot cancellation and cleanup on reversal, sleep, display changes, and quit when changing lifecycle behavior.
- Keep screenshots, generated binaries, logs, caches, signing material, and credentials out of Git.
- Document concrete limitations rather than claiming perfect smoothness, invisible capture, or untested compatibility.
