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

The requested OpenAI Docs workflow starts with current official guidance,
inventory, behavioral preservation, and representative validation. This repo is
a PowerShell module with no OpenAI API/model integration to migrate. The
[GPT-6 Astra migration guidance](https://developers.openai.com/api/docs/guides/latest-model/gpt-6-astra.md#migration-quickstart)
informs the review discipline; it is not a formal certification or a reason to
add an unrelated AI dependency.

Three complementary standards govern the decisions:

| Perspective | Acceptance Standard | Outcome |
| --- | --- | --- |
| Builder: contract and compatibility | Existing exports, parameter sets, wrappers, help, and PowerShell 5.1 remain usable. | Shared private writer removes repeated work without a public API break. |
| Critic: adversarial state transitions | Prove ownership, stale-read behavior, malformed schema handling, partial failure, and preview safety. | New regressions target actual loss/failure boundaries rather than only happy paths. |
| Quality gatekeeper: reproducibility | Exact baseline, pinned Pester, discovery failures, Windows execution, and live cleanup are checked separately. | Unit success is not presented as schema-mutation or distributed-concurrency proof. |

These perspectives agree on scoped deltas and schema traversal. They differ on
removing old APIs and simplifying schema provisioning: an aesthetically smaller
API is not sufficient justification for breaking callers or inventing forest
schema objects. Strategy therefore favors a compatible repair now and explicit
future design decisions where necessary. Delegated implementation reviews and
an independent final regression review supplement the primary review.

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
| Shared temporary log includes payloads | Confirmed. | Default optional logs use unique per-user files and count-only messages. Callers still control explicit log paths and their retention/permissions. |
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

## Verification Ledger

The ledger is sanitized. Exact targets, accounts, access methods, rollback
identifiers, and raw output stay outside GitHub and the public repository.

| Check | Result |
| --- | --- |
| Clean July baseline, Pester 5.7.1 | 94 passed, 0 failed, 6 integration not run. |
| Candidate local source gate | 204 passed, 0 failed, 8 integration not run; syntax, docs, atlas, and release gate passed. |
| Windows Server 2025 / Windows PowerShell 5.1 | 204 unit tests passed, including both confirmation choices; 8 integration tests excluded from that process. |
| Real-directory readiness | Ready without any schema modification. |
| Isolated live integration | 8 passed, 0 failed, 0 skipped, 0 failed containers. Separate fresh process after rollback preparation; no newly created test accounts remained. |
| Independent final regression review | One actionable CSV confirmation-scope regression found and fixed; both new tests fail against an in-memory regression mutation and pass against the fix. |
| Diagrams and atlas | Five Mermaid sources rendered successfully. All seven atlas flows and 34 nodes checked at desktop/mobile widths; no page errors or document overflow. Long labels wrap in both atlas variants. |
| Remote CI | See issue #13 and the PR checks for the exact pushed candidate; local validation is not a remote CI claim. |

## Remaining Limits

- Scoped deltas protect unowned values from the demonstrated same-DC stale-read
  loss. They do not implement compare-and-swap, locking, or same-prefix
  serialization. Conflicting same-prefix deltas may fail or merge undesirably.
- AD replication conflicts for nonlinked multivalued attributes remain an
  attribute-level concern. Pinning one operation does not coordinate separate
  writers on different DCs. Use one writer/DC policy or external coordination.
- Schema readiness is a schema legality check, not proof of object ACL rights,
  replication convergence, or successful future writes.
- CSV preflight retains prepared rows in memory and lengthens the read-to-write
  interval. It deliberately prioritizes avoiding predictable partial writes;
  very large imports need memory/runtime measurement before scale claims.
- Schema enablement code is unit-tested, not applied to the live forest in this
  pass. The eight-case integration suite is not a seeded-scale campaign.
- Logs are payload-minimized, not an audited secure logging subsystem. Explicit
  paths, platform file permissions, retention, and error/transcript handling
  remain operator responsibilities.

## Public Documentation Boundary

The final privacy scan found exact target/access identifiers and raw directory
screenshots in an older validation record that was already on public main.
The current candidate replaces that page with aggregate historical results and
removes six raw screenshot/HTML attachments. Private originals were preserved
outside the public tree. A separate commit keeps this cleanup independently
reviewable. This is not a new live-evidence publication or a claim that older
Git history has been scrubbed. History rewriting, artifact/cache cleanup, and
any necessary credential rotation require a separate coordinated decision.

## Primary References

- [Set-ADUser](https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-aduser?view=windowsserver2025-ps): combined operation ordering removes before adding.
- [drink schema attribute](https://learn.microsoft.com/en-us/windows/win32/adschema/a-drink): standard schema metadata; runtime metadata remains authoritative.
- [Attribute characteristics](https://learn.microsoft.com/en-us/windows/win32/ad/characteristics-of-attributes): nonlinked multivalue replication limitations.
- [Updating the schema cache](https://learn.microsoft.com/en-us/windows/win32/ad/example-code-for-updating-the-schema-cache): explicit RootDSE refresh pattern.
- [top class](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adsc/041c6068-c710-4c74-968f-3040e4208701): schema-root inheritance behavior.

## Delivery Boundary

October work is layered on the unmerged July candidate. Keep PR #12 and the
October review separately attributable. The privacy-only cleanup is also
proposed independently against main in [PR #14](https://github.com/jonathanweinberg/DrunkenAD/pull/14).
Issue #13 remains open for review; this change does not authorize a merge,
issue closure, tag, or release.

Implementation commit: `9191581`. Privacy commit: `aa335b7` on the October
branch, applied independently as `90d0da1` on the privacy-only branch.
