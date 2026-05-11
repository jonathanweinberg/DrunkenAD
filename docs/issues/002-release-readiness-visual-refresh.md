# Issue 002: Release-Readiness Visuals Need 0.11.0 Context

Status: Open

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

- Pending.

## Commits

- Pending.

## Close Criteria

- Live validation docs and diagrams point readers to profile-aware validation.
- Release-readiness checks are visible in the documentation reading path.
- Updated image prompts are stored beside the generated assets.
- Local documentation and release checks pass.

Leave this issue open after the fix is committed unless the user explicitly
requests closure. It should be marked ready to close once validation passes.
