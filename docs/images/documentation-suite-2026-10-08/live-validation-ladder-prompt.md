# live-validation-ladder

- Tool mode: built-in image_gen (image_gen.imagegen); reference-guided raster generation.
- Date: 2026-10-08.
- Use case: infographic-diagram.
- Attempts: 1. No fallback, CLI generation, or post-generation image editing.
- Reference image: `v0.13.1:docs/images/documentation-suite-2026-05-07/live-validation-ladder.png`
- Reference role: original visual style; historical text and results are not current evidence.
- Workspace output: `docs/images/documentation-suite-2026-10-08/live-validation-ladder.png`
- Tool arguments: referenced_image_paths contains the reference above; transparent_background=false; prompt is reproduced verbatim below.
- Export: byte-for-byte copy of the native generated PNG; historical assets unchanged.
- Inspection: Verified exact eight ordered steps, title and subtitle, optional campaign approval outside the ladder, legible icons and labels. No hosts, service requirements, credentials, historical pass counts, or execution claims. The requested bounded-integration ladder deliberately differs from the older campaign-oriented Mermaid flow; that source is unchanged.

## Current Sources Consulted

- docs/TESTING.md
- docs/POST-MERGE-VALIDATION.md
- docs/diagrams/live-validation-ladder.mmd

The owner approved the illustrated-style refresh. Technical labels were checked
against the sources above. Image generation establishes no test or CI result.

## Exact Prompt

```text
Use case: infographic-diagram.
Asset type: DrunkenAD technical documentation illustration.
Input image 1: original live-validation-ladder.png, visual-style reference only. Replace ALL original text and its old ten-stage structure with the eight-stage procedure below. Do not copy its service list, host, historical run, counts, pass claims or campaign steps.
Create one polished 3:2 landscape bitmap infographic, ideally 1536 x 1024. Match the original's rich technical illustration quality: white background, large navy heading, teal connector arrows, amber approval boundaries, restrained green icon details, shaded dimensional icons, crisp outlines, readable short labels. This should be a visually illustrated operator journey, not flat text cards. Keep icons large and richly crafted, no dense paragraphs.
Title exactly "Live Validation Ladder"
Subtitle exactly "Increase scope only with evidence and approval"
Main composition: eight numbered stations in TWO ROWS, 1-4 across the first row left-to-right, then a clearly visible return arrow to 5 at the left of row two, and 5-8 left-to-right. A clear navigable ladder of evidence gates, with a prominent distinctive technical illustration at each station. Use these exact labels and numbers:
1 "Source checks" - source file, terminal and inspection checklist.
2 "Verify rollback" - database snapshot and clock with recovery arrow.
3 "Approve bounded fixtures" - illustrated operator approving a small fenced directory tree.
4 "Check directory readiness" - directory server, tree and magnifying glass.
5 "Run isolated integration" - isolated terminal/process boundary with small test apparatus.
6 "Read-back + metadata" - magnifying glass inspecting a directory record and metadata rows.
7 "Verify cleanup" - inspection of an empty bounded fixture area, cleanup/recheck illustration.
8 "Sanitized receipt" - document with redacted rows and a privacy shield.
Use neutral procedural iconography: no success badges or completed test results. Short labels only; do not add explanatory bullet lists.
Below the main ladder, a visually SEPARATE amber optional branch or strip with an illustrated operator, approval lock and small group of users. It must be clearly outside the eight-step flow, not connected as a ninth step. Text exactly:
"Optional"
"Seeded campaigns need separate approval"
Do not show a campaign run, seed count, 3,000-user pass claim, any actual host/domain, any credentials or SSH keys, service names, an assumption that all transport services are required, result tables, timestamps, passed/ready badges, test counts, version numbers, or invented status claims. No extra slogans. This describes the approved escalation procedure, not execution evidence. Preserve original white/navy/teal/amber/green family, legible numbering, good whitespace and rich human/technical flow illustration.
```
