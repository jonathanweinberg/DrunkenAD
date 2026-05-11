# Issue 003: Parallels Live Harness Boundary Was Too Easy To Miss

Status: Closed - Fixed in v0.12.0

## Summary

The seeded live campaign harness was correctly isolated from the core module, but
the documentation made the Parallels dependency easier to infer than to see. The
host script defaulted to `WindowsServer2025_ADDNS`, used `prlctl`, and launched
guest work through `\\psf\DrunkenAD_CODEX`, while the main live-validation guide
mostly described those details through wrapper paths and shared-folder names.

## Evidence

- `README.md` and `docs/TESTING.md` mentioned the Parallels lab VM directly.
- `docs/LIVE-VALIDATION.md` described the wrapper lookup order and
  `DrunkenAD_CODEX` share but did not name Parallels, `prlctl`, or the default
  `WindowsServer2025_ADDNS` VM.
- `tests/Live/Invoke-DrunkenADLiveCampaign.ps1` is intentionally host-specific:
  it snapshots the VM with `prlctl`, ensures the Parallels shared folder, and
  writes ignored run output under `tests/Live/results/`.

## Desired Outcome

- Keep the seeded live campaign harness available for the existing Parallels lab.
- Make the host boundary explicit in the main live-validation reading path.
- Preserve the smaller integration suite as the generic live AD validation path.
- Keep `tests/Live/results/` documented as ignored local run output.
- Bump the release metadata to `0.12.0` for the documentation cleanup release.

## Fix Notes

- Updated `docs/LIVE-VALIDATION.md` to state that the seeded campaign harness is
  Parallels-specific, uses `prlctl`, defaults to `WindowsServer2025_ADDNS`, and
  expects the `\\psf\DrunkenAD_CODEX` guest share.
- Updated `README.md`, `docs/TESTING.md`, `docs/OPERATIONS.md`, and
  `docs/README.md` so the Parallels boundary and ignored results directory are
  visible from the main documentation paths.
- Updated `CHANGELOG.md`, `DrunkenAD/DrunkenAD.psd1`, release-readiness checks,
  and release unit tests for `0.12.0`.
- Added unit coverage that fails if `docs/LIVE-VALIDATION.md` stops naming the
  Parallels host dependency and ignored output boundary.

## Close Criteria

- The live-validation guide names the Parallels host dependency directly.
- Release metadata, changelog, and release-readiness tests agree on `0.12.0`.
- Local parser, docs, unit, and release checks pass.

Closed after the `v0.12.0` release-prep branch captured the issue record,
documentation cleanup, and version bump.
