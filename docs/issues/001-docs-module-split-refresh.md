# Issue 001: Documentation Drift After Module Split

Status: Closed - Fixed in v0.11.0

## Summary

The 0.11.0 module split moved implementation from a monolithic
`DrunkenAD/DrunkenAD.psm1` into focused `DrunkenAD/Private` and
`DrunkenAD/Public` files, but the documentation and image set still largely
present the project as a single module surface plus feature workflows.

## Evidence

- `README.md` lists the new folders but the primary overview image and reading
  path do not explain the source layout or export contract.
- `docs/ARCHITECTURE.md` describes the split in prose, but there is no
  dedicated visual for maintainers showing deterministic root-module loading,
  private helper ownership, public command files, and manifest/export parity.
- `docs/DIAGRAMS.md` only indexes the original workflow plates from
  `docs/images/documentation-suite-2026-05-07/`.

## Desired Outcome

- Add documentation that makes the 0.11.0 source layout easy to understand.
- Add a generated visual plate in the same style as the existing image-gen2
  documentation suite.
- Preserve the existing Mermaid diagrams as editable source of truth.
- Keep the public command surface unchanged in the docs.

## Fix Notes

- Added `docs/images/documentation-suite-2026-05-11/module-layout.png`, a
  generated image-gen2 plate that shows the split `Private` and `Public`
  source folders, the root `DrunkenAD.psm1` loader, `DrunkenAD.psd1` export
  parity, and the release-readiness gate.
- Tightened the dashed connector from `Private helpers` so the arrowhead lands
  directly on the `DrunkenAD.psd1` card instead of pointing into whitespace.
- Added `docs/diagrams/module-layout.mmd` as the editable Mermaid source for
  the module-layout concept.
- Updated `README.md`, `docs/README.md`, `docs/ARCHITECTURE.md`, and
  `docs/DIAGRAMS.md` so the module split is part of the main documentation
  path.
- Updated `docs/DATA-STORE.md` command links to point at the new public source
  files under `DrunkenAD/Public`.
- Captured the image-gen2 prompt and edit note in
  `docs/images/documentation-suite-2026-05-11/image-prompts.md`.
- Validation passed:
  - `pwsh -NoLogo -NoProfile -File scripts/Test-DrunkenADDocs.ps1`
  - `pwsh -NoLogo -NoProfile -File scripts/Test-DrunkenADSyntax.ps1`
  - `pwsh -NoLogo -NoProfile -File scripts/Test-DrunkenADRelease.ps1`

## Commits

- Opened issue record: `f375dfa`
- Fix commit: `d10e097`

## Close Criteria

- Documentation references the split module structure and release-readiness
  export contract.
- The new visual asset is checked into the repo and linked from relevant docs.
- Local documentation and release checks pass.

Closed after the `v0.11.0` GitHub Release was created:
https://github.com/jonathanweinberg/DrunkenAD/releases/tag/v0.11.0
