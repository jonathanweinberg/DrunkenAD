# Documentation Suite 2026-05-11 Image Prompts

These images were generated with image-gen2 to extend the existing DrunkenAD
documentation-suite style after the 0.11.0 module split. The Mermaid files in
`docs/diagrams/` remain the editable diagram source of truth. These PNG files
are page-facing infographic plates with labels, sample values, and workflow
context.

Unless otherwise noted, these generated documentation images are project
documentation assets covered by the repository's BSD 3-Clause License.

## module-layout.png

The final asset is an edited version of the first generated module-layout plate.
The edit tightened the dashed connector from `Private helpers` so the arrowhead
lands directly on the left edge of the `DrunkenAD.psd1` card.

```text
Create a polished technical documentation infographic in a clean white, navy, teal, and amber palette. Title exactly: "DrunkenAD Module Layout". Subtitle exactly: "Focused source files, unchanged exported commands". Overall style should match the previous DrunkenAD generated plates: crisp white background, navy header bars, teal accents, amber highlights, realistic UI cards, readable technical labels, thin connector arrows, no mascots, no fake logos, no fantasy. Center top has a root module card labeled "DrunkenAD.psm1" with short text "deterministic dot-source loader". To the left, a stacked folder panel labeled "Private helpers" containing exact file labels: Core.ps1, PrefixMap.ps1, ProjectionMap.ps1, CsvMapping.ps1, SchemaStatus.ps1. To the right, a stacked folder panel labeled "Public commands" containing exact command labels: Get-ADUserDrinkData, Set-ADUserDrinkData, Remove-ADUserDrinkData, Import-ADUserDrinkCsvData, Set-ADUserDrinkProjection, Test-ADDrinkAttributeReadyForUserWrite. Bottom center has a manifest card labeled "DrunkenAD.psd1" with "FunctionsToExport parity" and "ModuleVersion 0.11.0". Bottom right has a release gate card labeled "Release readiness" with checks: syntax, docs, unit tests, exported commands, manifest metadata. Bottom strip: Maintainable, Importable, Compatible, Release-ready, CI-gated. Keep labels short and legible, use exact filenames and command names above, do not invent additional command names, do not render tiny paragraphs.
```

## live-campaign-profiles.png

```text
Create a polished technical documentation infographic in a clean white, navy, teal, amber, and green palette. Title exactly: "Live Campaign Profiles". Subtitle exactly: "Choose validation scale before touching real AD data". Style must match the previous DrunkenAD documentation plates: crisp white background, navy title, teal connector lines, amber highlights, green pass states, realistic UI cards, readable labels, no mascots, no fake logos, no fantasy. Top row is a three-card segmented control with exact profile labels and counts: "Quick" with "30 seed users" and "3 CRUD samples per region"; "Standard" with "300 seed users" and "10 CRUD samples per region"; "Full" with "3,000 seed users" and "100 CRUD samples per region" plus a small tag "default". Middle row is a ladder with exact step labels: Snapshot, Parser gate, Unit tests, Integration tests, Seed reconcile, CSV ingestion, Projection, CRUD validation, campaign-summary.json. Put a small command panel showing exact command text: "-CampaignProfile Quick" and "Full remains default". Right side evidence card titled "Profile-derived totals" listing: Quick 30 / 9 CRUD, Standard 300 / 30 CRUD, Full 3000 / 300 CRUD. Bottom strip: Fast sanity, Broader coverage, Seeded scale, Snapshot-backed, Ignored results. Keep all labels short and legible, do not invent a fourth profile, do not show publish or PSGallery automation, do not imply Full is no longer the default.
```

## release-readiness.png

```text
Create a polished technical documentation infographic in a clean white, navy, teal, amber, and green palette. Title exactly: "0.11.0 Release Readiness". Subtitle exactly: "Stabilize the module before publishing". Style must match the previous DrunkenAD documentation plates: crisp white background, navy title, teal connector lines, amber highlights, green checks, realistic UI cards, readable labels, no mascots, no fake logos, no fantasy. Center has a release gate dashboard titled "scripts/Test-DrunkenADRelease.ps1" with six check tiles: Manifest metadata, Import clean session, Exported command parity, PowerShell syntax, Documentation hygiene, Unit tests. Left column titled "Inputs" with cards: DrunkenAD.psd1, DrunkenAD.psm1, Public commands, Private helpers, docs, tests. Right column titled "CI acceptance" with cards: Ubuntu, macOS, Windows, no PSGallery publish. Bottom left has a changelog card labeled "CHANGELOG.md" with "0.11.0 release-readiness notes". Bottom right has a manifest card labeled "ProjectUri" and "ReleaseNotes". Bottom strip: Metadata, Importability, Syntax, Docs, Tests, No publish credentials. Keep labels short and legible, do not claim the module was published, do not include secrets or credentials, do not invent commands other than scripts/Test-DrunkenADRelease.ps1.
```
