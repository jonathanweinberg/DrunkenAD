# Changelog

## 0.13.2

- Restored imagegen illustrations and README thumbnails with corrected workflow
  content, retaining editable Mermaid details and historical artwork references.
- Fail closed on malformed CSV byte sequences before AD access, preserving
  UTF-8 and BOM-marked UTF-16/UTF-32 without silently replacing damaged text.
- Replaced whole-attribute writes with prefix-scoped Remove/Add deltas on one
  selected domain controller. Case-only changes are honored, unowned values
  added after the read are preserved, and schema length bounds are validated.
- Reused one readiness context per operation; CSV preflights all usable rows,
  refreshes plans before confirmation, rejects a changed delta afterward, and reports progress
  and per-outcome counts on failure.
- Preserved blank CSV namespace retention by default; `ClearBlankNamespaces`
  explicitly opts into clearing. Reject nonrectangular CSV records before AD
  access while accepting quoted and unquoted empty cells.
  The sample config now uses `CsvProfile-` and `CsvRouting-` to coexist with the
  unchanged default projection. Existing imports need a preview and ownership
  review; stored values are not automatically migrated.
- Added explicit Written, NoChange, Declined, and WhatIf statuses to CSV and
  projection summaries, without changing generic writer string-array output.
- Kept read checks and `Enabled -PassThru` limited to attribute presence.
  Detailed presence reports mark write readiness as unassessed. Preserve explicit
  hosts, IPs, aliases, and tunnel endpoints; pin absent servers or domain DNS
  names to RootDSE's controller, retaining supplied ports.
- Added inherited and auxiliary-class schema readiness, fail-closed graph
  validation, and explicit schema-cache refresh after guarded enablement.
- Bounded default optional logs, added session and ObjectGUID correlation, and
  excluded account names and attribute payloads. Explicit paths remain caller-managed; logging failures warn
  without misreporting an already completed directory write.
- Expanded the explicit trusted test allowlist, failed discovery/container
  errors reliably, and checked manifest FileList completeness.
- Refreshed current Mermaid flows and atlas data; dated infographic plates are
  retained as historical rather than presented as current write contracts.
- Added sample/projection coexistence and smoke-cleanup regressions; campaign
  checks now read final directory state after both workflows.
- Hardened namespace and CSV input boundaries by rejecting blank or overlapping
  prefixes, empty CSV input, duplicate normalized identities, and ambiguous
  local configuration before Active Directory readiness or lookup.
- Fixed stale empty projections, delimiter-based multivalue comparison
  collisions, blank labeled CSV records, and culture-sensitive prefix matching.
- Isolated local and release validation from ignored live-result artifacts by
  requiring exact Pester 5.7.1 and an explicit tracked test allowlist.
- Made the live campaign fail closed on unexpected or unowned users, require
  rollback evidence and confirmation, compare exact manifest/CSV identity sets,
  and record per-run inputs with SHA-256 hashes.
- Added a Windows PowerShell 5.1 CI lane and regressions for script common
  parameters, JSON null/array conversion, and empty smoke assertions.
- Made release-metadata and help-example assertions separator- and
  parser-neutral, then passed the complete Ubuntu, macOS, Windows PowerShell
  Core, and Windows PowerShell 5.1 matrix.
- Fixed release-readiness drift by deriving the current release version from the
  module manifest instead of hardcoding an older release number.
- Added architecture atlas validation for the reusable JSON map, embedded
  self-contained HTML data, external-data HTML variant, flow references, node
  kinds, and repo-relative file links.
- Wired atlas validation into documentation hygiene so docs CI and the local
  release gate catch map drift before release.
- Refreshed the architecture atlas, Mermaid sources, issue mirrors, and six
  page-facing documentation plates to describe the current safety boundaries
  and verified CI state without claiming merge, tag, publish, or live-lab proof.

## 0.13.1

- Added an interactive architecture atlas with a self-contained HTML version,
  an external-data HTML version, and reusable JSON map data.
- Linked the atlas from the documentation index so readers can browse the
  module, Active Directory data model, validation gates, and release surfaces
  from one rollover view.
- Added an ignored `.codex-local/` workspace area so local agent operating notes
  stay out of public docs and release commits.

## 0.13.0

- Made comment-based help a first-class public interface for every exported
  command, including inputs, outputs, examples, related links, component, role,
  and functionality metadata.
- Added `about_DrunkenAD` as a module-level Get-Help entrypoint for command
  discovery, schema readiness, CSV ingestion, and live-validation guidance.
- Added release tests that exercise real `Get-Help` output and fail if exported
  command help regresses to autogenerated or incomplete content.
- Updated user docs and issue records for the issue #5 help-focused release.

## 0.12.1

- Replaced host-specific live campaign wording with generic host-method
  guidance for future seeded campaign implementations.
- Added a host-method contract page that describes rollback, workspace,
  result-collection, credential, and operator-note responsibilities without
  naming a specific virtualization or remote-execution method.
- Updated issue records, release metadata, and release-readiness checks for the
  corrective documentation release.

## 0.12.0

- Superseded by `0.12.1`. The first live-campaign documentation cleanup made one
  host method too prominent; the corrective release keeps the public docs generic
  while preserving the checked-in live campaign scripts.

## 0.11.0

- Split the module into focused `Private` and `Public` source files while preserving the exported command surface.
- Added `Quick`, `Standard`, and `Full` live validation campaign profiles.
- Added release-readiness validation for manifest metadata, importability, exports, syntax, docs, and tests.
- Expanded opt-in integration coverage for CSV ingestion and projection workflows.
- Added image-gen2 documentation plates for the module layout, campaign profiles, and release-readiness gate.

## 0.10.1

- Surfaced `Split-DrunkenADCsvField` as a public helper for CSV multivalue splitting.
- Documented `SplitOn` CSV ingestion behavior and added example coverage.
- Registered PSGallery in CI when missing before installing the pinned Pester version.
