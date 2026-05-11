# Issue 001: Documentation Drift After Module Split

Status: Open

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

- Pending.

## Commits

- Pending.

## Close Criteria

- Documentation references the split module structure and release-readiness
  export contract.
- The new visual asset is checked into the repo and linked from relevant docs.
- Local documentation and release checks pass.

Leave this issue open after the fix is committed unless the user explicitly
requests closure. It should be marked ready to close once validation passes.
