# Issue 006: Architecture Atlas Docs Release

Status: Fixed in v0.13.1

GitHub issue: https://github.com/jonathanweinberg/DrunkenAD/issues/6

## Summary

The documentation set needed a single browsable map of the module, data model,
operator workflows, validation gates, and release surfaces. The same cleanup
also clarified that local agent operating notes belong in an ignored workspace
area rather than public documentation.

## Evidence

- The docs already had several focused pages and static diagrams, but no single
  interactive map for understanding the whole repo at once.
- The architecture map data needed to be reusable by tools instead of living
  only inside one HTML artifact.
- Local GitHub CLI and connector setup details are useful to agents but should
  not be published in the repository documentation.

## Desired Outcome

- Add a self-contained interactive architecture atlas that works from a local
  file URL.
- Add an external-data atlas variant that loads reusable JSON map data.
- Link the atlas from the docs index.
- Add an ignored local Codex area for agent setup notes.
- Release the docs-only work as `v0.13.1`.

## Fix Notes

- Added `docs/drunkenad-architecture-map.html` as the self-contained atlas.
- Added `docs/drunkenad-architecture-map-external.html` as the external-data
  atlas variant.
- Added `docs/drunkenad-architecture-map.json` as reusable map data.
- Updated `docs/README.md` to link the atlas artifacts.
- Added `.codex-local/` to `.gitignore` and moved local agent notes there.
- Updated release metadata and changelog entries for `v0.13.1`.

## Validation

- `jq empty docs/drunkenad-architecture-map.json`
- `git diff --check`

CI was intentionally skipped for this docs-only release.

Follow-up release-integrity and atlas-validation hardening is tracked in
Issue 007.

## Commit Trail

- `b39b863` - `docs: add interactive architecture atlas`
- `421285d` - `docs: keep local agent notes ignored`
- Final release metadata commit - `chore: prepare v0.13.1 release`

## Release

Closed by the `v0.13.1` release:

https://github.com/jonathanweinberg/DrunkenAD/releases/tag/v0.13.1
