# live-campaign-profiles

- Tool mode: built-in image_gen (image_gen.imagegen); reference-guided raster generation.
- Date: 2026-10-08.
- Use case: infographic-diagram.
- Attempts: 1. No fallback, CLI generation, or post-generation image editing.
- Reference image: `v0.13.1:docs/images/documentation-suite-2026-05-11/live-campaign-profiles.png`
- Reference role: original visual style; historical text and results are not current evidence.
- Workspace output: `docs/images/documentation-suite-2026-10-08/live-campaign-profiles.png`
- Tool arguments: referenced_image_paths contains the reference above; transparent_background=false; prompt is reproduced verbatim below.
- Export: byte-for-byte copy of the native generated PNG; historical assets unchanged.
- Inspection: Verified Quick 30 users/9 CRUD, Standard 300 users/30 CRUD, Full 3,000 users/300 CRUD with default badge; planned-volume disclaimer; six ordered common-path stages; exact stop and privacy warnings. No current-result claims.

## Current Sources Consulted

- tests/Live/Invoke-DrunkenADLiveCampaign.ps1
- tests/Live/Invoke-DrunkenADGuestCampaign.ps1
- docs/diagrams/live-campaign-profiles.mmd

The owner approved the illustrated-style refresh. Technical labels were checked
against the sources above. Image generation establishes no test or CI result.

## Exact Prompt

```text
Use case: infographic-diagram.
Asset type: DrunkenAD technical documentation illustration.
Input image 1: original live-campaign-profiles.png, visual-style reference only. Replace its old explanatory copy and ladder with the precise profile totals and common path below.
Create one polished 3:2 landscape bitmap infographic, ideally 1536 x 1024, matching the original rich illustrated technical infographic craftsmanship. White background, bold navy heading, teal connectors, amber Full/default accent and approval warnings, restrained green icon details. Large beautiful shaded icons: gauge, ascending scale bars, database stack, human operator, rollback clock, hashed documents, identity group, bounded directory tree, CSV/projection records and privacy receipts. Use rich dimensional illustration and clean outlines, not flat text-only cards. Keep labels short and highly readable with generous spacing.
Exact title: "Live Campaign Profiles"
Exact subtitle: "Choose scale after proving the mutation boundary"
Top section: three balanced profile illustrations, one per column. Left gauge icon, center ascending scale icon, right amber database-stack icon. Exact profile text:
"Quick"
"30 users"
"9 CRUD"
"Standard"
"300 users"
"30 CRUD"
"Full"
"3,000 users"
"300 CRUD"
Add a small "default" badge ONLY to Full.
Directly beneath these three profiles display exactly "Planned profile volumes, not results". These counts are planned aggregate profile volumes, NOT pass counts or completed operations; no per-region counts needed.
Middle section: an illustrated COMMON PATH with SIX stations connected in this exact order. Use two rows of three stations, first row left-to-right, clear return connector to the left of row two, then left-to-right. Each station has a large technical/operator illustration and exactly this short label:
"Rollback + approval"
"Hashed run inputs"
"Exact identity set"
"Bounded root"
"CSV + projection + CRUD"
"Read-back + receipts"
The first station shows a human operator, approval lock and rollback snapshot; the second shows sealed/hash-mark documents; the third an exactly matched set of identity tokens; the fourth a directory tree surrounded by a precise dashed boundary; the fifth integrated CSV page, attribute sliders and CRUD circular arrows; the sixth magnifier on records and receipt. Keep the path visually distinct from the three profile choices. Do not imply Full is preapproved.
Bottom: two prominent, spacious safety statements with clear illustrative icons, amber stop/warning symbol for the first and a privacy lock/shield for the second. Text verbatim:
"Unexpected users: stop. Never prune or adopt."
"Credentials and raw results stay private."
No other text. Do not show live pass/results claims, elapsed times, test counts, actual hosts/domains, passwords, SSH keys, fake execution receipts, current success status, or automatic cleanup of unknown accounts. The unexpected-user stop rule must be unmissable. Preserve original white/navy/teal/amber/green palette and readable illustrated human flow.
```
