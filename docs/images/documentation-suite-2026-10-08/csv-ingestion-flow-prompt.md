# csv-ingestion-flow generation provenance

- Date: 2026-10-08
- Tool mode: built-in image_gen.imagegen; reference-guided raster generation.
- Use case: infographic-diagram.
- Calls: one generation call; no retries or post-generation image edits.
- Source visual reference: `v0.13.1:docs/images/documentation-suite-2026-05-07/csv-ingestion-flow.png`
- Source role: visual style only; inspected with view_image before generation.
- Technical source: current docs/diagrams/csv-ingestion-flow.mmd and the corresponding CSV implementation and operator guide.
- Tool arguments: referenced_image_paths contains the source visual reference above; transparent_background=false; prompt is reproduced verbatim below.
- Destination bitmap: csv-ingestion-flow.png
- Dimensions: 1536 x 1024 pixels (3:2 landscape).
- Validation: visually inspected generated output for required labels, examples, caveats, and readability. No required-content issues found. Original assets remain unchanged.

## Exact Prompt

```text
Use case: infographic-diagram
Create one polished raster documentation illustration, 3:2 landscape, ideally 1536x1024 or larger at exactly 3:2.
Input image: the supplied original csv-ingestion-flow.png is a VISUAL STYLE REFERENCE ONLY. Preserve the clean white/navy/teal/amber/green illustrated documentation-suite aesthetic, rich document, spreadsheet, mapping, checklist, people, approval, magnifier, directory and report icons, fine borders and subtle dimensional shading. Replace ALL old technical text. Do not replicate the old people, private addresses, domain strings, UPN support, Profile- namespace mapping, guaranteed-safety claims or automatic publishing claims.
Title exactly: "CSV Ingestion"
Subtitle exactly: "Validate the file before directory access"
Design: exceptionally legible spacious labels, crisp navy sans-serif, generous white space, teal flow arrows, amber cautions and green outcomes. Retain rich illustrative icons rather than flat all-text panels. An illustrated six-step left-to-right flow occupies the upper body. Under it arrange local validation and blank-cell annotations, a large three-row synthetic mapping example, and results; keep wide space for long mapping values. A bottom caveat band is readable. All required text is below; do not add lengthy copy.
Six flow steps in this exact order, with arrows and relevant large illustrations:
"CSV file + map" -> "Local validation" -> "Preflight all users" -> "Confirm current plan" -> "Verify approved delta" -> "Scoped writes"
Local validation must be visually before any directory interaction; preflight covers all users before writes. The final write uses prefix-scoped Remove/Add. If showing a directory server, show ONE endpoint only.
Required validation labels verbatim, readable beside suitable icons:
"Strict Unicode decoding"
"Complete records"
"Unique SamAccountName"
"UTF-8 recommended"
Required blank-cell behavior labels verbatim:
"Blank cells retain data"
"ClearBlankNamespaces opts into clearing"
Do not imply that blank cells or all-blank rows clear data by default.
A visual mapping example under heading "Synthetic mapping", with exactly these source-to-value arrows:
"ProfileTier" -> "CsvProfile-Tier=Gold"
"Flags" -> "Flags-Audited"
"RoutingMailbox" -> "CsvRouting-Mailbox=user@example.test"
Each source is a CSV column, each destination is a generated namespaced drink value; do not treat the example mailbox as an identity lookup or claim UPN input support. Use a wide mapping area and readable text without truncation.
Results heading "Results" with four distinct clearly labeled outcomes:
"Written" / "NoChange" / "Declined" / "WhatIf"
Required readable caution: "Computed output is not a read-back"
Required small but legible note: "Earlier successful rows are not rolled back"
A small label by scoped writes may say "Remove/Add only".
Do not claim transactions, guaranteed safety, automatic rollback, automatic report export or publishing. No private hostnames, IP addresses, GUIDs, lab names, real people, credentials or secrets. The sole email-like text is the synthetic user@example.test specified above. Keep text short, accurate, legible and uncrowded. No watermark or extra slogans.
```
