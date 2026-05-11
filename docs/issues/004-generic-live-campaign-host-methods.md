# Issue 004: Live Campaign Docs Need Generic Host-Method Guidance

Status: Closed - Fixed in v0.12.1

## Summary

The seeded live campaign needs documentation that describes the responsibilities
of any host method without blessing one implementation as the project default.
The current scripts can stay as working lab automation, but the public docs
should prepare operators for future methods that may use different rollback,
workspace transfer, execution, and collection mechanisms.

## Evidence

- Operators need to understand the seeded campaign contract before adapting it to
  another lab.
- The live-validation docs already separate the smaller integration suite from
  the larger seeded campaign, but the host responsibilities were spread across
  README, testing, operations, and script-specific details.
- The release gate did not previously protect public docs from drifting toward a
  single host method.

## Desired Outcome

- Add a method-neutral host contract for seeded live campaigns.
- Link that contract from the README, docs index, testing guide, live-validation
  guide, and operations runbook.
- Keep `tests/Live/results/` documented as ignored local run output.
- Update release metadata and release-readiness checks for `0.12.1`.
- Add regression coverage that rejects specific host-method vocabulary in public
  docs and issue records.

## Fix Notes

- Added `docs/LIVE-CAMPAIGN-HOSTS.md` with host wrapper responsibilities,
  rollback expectations, workspace setup, result collection, credential handling,
  operator notes, and future-method guidance.
- Reworked public live campaign docs to describe host wrappers, rollback points,
  workspaces, and report collection generically.
- Rewrote Issue 003 as a superseded note and recorded this corrective issue as
  the `0.12.1` closeout.
- Updated `CHANGELOG.md`, `DrunkenAD/DrunkenAD.psd1`, release-readiness checks,
  and release unit tests for `0.12.1`.
- Added tests that keep the public docs and issue notes host-method neutral.

## Close Criteria

- Public docs do not name a specific host implementation.
- The generic host-method contract is linked from the main reading paths.
- Local documentation and release checks pass.

Closed by the `v0.12.1` release.
