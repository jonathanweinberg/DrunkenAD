# Documentation Suite 2026-05-11 Image Prompts

These images were generated with image-gen2 to extend the existing DrunkenAD
documentation-suite style established during the 0.11.0 module split. The Mermaid files in
`docs/diagrams/` remain the editable diagram source of truth. These PNG files
are page-facing infographic plates with labels, sample values, and workflow
context.

The 2026-07-16 safety refresh rendered the module, campaign, and release plates
deterministically from these semantic requirements so version, trust-boundary,
and verification-status text remains exact.

Unless otherwise noted, these generated documentation images are project
documentation assets covered by the repository's BSD 3-Clause License.

## module-layout.png

The final asset is an edited version of the first generated module-layout plate.
The edit tightened the dashed connector from `Private helpers` so the arrowhead
lands directly on the left edge of the `DrunkenAD.psd1` card.

```text
Create a polished technical documentation infographic in a clean white, navy, teal, amber, and green palette. Title exactly: "DrunkenAD Module Layout". Subtitle exactly: "Focused internals, stable 12-command compatibility surface". Overall style should match the previous DrunkenAD generated plates: crisp white background, navy header bars, teal accents, amber highlights, realistic UI cards, readable technical labels, thin connector arrows, no mascots, no fake logos, no fantasy. Center top has a root module card labeled "DrunkenAD.psm1" with short text "deterministic dot-source loader". To the left, a stacked folder panel labeled "Private helpers" containing exact file labels: Core.ps1, PrefixMap.ps1, ProjectionMap.ps1, CsvMapping.ps1, SchemaStatus.ps1. To the right, group the public surface into exact short labels: Get / Set / Remove, CSV import + split, Projection + demo, Prefixed compatibility, Schema readiness, Legacy updater. State exactly "12 exported commands". Bottom center has a manifest card labeled "DrunkenAD.psd1" with "FunctionsToExport parity", "ModuleVersion 0.13.2", and "PowerShell 5.1". Bottom right has a source gate card with checks: syntax, docs, architecture atlas, trusted Pester 5.7.1, exported commands, manifest metadata. Bottom strip: Maintainable, Importable, PS 5.1, Source-gated, CI matrix. Do not claim a release was published or remotely proven.
```

## live-campaign-profiles.png

```text
Create a polished technical documentation infographic in a clean white, navy, teal, amber, and green palette. Title exactly: "Live Campaign Profiles". Subtitle exactly: "Choose scale only after proving the mutation boundary". Style must match the previous DrunkenAD documentation plates: crisp white background, navy title, teal connector lines, amber highlights, green pass states, realistic UI cards, readable labels, no mascots, no fake logos, no fantasy. Top row is a three-card segmented control with exact profile labels and counts: "Quick" with "30 seed users" and "3 CRUD samples per region"; "Standard" with "300 seed users" and "10 CRUD samples per region"; "Full" with "3,000 seed users" and "100 CRUD samples per region" plus a small tag "default". Middle workflow must show: Rollback evidence + confirmation; Run-specific inputs + SHA-256; Exact manifest/CSV identity set; Bounded campaign root; CSV + projection + CRUD; campaign-summary.json + operator notes. Include a prominent fail-closed callout: "Unexpected root user: stop; never prune or adopt". Put a small command panel showing exact command text: "-CampaignProfile Quick" and "Full remains default". Right side evidence card titled "Profile-derived totals" listing: Quick 30 / 9 CRUD, Standard 300 / 30 CRUD, Full 3000 / 300 CRUD. Bottom strip: Fast sanity, Broader coverage, Seeded scale, Snapshot-backed, Ignored run output. Do not invent a fourth profile or imply a live run has occurred.
```

## release-readiness.png

```text
Create a polished technical documentation infographic in a clean white, navy, teal, amber, and green palette. Title exactly: "0.13.2 Release Readiness". Subtitle exactly: "Local source gate passed; remote CI and review remain". Style must match the previous DrunkenAD documentation plates: crisp white background, navy title, teal connector lines, amber highlights, green checks, realistic UI cards, readable labels, no mascots, no fake logos, no fantasy. Center has a release gate dashboard titled "scripts/Test-DrunkenADRelease.ps1" with exact checks: Manifest metadata, Clean import, Export parity, PowerShell syntax, Documentation hygiene, Architecture atlas, Trusted Pester 5.7.1, Explicit six-file test allowlist. Show local result exactly: "100 discovered; 94 passed; 6 integration not run; 0 failed". Add a trust-boundary card: "Never import or discover tests from tests/Live/results". Left column titled "Inputs" with cards: DrunkenAD.psd1, DrunkenAD.psm1, Public commands, Private helpers, docs, tests. Right column titled "Remote CI matrix" with cards: Ubuntu pwsh, macOS pwsh, Windows pwsh, Windows PowerShell 5.1, no PSGallery publish. Bottom strip: Metadata, Importability, Syntax, Docs + atlas, Trusted tests, No publish credentials. Do not claim remote CI passed, the branch merged, a tag exists, or the module was published.
```
