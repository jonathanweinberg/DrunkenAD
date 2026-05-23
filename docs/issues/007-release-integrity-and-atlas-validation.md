# Issue 007: Release Integrity And Architecture Atlas Validation

Status: Fixed in v0.13.2

GitHub issue: https://github.com/jonathanweinberg/DrunkenAD/issues/7

## Summary

The `v0.13.1` release metadata advanced the manifest and changelog, but the
release-readiness gate and release unit tests still asserted `0.13.0`. The
interactive architecture atlas also had reusable JSON plus embedded HTML data,
but no repo-native gate proved that the two stayed synchronized or that flow and
file references remained valid.

## Evidence

- `pwsh -NoLogo -NoProfile -File ./scripts/Test-DrunkenADRelease.ps1` failed
  with `Expected module version 0.13.0 but found 0.13.1`.
- `scripts/Test-DrunkenADRelease.ps1` and `tests/Release.Unit.Tests.ps1`
  contained hardcoded `0.13.0` release assertions.
- `docs/drunkenad-architecture-map.json` and the self-contained HTML atlas
  duplicated map data without a dedicated validation script.

## Desired Outcome

- Derive release-readiness expectations from the module manifest version.
- Release the fix as `v0.13.2`.
- Add a PowerShell 5.1 compatible architecture-map validator.
- Run the validator from documentation hygiene so docs CI and release readiness
  catch atlas drift.
- Keep public module behavior unchanged.

## Fix Notes

- Updated `scripts/Test-DrunkenADRelease.ps1` to derive `$releaseVersion` from
  `Test-ModuleManifest`.
- Expanded release unit tests to cover dynamic release-version checks, `v0.13.2`
  metadata, changelog coverage, and architecture-map validation wiring.
- Added `scripts/Test-DrunkenADArchitectureMap.ps1` to validate required map
  fields, unique IDs, legend kind consistency, flow node references,
  repo-relative file references, manifest-version parity, and embedded HTML data
  parity.
- Wired the architecture-map validator into `scripts/Test-DrunkenADDocs.ps1`.
- Bumped manifest, changelog, and architecture-map data to `0.13.2`.
- Updated Issue 006 to remove stale planned-release and pending-validation
  wording.

## Validation

- Red proof before implementation:
  `pwsh -NoLogo -NoProfile -File ./scripts/Test-DrunkenADRelease.ps1` failed
  with the stale `0.13.0` version expectation.
- Red proof after writing release/atlas contract tests:
  `pwsh -NoLogo -NoProfile -File ./tests/Invoke-DrunkenADTests.ps1 -Output Detailed`
  failed with five release-readiness failures.
- Green proof after implementation:
  `pwsh -NoLogo -NoProfile -File ./scripts/Test-DrunkenADArchitectureMap.ps1`
  passed.
- Green proof after docs wiring:
  `pwsh -NoLogo -NoProfile -File ./scripts/Test-DrunkenADDocs.ps1` passed.
- Green proof for the test suite:
  `pwsh -NoLogo -NoProfile -File ./tests/Invoke-DrunkenADTests.ps1 -Output Detailed`
  passed with 66 tests, 0 failures.

## Commit Trail

- `a64203c` - `test: validate release integrity and atlas data`
- Documentation issue record commit - records Issue 007 and cleans up stale
  Issue 006 release wording.

## Close Criteria

- Local release-readiness gate passes without hardcoded current-version
  assertions.
- Atlas validation is part of documentation hygiene.
- Local release metadata, changelog, and atlas version all agree on `0.13.2`.
- GitHub issue comments record the implementation commits and final validation.

The GitHub issue should remain open for review until explicitly closed.
