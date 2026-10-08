# Issue 13: October Review Adjudication And Hardening

- Issue: [#13](https://github.com/jonathanweinberg/DrunkenAD/issues/13)
- Date: 2026-10-08
- Candidate base: `caeb0ec`, the July branch proposed in draft PR #12.
- External review base: `main` at `0306f13` (0.13.1), static review only.
- Status: implemented and locally validated; remote CI recorded in issue #13.

## Scope And Method

The external review is useful evidence, not an acceptance checklist. It explicitly
excluded PR #12, so findings must be checked against both public main and the
existing candidate. A clean archive of the July candidate produced 94 passing
tests, no failures, and six integration tests not run. That is the comparison
baseline, not evidence that public main has been repaired.

Three complementary standards govern the decisions:

| Perspective | Acceptance Standard | Outcome |
| --- | --- | --- |
| Contract and compatibility | Existing exports, parameter sets, wrappers, help, and PowerShell 5.1 remain usable. | Shared private writer removes repeated work without a public API break. |
| Adversarial state transitions | Prove ownership, stale-read behavior, malformed schema handling, partial failure, and preview safety. | New regressions target actual loss/failure boundaries rather than only happy paths. |
| Reproducibility | Exact baseline, pinned Pester, discovery failures, Windows execution, and live cleanup are checked separately. | Unit success is not presented as schema-mutation or distributed-concurrency proof. |

These perspectives agree on scoped deltas and schema traversal. They differ on
removing old APIs and simplifying schema provisioning: an aesthetically smaller
API is not sufficient justification for breaking callers or inventing forest
schema objects. Strategy therefore favors a compatible repair now and explicit
future design decisions where necessary. An independent final regression review
supplements the primary review.

## External Finding Decisions

| Finding | Adjudication | Action And Evidence |
| --- | --- | --- |
| Overlapping prefixes in one map delete values | Valid on reviewed main; already rejected in the July candidate. | Retain case-insensitive literal overlap rejection and tests. Do not claim this is a new October fix. |
| A later `Meta-` write removes `Meta-Extra-*` | Expected under literal-prefix ownership, not evidence of a separate namespace registry. | Document that callers must coordinate non-overlapping prefixes across operations. A mandatory delimiter alone does not solve nested prefixes. |
| Whole-attribute replacement loses another namespace's concurrent write | Confirmed in the July candidate. | Replace full `Replace`/`Clear` operations with one scoped `Remove`/`Add` call. Test an unrelated addition after the initial read. |
| Default DC can vary during a write | Confirmed. | Select the effective DC from RootDSE and reuse it for schema queries, identity lookup, and mutation. Explicit DC input remains supported. |
| Readiness ignores inheritance and auxiliary classes | Confirmed. | Traverse superclass and both auxiliary-class lists, including optional and mandatory attribute lists. Cache within the operation and fail closed on unresolved, ambiguous, or cyclic graphs. AD's `top` self-parent is an explicit valid exception. |
| Enablement directly extends `user` | Existing explicit administrator operation, not silently unsafe merely because it is direct. | Keep the guarded opt-in path. An auxiliary-class provisioning mode needs naming/OID, ownership, migration, and operational review before implementation. Never auto-create schema objects. |
| Enablement uses a short sleep instead of a cache refresh | Confirmed. | Request RootDSE `schemaUpdateNow` after the approved change. Refresh failure reports that the schema modification remains applied; it is not a rollback. |
| Script-level `WhatIf` is unavailable | Already corrected by the July candidate. | Preserve outer `SupportsShouldProcess` and expand tests proving preview does not mutate or refresh. |
| Repeated schema checks and projection lookup | Confirmed. The review's exact query estimate is illustrative, not a measured benchmark. | One operation context; one user lookup for projection; one schema check per CSV invocation. No persistent schema cache with hidden staleness. |
| Empty CSV and JSON null fail before validation | Already fixed and covered in July. | Retain the binding fixes and meaningful validation errors. |
| A bad CSV identity causes avoidable partial writes | Confirmed. | Resolve and validate every usable row before the first mutation. Later AD/write failures stop with completed, failed-row, pending, and prepared counts on the error TargetObject. No transaction or automatic rollback is promised. |
| CSV supports only SamAccountName | Documented format restriction, not an undisclosed bug. | Preserve the contract. Additional identity columns require an explicit ambiguity and migration design. |
| No schema length validation | Confirmed. | Use the selected schema's actual `rangeUpper`, including the prefix. Do not hardcode 256 or invent a bound when the schema omits it. |
| Case-only updates are ignored | Confirmed. | Use ordinal, case-sensitive delta comparison while retaining case-insensitive ownership and desired-value deduplication. |
| Shared temporary log includes payloads | Confirmed. | Logs contain counts only. The follow-up bounds the current user's default log; explicit paths remain caller-managed. |
| Projection `WhatIf -PassThru` returns nothing | Confirmed. | Return the computed snapshot preview under WhatIf. Explicitly document that it is not a fresh directory read-back. |
| Version-pinned release tests drift | Main was stale; July corrected the number but still pinned assertions. | Derive version assertions from the manifest, verify version shape and current changelog heading, and retain export parity. Public main changes only after an authorized merge. |
| Repeated identity forwarding | Valid in changed write paths. | Centralize bound-identity extraction in a private helper; retain explicit public parameter declarations for discoverability and compatibility. |
| Too many exports; AutoConfirm duplication | Compatibility concern, not grounds for silent removal. | Keep all 12 exports and AutoConfirm; adapt wrappers to the shared implementation. Any removal requires a deprecation/versioning decision. |
| Ordered maps become hashtables | True in some boundaries; order is not a storage contract. | Make owned delta planning deterministic where useful. AD multivalues remain unordered; tests must not depend on directory return order. |
| Duplicate schema DN fields | Existing public result shape. | Keep aliases for compatibility. Removing one does not improve write safety. |
| Repeated schema report writer | Confirmed local duplication. | Extract one report writer inside the admin script. |
| Repeated blank check and duplicate drink projection property | Low-risk cleanup opportunities. | Deduplicate requested AD properties. Leave unrelated CSV normalization alone rather than expanding the patch for aesthetics. |
| Export list appears in loader and manifest | Deliberate explicit public contract. | Keep parity checks; duplication here is small and independently verifiable. |
| Incomplete manifest FileList | Confirmed. | List all distributable module files and test exact parity against module contents. |
| Docs, PNGs, atlas, seed data, issue mirrors, commit churn | Primarily a maintainability judgment, not proof of a runtime defect. | Update current flow sources and atlas, label dated plates as historical, keep established help/history/seed assets. Do not rewrite history or delete evidence to improve an aesthetic score. |

## Additional Regression Found

The trusted test runner previously checked only individual failed-test count.
A container/discovery failure can have zero failed tests and still be a failed
run. It now requires the overall Pester result to be `Passed`. A real child
PowerShell process with a synthetic discovery failure verifies nonzero exit.
That test also handles Windows PowerShell 5.1's redirected stderr ErrorRecords.

Independent final review caught a confirmation-scope regression in the candidate:
calling a fresh private writer for each CSV row reset Yes/No to All. Confirmation
now belongs to the outer import command and approved rows call the shared writer
without a second prompt. Preview or declined rows still return computed values.
Dedicated interactive-host regressions verify the two All choices.

## Second Review Decisions

The follow-up reviewed the candidate at `c2949ef`. The changes below are
tracked in the same issue and PR, without another duplicate issue mirror.

| Finding | Decision |
| --- | --- |
| Sample CSV collides with projection defaults | Confirmed. Rename only the sample prefixes to `CsvProfile-` and `CsvRouting-`; preserve default projection compatibility. Test the combined map and both execution orders against final state. |
| CSV blanks retain old values | Confirmed inconsistency. Retain every mapped prefix, including empty replacements. Document the behavior change and preview/migration guidance; no automatic data migration. |
| CSV writes reuse preflight snapshots | Confirmed. Keep full validation, refresh approved resolved identities immediately before mutation, and expose later failures. This narrows the stale window but cannot eliminate races. |
| Results do not distinguish outcomes | Confirmed. CSV/projection summaries report Written, NoChange, Declined, or WhatIf. Failure progress separates processed counts from write counts. Generic writer output remains compatible. |
| Reads traverse the write-readiness graph | Confirmed. Attribute reads use a lightweight presence check and the same resolved controller. Full readiness queries retain graph validation. |
| Explicit domain aliases can drift between calls | Confirmed. Pin the RootDSE hostname for all subsequent calls while preserving an explicit port. Separate operations still need a shared actual DC hostname. |
| Default logs accumulate per invocation | Confirmed. Reuse a bounded current-user log with one archive and session correlation. Do not delete legacy or caller-managed files; log failures warn separately from write outcomes. |
| Dead readiness assertion and automatic-variable shadowing | Remove the unused private assertion and rename the class lookup variable. Keep explicit public parameter declarations for help and binding. |
| Smoke cleanup failures are hidden | Confirmed. Require terminating removal and verified absence before reporting success; add executable cleanup failure tests. |
| Wrapper stacking and repeated checks | Remove avoidable forwarding/check duplication and reuse the existing identity helper for reads. Keep validation at the public boundary and private plan boundary, and retain supported exports. |
| Source-only release and campaign tests | Replace selected text assertions with executable release-gate and cleanup tests. Static ownership/safety guards remain supplemental, not live proof. |
| Large docs, seed data, and tracking volume | Keep existing reproducible assets and historical records. Update current diagrams in place; avoid new generated plates or another issue mirror. Future receipts belong on the issue, contracts in operator docs. |
| Merge drafts and close implemented issues | Operationally sensible after review, but not authorized by a pasted recommendation. Keep #12 and #15 separately attributable, then merge #12, retarget/revalidate #15, and merge only with owner approval. Leave issues ready for closure. |

Supported compatibility commands have no scheduled 0.13-series removal. A
future removal needs migration guidance, a warning period, and a breaking-version
decision; reducing export count alone is not a correctness fix.

## Fresh Review Decisions

The static review of `7071a7d` identified several valid follow-ups and also
corrected earlier recommendations. These decisions supersede the corresponding
second-review rows above; the prior receipts remain dated evidence.

| Finding | Decision And Rationale |
| --- | --- |
| Generic examples collide with projection | Change current generic examples and verify actual documented prefixes against default ownership. Keep established projection defaults and historical evidence unchanged. |
| Default blank clearing breaks patch compatibility | Withdraw the unmerged default-clearing change. Retain blank namespaces by default and add `ClearBlankNamespaces` for deliberate clearing. All-blank default rows warn and skip. Update module release notes as well as operator docs. |
| Truncated rows look like blanks | Reject nonrectangular records before AD access. The suggested null-only check is insufficient: actual PowerShell 7.6 also returns null for a valid unquoted trailing empty cell. Validate structure with the framework CSV parser, then convert the same text snapshot; support quoted commas/newlines and valid empty cells. |
| Explicit endpoint is replaced | Preserve explicit host/IP/alias/tunnel endpoints. Resolve absent servers and domain DNS names, identified against RootDSE domain metadata, to the controller hostname. Do not assume every alias is a domain locator. |
| Confirmation approves a stale plan | Refresh before the prompt, then compare exact owned Remove/Add sets after approval. Stop if those sets changed, without writing that row; unrelated namespace changes may proceed. No locking or transaction claim. |
| Logger lacks useful identity and overrides warnings | Keep the supported optional logger, bounded retention, and path protections; these guards address filesystem risks. Add ObjectGUID correlation without account names or payloads and respect warning suppression. Do not expand the public API solely to expose legacy convenience logging. |
| Test allowlist guard misses new suites | Compare the explicit trusted allowlist with every top-level test file, including omission/addition/duplication regressions. Keep discovery explicit rather than executing arbitrary nested test files. |
| CI runs units twice | Run them once through the release gate in each platform lane. |
| Enabled changes meaning with PassThru | Both forms check presence only. Mark readiness unassessed in detailed presence reports and retain the dedicated full-readiness command. |
| Land the stack | Ask for explicit owner approval to merge #12, then retarget/revalidate #15. A pasted process recommendation does not itself authorize merges or issue closures. No tag or release is implied. |

The three standards expose different tradeoffs: compatibility favors opt-in
clearing and preserving explicit endpoints; adversarial testing requires
structural CSV validation and stable approved deltas; reproducibility requires
complete test discovery and exact-candidate checks. A smaller logger is an
understandable maintenance preference, but deleting its safeguards or supported
switch is not necessary to fix the demonstrated defects. Public documentation
is updated in place rather than creating another review mirror.

## Verification Ledger

The October ledger is sanitized. Credentials, new raw output, and other private
material remain excluded. The specific historical publication exception below
does not broaden permission to publish future lab artifacts.

| Check | Result |
| --- | --- |
| Clean July baseline, Pester 5.7.1 | 94 passed, 0 failed, 6 integration not run. |
| Initial October candidate local source gate | 204 passed, 0 failed, 8 integration not run; syntax, docs, atlas, and release gate passed. |
| Windows Server 2025 / Windows PowerShell 5.1 | 204 unit tests passed, including both confirmation choices; 8 integration tests excluded from that process. |
| Real-directory readiness | Ready without any schema modification. |
| Isolated live integration | 8 passed, 0 failed, 0 skipped, 0 failed containers. Separate fresh process after rollback preparation; no newly created test accounts remained. |
| Independent final regression review | One actionable CSV confirmation-scope regression found and fixed; both new tests fail against an in-memory regression mutation and pass against the fix. |
| Diagrams and atlas | Five Mermaid sources rendered successfully. All seven atlas flows and 34 nodes checked at desktop/mobile widths; no page errors or document overflow. Long labels wrap in both atlas variants. |
| Remote CI | See issue #13 and the PR checks for the exact pushed candidate; local validation is not a remote CI claim. |

Second-review validation: the local release gate passes with 256 unit tests.
Windows PowerShell 5.1 passes 255, with one macOS-specific link test skipped;
ten integration cases are excluded from both unit runs. The combined suite
also exposed and corrected fixture-module leakage and nonportable manifest
test setup. Follow-up live and remote CI receipts are recorded on issue #13.
An independent review found a preview-mode log-rotation defect; regression
tests now prove existing logs are byte-for-byte unchanged under preview.

Fresh-review validation: 347 local unit tests pass; Windows PowerShell 5.1
passes 346 with one macOS-only test skipped. Both exclude the 12 opt-in live
cases. The fresh suite adds explicit blank-retention/clearing live coverage,
but it has not been run against AD pending a new authorization; the earlier
ten-case live receipt applies only to `7071a7d`. An independent review found
and verified the fix for hash-prefixed CSV records, with all six CSV structure
tests passing. The runtime allowlist guard also rejects omission of its own
release-test suite. Six diagrams render and all seven atlas flows pass desktop
and mobile checks. Exact pushed-commit CI receipts remain on issue #13.

## Remaining Limits

- Scoped deltas protect unowned values from the demonstrated same-DC stale-read
  loss. They do not implement compare-and-swap, locking, or same-prefix
  serialization. Conflicting same-prefix deltas may fail or merge undesirably.
- AD replication conflicts for nonlinked multivalued attributes remain an
  attribute-level concern. Pinning one operation does not coordinate separate
  writers on different DCs. Use one writer/DC policy or external coordination.
- Schema readiness is a schema legality check, not proof of object ACL rights,
  replication convergence, or successful future writes.
- CSV preflight retains prepared rows in memory. Execution refreshes approved
  objects, but same-prefix changes after that read can still cause conflicts.
  Very large imports need memory/runtime measurement before scale claims.
- Schema enablement code is unit-tested, not applied to the live forest in this
  pass. The isolated integration suite is not a seeded-scale campaign.
- Logs are payload-minimized, not an audited secure logging subsystem. Explicit
  paths, platform file permissions, retention, and error/transcript handling
  remain operator responsibilities.

## Public Documentation Boundary

The initial privacy scan identified an older validation note and six directory
screenshot/HTML attachments already on public main. They were temporarily
removed by `aa335b7`, also proposed independently as `90d0da1` in PR #14.

On 2026-10-08, the repository owner explicitly accepted publication of the
details covered by [commit 90d0da1](https://github.com/jonathanweinberg/DrunkenAD/commit/90d0da13162cab2ba2ae817c7055a5ade5d3cc14).
That limited removal is therefore reversed, and the historical note and six
attachments remain available. No history purge is required for these accepted
details. This does not authorize publishing passwords, tokens, private keys,
new raw live output, or unrelated private lab material. The historical record
is not current validation evidence.

## Primary References

- [Set-ADUser](https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-aduser?view=windowsserver2025-ps): combined operation ordering removes before adding.
- [drink schema attribute](https://learn.microsoft.com/en-us/windows/win32/adschema/a-drink): standard schema metadata; runtime metadata remains authoritative.
- [Attribute characteristics](https://learn.microsoft.com/en-us/windows/win32/ad/characteristics-of-attributes): nonlinked multivalue replication limitations.
- [Updating the schema cache](https://learn.microsoft.com/en-us/windows/win32/ad/example-code-for-updating-the-schema-cache): explicit RootDSE refresh pattern.
- [top class](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adsc/041c6068-c710-4c74-968f-3040e4208701): schema-root inheritance behavior.
- [TextFieldParser](https://learn.microsoft.com/dotnet/api/microsoft.visualbasic.fileio.textfieldparser): framework CSV structure parsing rather than a custom delimiter parser.
- [Import-Csv](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-csv): supported CSV conversion and header behavior; runtime regressions verify ambiguous empty fields.

## Delivery Boundary

October work is layered on the unmerged July candidate. Keep PR #12 and the
October review separately attributable. The privacy-only cleanup in
[PR #14](https://github.com/jonathanweinberg/DrunkenAD/pull/14) is withdrawn under
the owner's revised publication decision; the code hardening is unchanged.
Issue #13 remains open for review; this change does not authorize a merge,
issue closure, tag, or release.

Implementation commit: `9191581`. The privacy removal (`aa335b7`, independently
`90d0da1`) and its reversal remain attributable; no history was rewritten.
