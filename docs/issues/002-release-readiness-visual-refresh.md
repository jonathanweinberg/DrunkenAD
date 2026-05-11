# Issue 002: Release-Readiness Visuals Need 0.11.0 Context

Status: Closed - Fixed in v0.11.0

## Summary

The documentation image set predates the 0.11.0 release-readiness changes. It
does not show the new Quick, Standard, and Full live campaign profiles, the
release-readiness script, or the CI release gate added for this stabilization
milestone.

## Evidence

- `docs/images/documentation-suite-2026-05-07/live-validation-ladder.png`
  presents a single full-scale campaign evidence panel with 3,000 seed users.
- `docs/LIVE-VALIDATION.md` now documents selectable `-CampaignProfile`
  values, but the main visual path still emphasizes only the full campaign.
- `docs/TESTING.md` mentions `scripts/Test-DrunkenADRelease.ps1`, but the
  visual suite has no release-readiness plate.

## Desired Outcome

- Refresh the visual documentation path so it includes campaign profiles and
  the release-readiness gate.
- Keep Full as the default behavior in prose and examples.
- Make Quick the recommended first operator pass after code changes.
- Capture the updated image prompts for future regeneration.

## Fix Notes

- Added `docs/images/documentation-suite-2026-05-11/live-campaign-profiles.png`
  to show Quick, Standard, and Full campaign scale in the documentation visual
  path while preserving Full as the default.
- Added `docs/images/documentation-suite-2026-05-11/release-readiness.png` to
  make `scripts/Test-DrunkenADRelease.ps1`, manifest metadata, importability,
  exported command parity, docs, syntax, and unit tests visible to release
  reviewers.
- Added editable Mermaid sources:
  - `docs/diagrams/live-campaign-profiles.mmd`
  - `docs/diagrams/release-readiness-flow.mmd`
- Updated `README.md`, `docs/README.md`, `docs/LIVE-VALIDATION.md`,
  `docs/OPERATIONS.md`, `docs/TESTING.md`, and `docs/DIAGRAMS.md` to link the
  new image-gen2 plates from the main reading paths.
- Added the image-gen2 prompt record under
  `docs/images/documentation-suite-2026-05-11/image-prompts.md`.
- Updated `CHANGELOG.md` so the 0.11.0 notes mention the refreshed
  documentation plates.
- Validation passed:
  - `pwsh -NoLogo -NoProfile -File scripts/Test-DrunkenADDocs.ps1`
  - `pwsh -NoLogo -NoProfile -File scripts/Test-DrunkenADSyntax.ps1`
  - `pwsh -NoLogo -NoProfile -File scripts/Test-DrunkenADRelease.ps1`

## Commits

- Opened issue record: `f375dfa`
- Fix commit: `d10e097`

## Close Criteria

- Live validation docs and diagrams point readers to profile-aware validation.
- Release-readiness checks are visible in the documentation reading path.
- Updated image prompts are stored beside the generated assets.
- Local documentation and release checks pass.

Closed after the `v0.11.0` GitHub Release was created:
https://github.com/jonathanweinberg/DrunkenAD/releases/tag/v0.11.0
