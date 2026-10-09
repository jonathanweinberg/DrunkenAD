# release-readiness

- Tool mode: built-in image_gen (image_gen.imagegen); reference-guided raster generation.
- Date: 2026-10-08.
- Use case: infographic-diagram.
- Attempts: 1. No fallback, CLI generation, or post-generation image editing.
- Reference image: `v0.13.1:docs/images/documentation-suite-2026-05-11/release-readiness.png`
- Reference role: original visual style; historical text and results are not current evidence.
- Workspace output: `docs/images/documentation-suite-2026-10-08/release-readiness.png`
- Tool arguments: referenced_image_paths contains the reference above; transparent_background=false; prompt is reproduced verbatim below.
- Export: byte-for-byte copy of the native generated PNG; historical assets unchanged.
- Inspection: Verified title, subtitle, five gate categories, script path, four CI lanes, and separate live/publish boundaries. No version-readiness, test-count, live-pass, publication, or allowlist-count claims.

## Current Sources Consulted

- scripts/Test-DrunkenADRelease.ps1
- tests/Release.Unit.Tests.ps1
- .github/workflows/powershell-ci.yml
- docs/diagrams/release-readiness-flow.mmd

The owner approved the illustrated-style refresh. Technical labels were checked
against the sources above. Image generation establishes no test or CI result.

## Exact Prompt

```text
Use case: infographic-diagram.
Asset type: DrunkenAD technical documentation illustration, a refreshed sibling of the supplied original.
Input image 1: original release-readiness.png, visual-style reference only; replace its dated content, never copy its version, results or readiness claims.
Create one polished 3:2 landscape bitmap infographic, ideally 1536 x 1024. Match the original's rich professional technical illustration: crisp white background, bold navy heading, teal fine connectors, amber approval accents, green accents only on neutral icon details. Beautiful dimensional document, terminal, book/atlas, shield, test clipboard, platform and operator icons with restrained shading and clean outlines. Retain the original visual density and craftsmanship but use fewer, larger labels. An illustrated understandable human/operator flow, not flat text cards or a text-only slide. Clear generous spacing, text legible at full size, no overlaps.
Exact title: "Release Readiness"
Exact subtitle: "Source checks, live evidence, explicit approval"
Composition: source documents and module/file icons at left feed a central illustrated source gate; at right, four clear CI platform lanes. Along bottom, TWO SEPARATE approval boundaries, each with its own appropriate illustration: isolated directory server + operator permission for live AD, and a locked publication package + operator approval for publishing. Neither boundary is an automatic continuation or a completed result.
The source gate heading must be exactly "scripts/Test-DrunkenADRelease.ps1". Beneath it show FIVE equally readable illustrated check categories, exactly:
"Manifest + FileList"
"Import + exports"
"Syntax"
"Docs + atlas"
"Trusted Pester 5.7.1"
Use neutral checklist/inspection symbols, not green pass badges.
Right heading: "CI platforms". Four platform lanes, exact labels:
"Ubuntu" with "PowerShell 7"
"macOS" with "PowerShell 7"
"Windows" with "PowerShell 7"
"Windows" with "PowerShell 5.1"
Bottom separated labels, exactly:
"Live AD: opt-in"
"Publish: separate approval"
Avoid all extra text except optional short left heading "Source inputs". Do not display test counts, hardcoded allowlist counts, module version numbers, release-ready or passed claims, completed CI status, live success claims, published/not-published claims, actual hosts, secrets, SSH keys, watermarks or invented logos. Pester 5.7.1 and PowerShell versions are requirements, not run evidence. Overall meaning is a procedure and distinct approval boundaries, never a current success dashboard. Preserve white/navy/teal/amber/green visual family and original illustrative quality.
```
