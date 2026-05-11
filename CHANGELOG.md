# Changelog

## 0.12.1

- Replaced host-specific live campaign wording with generic host-method
  guidance for future seeded campaign implementations.
- Added a host-method contract page that describes rollback, workspace,
  result-collection, credential, and operator-note responsibilities without
  naming a specific virtualization or remote-execution method.
- Updated issue records, release metadata, and release-readiness checks for the
  corrective documentation release.

## 0.12.0

- Superseded by `0.12.1`. The first live-campaign documentation cleanup made one
  host method too prominent; the corrective release keeps the public docs generic
  while preserving the checked-in live campaign scripts.

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
