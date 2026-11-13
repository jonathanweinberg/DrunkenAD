# Module Layout Image Generation Record

- Tool mode: default built-in image_gen only (image_gen.imagegen; exposed as image_gen__imagegen).
- Intent: generate a replacement infographic using an original illustration as a style reference.
- Use case: infographic-diagram.
- transparent_background: false.
- Built-in calls: 1; selected attempt: 1.
- Original style source (Git reference): v0.13.1:docs/images/documentation-suite-2026-05-11/module-layout.png
- Current content source (repository-relative): docs/diagrams/module-layout.mmd
- Selected bitmap: built-in tool output from attempt 1.
- Repository output: docs/images/documentation-suite-2026-10-08/module-layout.png
- Delivery: copied the returned bitmap unchanged; no CLI, Python, SVG, or HTML generation or post-processing.
- Dimensions verified: 1536 x 1024 (3:2 landscape).
- Visual review: six helper filenames, incoming helper-to-loader arrow, 12 exported commands grouped into four families, manifest export parity and PowerShell 5.1, neutral Syntax/Docs/Unit/CI categories. No test counts, release version, or live/passed/publication claims. Large labels are clear at full resolution; detailed reading should use the full-size bitmap rather than a small thumbnail.
- Generation scope: this bitmap and prompt record. Integration restores README thumbnails and retains the detailed Mermaid flows.

## Exact Prompt

```text
Use case: infographic-diagram
Asset type: DrunkenAD project documentation bitmap, readable as a README thumbnail and at full size.
Primary request: Restore the attached original's rich illustrated technical infographic style while replacing ALL obsolete text and topology with the exact current specification below.
Input image 1: style reference, original module-layout.png. Retain its professional clean white background, navy headings, teal technical objects, amber command accents, small green accents, dimensional illustrated folder/file/terminal/manifest/tool icons, crisp lines, subtle shading and strong readable typography. Redesign its layout as necessary. Do not preserve any old text not specified here.
Canvas: 3:2 landscape, ideally 1536 x 1024. Opaque white background. Spacious composition, few short labels, large legible type, not dense flat cards. Rich illustrated objects connected as a technical graph. No raw code listing.
Title exactly: "DrunkenAD Module Layout"
Subtitle exactly: "Focused internals. Stable public commands."
Content and topology:
On the left, an illustrated folder labeled "Private helpers" with SIX clearly readable file labels:
"Core.ps1"
"WriteOperation.ps1"
"PrefixMap.ps1"
"ProjectionMap.ps1"
"CsvMapping.ps1"
"SchemaStatus.ps1"
The six private helpers feed INTO a central illustrated module object labeled "DrunkenAD.psm1" and "Deterministic loader". Make arrow direction unmistakably private helpers -> loader.
From the central loader an arrow leads to an illustrated public terminal / command grouping on the right labeled "12 exported commands", with only four group labels:
"Get / Set / Remove"
"CSV + projection"
"Schema readiness"
"Compatibility"
Below the loader, a connected illustrated manifest document labeled "DrunkenAD.psd1", "Export parity", and "PowerShell 5.1".
A lower validation region connected from the manifest labeled "Validation" with four illustrative neutral tool icons and short labels "Syntax", "Docs", "Unit", "CI". These are validation categories, not completion statuses; no checkmarks or passed badges.
Constraints: Six helpers, not five. Public command count is exactly 12, but show grouped command families rather than an exhaustive list. Preserve exact filenames and requested title/subtitle spelling. No version numbers, test counts, release-ready claims, green passed claims, merge claims, publication claims, real hostnames, account names, lab details, IP addresses, directory DNs, tiny prose, watermark, or extra slogans. Use green only as a restrained decorative accent, not as evidence of successful tests. Conceptual illustrated objects only.
```
