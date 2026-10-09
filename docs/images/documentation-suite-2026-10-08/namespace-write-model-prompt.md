# namespace-write-model generation provenance

- Date: 2026-10-08
- Tool mode: built-in image_gen.imagegen; reference-guided raster generation.
- Use case: infographic-diagram.
- Calls: one generation call; no retries or post-generation image edits.
- Source visual reference: `v0.13.1:docs/images/documentation-suite-2026-05-07/namespace-write-model.png`
- Source role: visual style only; inspected with view_image before generation.
- Technical source: current docs/diagrams/namespace-write-model.mmd and the corresponding scoped writer and data-model guide.
- Tool arguments: referenced_image_paths contains the source visual reference above; transparent_background=false; prompt is reproduced verbatim below.
- Destination bitmap: namespace-write-model.png
- Dimensions: 1536 x 1024 pixels (3:2 landscape).
- Validation: visually inspected generated output for required labels, examples, caveats, and readability. No required-content issues found. Original assets remain unchanged.

## Exact Prompt

```text
Use case: infographic-diagram
Create one polished raster documentation illustration, 3:2 landscape, ideally 1536x1024 or larger at exactly 3:2.
Input image: the supplied original namespace-write-model.png is a VISUAL STYLE REFERENCE ONLY. Retain its rich illustrative teal icons, crisp white background, navy headings, teal arrows, amber ownership indicators and green result accents. Replace ALL old technical content. Do not copy its identities, hostnames, domain strings, old safety claims, Replace/Clear operations, or commit language. This is not a text-only panel diagram: give the tag, document, checklist, magnifier, user, remove/add, approval and directory-server illustrations real visual presence, dimensional shading and polished detail.
Title exactly: "Namespace Write Model"
Subtitle exactly: "Change owned values. Preserve unrelated data."
Composition: spacious top title, an illustrated six-step left-to-right strip below it, then a large before / delta / after comparison, then a short illustrated caveat footer. Keep all typography exceptionally legible, with generous spacing and no overlaps. Use navy sans serif. All required text below must be included verbatim, without extra paragraphs.
Six numbered steps in this order, connected by arrows:
"Validate prefixes" -> "Check readiness" -> "Resolve user" -> "Plan Remove/Add" -> "Confirm" -> "Apply delta"
Illustrate each step with a suitable rich icon. Show only ONE actual directory-controller/server endpoint in the entire image, labeled "Same DC endpoint"; all directory read/write activity refers to this single endpoint. Do not draw multiple DCs or imply transactions or atomic guarantees.
Main comparison:
Left heading "Before", small attribute label "drink", exactly three separate rows:
"AppProfile-Tier=Silver" with amber "OWNED" badge
"Flags-Enabled" with "KEEP" badge
"Keep-Stable" with "KEEP" badge
Center: visually illustrate removing the owned Silver value and adding the owned Gold value using a minus and plus, with heading "Remove/Add only". No other value is removed. A literal tag "AppProfile-" identifies the owned prefix.
Right heading "After", small attribute label "drink", exactly three separate rows:
"AppProfile-Tier=Gold"
"Flags-Enabled"
"Keep-Stable"
Green accents may distinguish the changed owned result; do not imply guaranteed concurrency safety.
Four clearly readable short statements, integrated into illustrated lower annotations:
"Remove/Add only"
"No whole-attribute Replace or Clear"
"Coordinate concurrent writers"
"WhatIf previews; read back to verify"
You may show "Remove/Add only" once as the center heading and use the remaining three as footer statements.
Technical constraints: resolve one user, operate on one actual DC endpoint, compute and apply a scoped delta, preserve unrelated values through scoped operations. WhatIf and computed output are not actual read-back verification. Do not invent guaranteed safety, transactions, automatic rollback, locking, whole-attribute replacement or clearing.
No private hostnames, IP addresses, GUIDs, lab names, people, credentials, UPNs, publishing marks, logos or watermark. No extra explanatory copy. Preserve the rich original illustrated-suite feel, not flat all-text cards.
```
