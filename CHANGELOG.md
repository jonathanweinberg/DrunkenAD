# Changelog

## 0.12.0

- Clarified that the seeded live campaign harness is a Parallels Desktop
  operator workflow built around `prlctl`, `WindowsServer2025_ADDNS`, and the
  `\\psf\DrunkenAD_CODEX` guest share.
- Added a tracked issue note for the Parallels live-harness documentation
  cleanup.
- Kept the release-readiness gate current with the `0.12.0` manifest metadata.

## 0.11.0

- Split the module into focused `Private` and `Public` source files while preserving the exported command surface.
- Added `Quick`, `Standard`, and `Full` live validation campaign profiles.
- Added release-readiness validation for manifest metadata, importability, exports, syntax, docs, and tests.
- Expanded opt-in integration coverage for CSV ingestion and projection workflows.
- Added image-gen2 documentation plates for the module layout, campaign profiles, and release-readiness gate.

## 0.10.1

- Surfaced `Split-DrunkenADCsvField` as a public helper for CSV multivalue splitting.
- Documented `SplitOn` CSV ingestion behavior and added example coverage.
- Registered PSGallery in CI when missing before installing the pinned Pester version.
