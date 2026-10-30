# Glissform project guidance

## Scope and product

- The product name is Glissform: a macOS app focused exclusively on Seamless Close.
- Improve Seamless Close's animation, controls, setup and reliability. Do not propose or add separate experiences without a new explicit product decision from the owner.
- Do not announce specific future experiences before the owner approves their disclosure. Keep unimplemented ideas clearly separate from current capabilities.
- VERSION is the source for the current release; the first public version was 0.1.0-alpha.1.
- Preserve menu bar access, Seamless Close’s one-screenshot-per-gesture model, normal system sleep, and privacy behaviour unless the user explicitly changes the scope.
- Do not add continuous recording, networking, analytics, wake guarantees, or broad hardware claims implicitly.
- The source repository is public, and no open-source license has been selected. Do not add a license without the owner's choice.

## Design consistency

- Treat a change to a shared visual rule as a change to the whole affected surface. Inspect peer components and update them consistently rather than changing only the first matching component.
- Preserve previously agreed spacing, radius, typography, and color rules through later UI refinements. In the Settings detail area, all cards share one outer radius and all card icon tiles share one inner radius. Follow explicitly requested radius and padding values when they supersede an earlier proportional rule.

## Documentation is part of every change

For every project task, review README.md, CHANGELOG.md, and ROADMAP.md alongside the code:

- README.md describes current behavior, setup, support, permissions, and limitations. Update it when these change.
- CHANGELOG.md records completed user-visible work under Unreleased. Do not retroactively rewrite release history to describe later behavior.
- ROADMAP.md describes upcoming work and readiness gates. Mark completed items and revise plans when priorities change. Keep speculative ideas distinct from commitments.
- If one of the three does not need a change, leave it accurate rather than adding filler. Note the review in the change summary or PR checklist.
- Keep documentation updates in the same commit/PR as the corresponding behavior changes. This is a workflow obligation, not a scheduled background monitor.

## Keep GitHub information accurate

As part of each relevant feature, fix, compatibility finding, product decision, or release, review the affected public information before calling the work complete:

- Keep README.md a concise visitor-facing overview. Keep its product description, current features, development/download status, requirements, tested hardware, privacy claims, and feedback links accurate. Keep detailed behaviour in docs/APP_GUIDE.md and update both when shared facts change.
- Cross-check version claims against VERSION, the corresponding tag, CHANGELOG.md, and actual published GitHub Releases and assets. Clearly distinguish unreleased main-branch work, source-only prereleases, and downloadable app releases. Do not imply a `.dmg` exists until it is published.
- Review the GitHub About description, website URL, and topics when positioning, availability, or the relevant technology changes. Describe Glissform's focus on Seamless Close. Use only relevant topics and real, working destination links.
- Keep CONTRIBUTING.md, the issue chooser, bug/feature/compatibility forms, and pull-request template aligned with current features and support needs. Private GitHub forms are for collaborators only; do not present them as public feedback links. Ask only for useful information and never request serial numbers or credentials.
- Track actionable bugs and unresolved work in GitHub Issues, not in README bug or limitations lists. Label the README issue-tracker link as private until a public feedback channel exists; record inherent behaviour and compatibility boundaries in the relevant guide or requirements section. Search existing issues before creating a report, link roadmap work to its issue, and do not create speculative or duplicate issues merely to suggest activity.
- Write issues in a clean, concise, professional style: state the problem directly and add expected behaviour when useful. Do not use third-person attribution such as "the owner reported" for issues submitted on the owner's behalf. Include reproduction steps or environment details only when known and necessary; avoid speculative steps, filler sections, and lengthy investigation checklists.
- Keep known issues and roadmap completion status aligned with verified results. Distinguish owner testing, community reports, and automated checks; do not turn a single successful configuration into a broad compatibility claim. Preserve historical release notes rather than adding later behaviour to earlier versions.
- Validate changed Markdown links and issue-form YAML locally. After authorized publication, verify affected GitHub pages, forms, metadata, and release assets live. Repository metadata is separate from tracked files: a Git push alone does not update the About description or topics.
- Include a brief accuracy-review result in the completion summary: what changed, what remained accurate, and anything still local, unpublished, inaccessible, or unverified. If live updates are outside the current authorization, prepare the exact changes and report them as pending; do not claim GitHub is updated.

This checklist is part of normal project work, not a background automation. It does not authorize unrelated edits, announcements, or publication, and does not require filler changes to documents that remain accurate.

## Versions and releases

- VERSION is the public version source; BUILD_NUMBER is a monotonically increasing numeric app build number.
- scripts/build.sh derives the numeric bundle short version and full GlissformVersion from VERSION.
- Increment the public version only for an intended release. Keep unreleased work in the changelog until then.
- Tags are v<VERSION>. Never move an existing public release tag.
- An authorized version release includes a GitHub Release page for its exact tag, with version-specific notes based on the corresponding changelog entry. Mark alpha, beta, and release-candidate versions as prereleases. A pushed tag alone is not a completed GitHub Release; if the user requests tags only, report that distinction explicitly.
- Before reporting a release complete, verify its published GitHub page, tag and target commit, notes, prerelease status, and any intended downloadable assets. Report missing steps or blockers rather than claiming completion.
- Missing release pages may be added later to existing tags without moving those tags or changing their code. Publish backfilled pages only when authorized, describe only that version's changes, and clearly identify source-only releases without implying an app installer is available.
- Public app download links and installation instructions belong on GitHub only once the intended `.dmg` is ready and published. Source tags and release notes do not establish app-download availability.
- Do not publish future commits, tags, or releases without authorization for that publication task.

## Verification

- For documentation or workflow-only changes, check the affected text, links, and formatting; do not build or run app tests.
- For small UI copy, icon, or layout changes without behavior changes, run `bash scripts/build.sh` once after the final edit. Do not run the regression suite or inspect every page: the owner can review the visible result. Use at most a targeted visual check when needed to catch a concrete visibility or clipping risk, or when the owner asks. Broader visual review and tests belong to interaction, state, or behavior changes.
- For motion, sensor, capture, gesture, sleep/wake, permission, settings-logic, or app-lifecycle changes, run relevant focused checks while working. After the implementation is final, run `bash scripts/build.sh` and `bash scripts/test.sh` once. Avoid repeating the full suite after each small adjustment.
- Before a release, run the full build and test suite on the intended release build and complete the relevant physical checks. Automated checks do not replace lid, sleep, or wake validation on the development Mac.
- Summarize successful checks briefly; inspect and report detailed output when a check fails. Keep generated test output out of Git.
- CI uses --motion-only because hosted runners are not hardware/GPU acceptance tests. Never describe CI as physical lid verification.
- Test snapshot cancellation and cleanup on reversal, sleep, display changes, and quit when changing lifecycle behavior.
- Keep screenshots, generated binaries, logs, caches, signing material, and credentials out of Git.
- Document concrete limitations rather than claiming perfect smoothness, invisible capture, or untested compatibility.
