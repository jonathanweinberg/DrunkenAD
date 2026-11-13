# Schema Readiness Image Generation Record

- Tool mode: default built-in image_gen only (image_gen.imagegen; exposed as image_gen__imagegen).
- Intent: generate a replacement infographic using an original illustration as a style reference, followed by one targeted built-in edit.
- Use case: infographic-diagram.
- transparent_background: false for both calls.
- Built-in calls: 2; selected attempt: 2.
- Original style source (Git reference): v0.13.1:docs/images/documentation-suite-2026-05-07/schema-readiness-flow.png
- Current content source (repository-relative): docs/diagrams/schema-readiness-flow.mmd
- Attempt 2 edit input: built-in tool output from attempt 1.
- Selected bitmap: built-in tool output from attempt 2.
- Repository output: docs/images/documentation-suite-2026-10-08/schema-readiness-flow.png
- Delivery: copied the selected returned bitmap unchanged; no CLI, Python, SVG, or HTML generation or post-processing.
- Dimensions verified: 1536 x 1024 (3:2 landscape).
- Visual review: five readiness steps, generic inherited/auxiliary class graph, all four allowed-attribute families, explicit fail-closed stop sentence, separately authorized administrator path, and explicit no-schema-change footer. No write probe or automatic change in the readiness path, concrete directory identifiers, test counts, or live status claims. Green/check imagery denotes conceptual checks, not measured live success. Primary labels are clear at full resolution; supporting attribute-family text requires opening the full-size image from a small thumbnail.
- Iteration reason: first image invented concrete directory-class names and a potentially misleading hierarchy. Second call replaced only that graph with generic conceptual class objects.
- Generation scope: this bitmap and prompt record. Integration restores README thumbnails and retains the detailed Mermaid flows.

## Exact Prompt: Attempt 1

```text
Use case: infographic-diagram
Asset type: DrunkenAD project documentation bitmap, readable as a README thumbnail and at full size.
Primary request: Restore the attached original Schema Readiness illustration's rich professional technical infographic style, replacing ALL outdated content with the current accurate conceptual flow below.
Input image 1: style reference only, original schema-readiness-flow.png. Keep clean white background, navy headings, teal technical objects, amber administrator path, restrained green endpoint accent, dimensional illustrated icons, crisp lines, subtle shading, readable typography. Discard the original dense cards, raw directory details, write probes and obsolete text. Do not reproduce them.
Canvas: 3:2 landscape, ideally 1536 x 1024, opaque white. Spacious few-label infographic of illustrated objects and connectors, not dense flat cards. Large legible typography with clear hierarchy and ample whitespace. No tiny body prose.
Title exactly: "Schema Readiness"
Subtitle exactly: "Present does not mean writable on users"
Main upper flow: Five numbered conceptual illustrated objects connected left to right by clear directional arrows, each with its label below. Use a magnifying glass and attribute document, an active attribute shield, a branching class inheritance graph, an allowed-attribute document set, and a neutral directory-server object respectively.
1. "Find drink"
2. "Not defunct"
3. "Walk user inheritance" with second line "+ auxiliary classes"
4. "Allowed attributes"
5. "Ready on selected DC"
For stage 3/4 include a single readable supporting label "may / systemMay / must / systemMustContain" beneath the graph and allowed-attributes area. Show branching conceptual class objects, not just a direct single-class mayContain check.
Below the upper flow place a clear amber stop icon and the exact prominent sentence:
"Missing, defunct, unresolved, or disallowed: stop"
Below this, clearly separate the administrator workflow with whitespace and a thin amber rule, heading "Administrator path", and four amber illustrated objects joined left to right:
"Separate authorization" -> "Schema master + expected values" -> "Apply guarded change" -> "Refresh cache and verify"
These four labels may wrap over two lines for readability. The administrator path is independently authorized, not an automatic branch from a failed readiness check. No arrow from a failed check into the administrator path. A small dashed return arrow from the final administrator verification may lead back toward the readiness flow, but omit if it makes the composition crowded.
Prominent footer exact wording:
"Readiness checks do not change schema"
Constraints: Main readiness path is read-only and never performs a write probe or schema mutation. Ready is a conceptual conditional result, not a verified live status or a claim about write permissions, connectivity, or a real host. No "passed" badges or checklists of live successes. Show user inheritance AND auxiliary classes, with all four allowed-attribute families represented in the supporting label. Missing, defunct, unresolved graph, or disallowed must stop. Administrator changes are separate, guarded, on the schema master with expected values, followed by refresh and verification. No test counts, versions, merge/publication claims, raw directory DNs, IPs, actual host/account names, lab details, raw commands, watermark, or extra slogans. Preserve exact requested title/subtitle and explicit stop and read-only statements.
```

## Exact Prompt: Attempt 2 (Selected)

```text
Use case: infographic-diagram
Asset type: DrunkenAD schema readiness documentation bitmap.
Input image 1: edit target, the just-generated Schema Readiness infographic.
Make ONE tightly scoped correction: replace ONLY the internal illustrated class graph at stage 3 with a generic conceptual graph. The current named classes and their hierarchy are misleading. Remove ALL occurrences inside that small graph of "user", "person", "organizationalPerson", "inetOrgPerson", and "auxiliaryClass".
The replacement graph has exactly three dimensional blue/teal document or object nodes labeled "User class", "Inherited class", and "Auxiliary class". A node labeled "User class" connects by two neutral lines to the two generic nodes "Inherited class" and "Auxiliary class". No concrete directory-class names or invented real class hierarchy. Keep this three-node graph entirely within stage 3's existing space.
Preserve EVERYTHING else unchanged: 3:2 landscape 1536 x 1024 composition, illustrated dimensional style, white/navy/teal/amber palette, all five numbered steps, all arrows between steps, all stage labels, title "Schema Readiness", subtitle "Present does not mean writable on users", "may / systemMay / must / systemMustContain", exact stop sentence "Missing, defunct, unresolved, or disallowed: stop", separately authorized amber administrator path and its four labels, and footer "Readiness checks do not change schema".
No additional text, no write probe, no automatic schema mutation, no live-status claim, no actual hosts/accounts/IPs/DNs. This is a single local content correction; do not redesign the image.
```
