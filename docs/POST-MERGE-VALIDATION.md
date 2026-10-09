# Post-Merge Review And Release Evidence Matrix

Updated for Review 5, 2026-10-08. This page records public requirements,
sanitized evidence and remaining decisions. Detailed reviewer notes, original
logs/XML, source hashes and the earlier chronological dossier are retained
in the private review collection, outside this repository. No raw lab output
or credentials belong in public issues, pull requests or documentation.

Tracking: [issue #16](https://github.com/jonathanweinberg/DrunkenAD/issues/16),
[test isolation #18](https://github.com/jonathanweinberg/DrunkenAD/issues/18),
[fixture recovery #20](https://github.com/jonathanweinberg/DrunkenAD/issues/20),
[PR #17](https://github.com/jonathanweinberg/DrunkenAD/pull/17), and the separate
[encoding PR #19](https://github.com/jonathanweinberg/DrunkenAD/pull/19).
The manifest's `0.13.2` is not a published-release receipt. Release/tagging
remains held; neither this matrix nor a green check authorizes publication.

## Current Evidence Summary

| Evidence Class | Candidate And Observed Result | Limit |
| --- | --- | --- |
| Encoding-only source review | `083e384`: independent gatekeeper found no blocking issue in the five-file extraction from `55906b1`. | No merge or support-scope approval is implied. |
| Encoding regression | Main plus the added tests: 9 passed / 12 failed. With the extracted fix: 21 passed / 0 failed. | Failing baseline demonstrates malformed bytes reaching a mocked directory boundary, not a live AD call. |
| Encoding local and CI | `083e384`: LF/CRLF local gates each 370 passed, 0 failed/skipped, 12 integration cases excluded. Five hosted checks passed, including Windows PowerShell 5.1. | Offline/hosted evidence is not native directory or authentic Excel certification. |
| Previous completed native suite | `038013b`: 18 passed, 0 failed, 1 explicit capacity-prerequisite skip, with cleanup. | Partial, not all proposed cases passed. Setup rejection did not exercise large-range retrieval. |
| Expanded native checks | Same production source as `038013b`: identity/lookup, prompts, failure accounting, rename/move, projection, no-op and seven endpoint forms. See the [bounded receipt](POST-MERGE-LIVE-EXPANSION.md). | One controller and runtime; not multi-DC, delegated-actor or compatibility-mode proof. |
| Last actual AD attempt | `07d26b9`: interrupted by a private launcher/Pester variable collision. Fixture deletion and independent absence/parent checks completed. See the [attempt receipt](SINGLE-DC-VALIDATION-2026-10-08.md). | No completed live aggregate; eight new native projection-boundary cases never ran. Approval is consumed. |
| Later synthetic preparation | Corrected launcher skip preflight and eight watchdog controls passed without AD. | Preparation only; no authorized live retry occurred. |
| PR #17 checkpoint | `3314d38` had five passing CI checks. Its production module matched `038013b`; later capacity work changes tests, not production code. | Source identity supports relevance of old receipts, not a fresh new-head live pass. |
| Replacement capacity case | Bounded production Remove/Add characterization is implemented behind a separate opt-in. | No fresh accepted/rejected count, native preservation result or cleanup receipt exists for it. |
| Fixture ownership recovery | Private intent/GUID journals, verified target/parent binding and GUID-only cleanup have offline helper and actual-hook fault-injection coverage. | No surviving-controller or fresh native interruption-recovery receipt is implied. See [fixture guidance](TESTING.md#fixture-ownership-and-interruption). |

Do not sum counts across candidates, deliberately repeated runs or evidence
classes. A Pester pass with a partial wrapper result is still partial. A
recognized setup skip, interruption or missing exporter is an Evidence Gap.

## Review Item Matrix

| Review 5 Recommendation | Disposition |
| --- | --- |
| Split and merge encoding repair | Extracted as PR #19, with independent review and exact-head checks. Merge awaits explicit owner authority. PR #17 and issue closure remain separate. |
| Replace fixed large-set prerequisite | Adapted to a bounded fixture-specific capacity bracket with real companion removal, full-set and replication-metadata preservation. No universal ceiling claim. Range retrieval remains separate and unproven. |
| One writable DC per writer | Corrected to one **common** writable DC across every producer of the affected objects' nonlinked `drink` attribute, including different prefixes. See [operating guidance](OPERATIONS.md#before-any-live-write). |
| Same-prefix writers always silently merge | Rejected as a general contract. Stale deltas can fail, replace values or leave combined sets; external serialization is still needed. |
| Multi-DC cases become out of scope | Conditional proposal only. An accepted restriction can exclude scenarios from a support envelope, but cannot label their unexecuted evidence as passed. |
| Add a default missing-DC warning | Not adopted. Warnings can terminate automation under `WarningAction Stop`; a host string alone cannot establish role, common configuration or other writers. No API parameter or endpoint behavior changes. |
| Keep evidence write-ups out of public docs | Detailed chronology and raw receipts are private. This concise public matrix retains requirements and limitations; stable links to sanitized receipts remain. |
| Illustration size concern | Retain the artwork the owner explicitly requested. Keep the illustrated overview and detailed Mermaid flows; no removal is inferred from the review's size observation. |
| Import the four external probe scripts | Awaiting original files. Descriptions and independently written tests are not an exact reproduction of that corpus. |
| Declare 0.13.2 scope and tag | The [restricted proposal](SINGLE-DC-ACCEPTANCE-PROPOSAL.md) awaits owner acceptance; tagging remains explicitly held. |

## Scope And Evidence Discipline

- Keep unit/CI, documentation, read-only inspection, synthetic launcher and
  fresh native-AD evidence distinct. Bind each receipt to exact source and
  runtime; a changed test suite needs its own result.
- Use a fresh process and prove native AD command provenance for native claims.
  Mocked functions or compatibility proxies are not native evidence. Default
  units must not initialize AD during integration discovery.
- Every live run needs new explicit scope, verified rollback prerequisites,
  bounded fixture ownership, private output, a reviewed timeout and independent
  cleanup. Historical approval markers cannot authorize a retry.
- Do not mutate schema, DNS, ACLs, infrastructure, existing users or seeded
  campaigns under a one-user integration allowance. Each requires its own scope.
- No issue closure, merge, tag, release, install or reduced acceptance scope is
  implied by a reviewer recommendation or absent response.

## Specific Design Adjudications

### NetBIOS Domains Are Not Short DC Names

Explicit endpoint forms remain preserved. A single-label input can denote a
short DC hostname or a NetBIOS domain; blanket rewriting would break routing
intent. Omitted/domain-DNS selection pins the operation's context, not all
future operations. Aliases and domain names do not prove a stable physical DC.
Use the common actual writable DC hostname for coordinated producers and
coordinate failover; peer readers and replicated projection inputs can lag.

### Concurrency And Capacity

The native missing-Remove/duplicate-Add observations are consistent with
[Microsoft's permissive-modify control](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/49cdb1e3-3baa-4c7c-8cde-7c26b13d3ba7),
not proof that every runtime uses it or that every conflict is ignored.
An individual AD modify and the module's read/plan/confirm/write workflow are
different boundaries. CSV's final delta comparison narrows a race; it is not
a lock or an atomic compare-and-swap.

The failed 1,602-value seed established neither an exact limit nor that larger
sets are impossible elsewhere. Storage depends on configuration, other object
contents and request shape. Windows Server 2025 alone does not establish
active [32K pages](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/32k-pages-optional-feature).
Changing database/schema settings is not a test workaround. The replacement
[capacity protocol](TESTING.md#bounded-capacity-characterization) reports a
bounded accepted/rejected bracket; no rejection within the bound is a gap.

### Three Reads: Cost Versus Consistency

CSV resolves identities during whole-input preflight, refreshes before
confirmation, then rechecks the approved delta before mutation. Retain that
order and GUID-based refresh. Any batching/cache optimization needs explicit
freshness semantics and real performance evidence; it must not silently remove
operator-approval checks or claim atomicity across CSV rows.

### Logger Safeguards Versus Complexity

Keep private bounded default logs, caller-managed explicit paths, linked-path
rejection, payload-free records, preview suppression and nonterminating logging
failures. GUIDs remain sensitive. Simplification needs equivalent tests;
enterprise profile behavior remains a separate unexecuted lane.

### Nonbreaking Pre-1.0 API Proposal

Preserve exported commands, identity parameters, status aliases, invariant
projection formatting and return shapes. A new encoding parameter, automatic
code-page guessing, endpoint rejection or public export is not needed for the
strict decoder repair. Fix docs without silently changing behavior.

## Numbered Live Case Matrix

The 26 review proposals are not the count of Pester tests. The integration
suite discovers 27 cases: 12 baseline and 15 Tier 1, including eight projection
boundary combinations. Capacity additionally requires its own opt-in. See
[testing](TESTING.md) for selection, bounds and cleanup. These rows preserve
all proposed objectives, including those without an executable test.

Gate classification is unchanged: cases 1-13 and 22-23, plus case 24's
Windows PowerShell 5.1/RSAT lane, are recommended 0.13.2 gates (`G`). Cases 14,
24's other advertised modes and 25 are conditional support gates (`C`), with
explicit scope deferral required if not claimed. Cases 15-21 and 26 are planned
pre-1.0 evidence (`D`), promoted to gates when claiming those environments or
current throughput. See G0-G5 below; no proposed restriction is accepted here.

### Tier 1: Single Writable DC

| Case | Required Evidence | Current Disposition |
| --- | --- | --- |
| 1. Remove already-absent value | Controlled stale mixed delta; actual error/success and full-state preservation, without treating missing Remove as a lock. | Native remaining delta applied when absent Remove was tolerated; broad conflict guarantees rejected. |
| 2. Add already-present value | Exact duplicate, real companion removal, one stored value and unrelated-state check. | Native duplicate Add was tolerated; candidate-bound result, not a universal runtime rule. |
| 3. Case-variant collision | Separate case-only replacement from coexisting variants; ordinal readback. | Native replacement/collision observations recorded; AD equality is not .NET ordinal equality. |
| 4. Length boundaries | Actual schema limit on complete prefix plus payload, exact/over-limit readback and Unicode counting. | Generic native boundaries recorded; no universal collation or every-runtime guarantee. |
| 5. Non-ASCII round-trip | Independent ordinal strings across owned write/read paths; no substitution and defined encoding. | Native synthetic Unicode cases recorded; authentic exporter/runtime lanes remain separate. |
| 6. Every identity type | Correct object for public identity-bearing commands; ambiguous matches cause zero mutation. | 96 combined identity/literal-lookup public checks for cases 6-7 passed. CSV remains SamAccountName-only. |
| 7. LDAP special characters | Literal metacharacters, wildcard decoy and independent unchanged-state checks. | Included in the 96 checks above; setup rejection is not lookup proof. |
| 8. Large multivalue retrieval | Complete retrieval beyond the effective range boundary; replace all stale owned values, preserve every unowned value. | Seed rejected before retrieval. Still unproven. New capacity characterization is a different objective, not closure of case 8. |
| 9. Real no-op | Repeated CSV/projection has unchanged state and same-DC drink metadata version. | Native no-op checks passed. Deliberately skipped blank rows are not NoChange results. |
| 10. Interactive confirmation | Real Yes/No/All choices, status/prompt counts and paused-prompt drift checks. | Four primary ConsoleHost confirmation scenarios passed; additional prompt-attested rename/failure scenarios belong to case 11. CSV still has a final-read-to-write race. |
| 11. Mid-import failure and rename/move | Deleted/denied row stops, accurate progress, previous writes retained, pending rows untouched, GUID refresh; test after-final-refresh rename/move separately. | Before-refresh and during-prompt scenarios passed. After-final-refresh rename/move remains unexecuted and needs separate authorization or an explicitly accepted scope decision. No atomic rename or whole-file rollback promise. |
| 12. Server forms | Per-call target trace and write origin; distinguish syntax, routing and physical stability. | Seven forms passed on one DC. Alias unavailable; multi-DC locator/failover unproven. Review 5 identifies the omitted fourteenth stub input as bracketed loopback IPv6; original script still absent. |
| 13. Excel-produced CSV | Original exporter/version/locale, bytes, delimiter/BOM and exact supported-Unicode round-trip; malformed data fails before AD. | [Intake protocol](EXCEL-CSV-VALIDATION.md) and synthetic source prepared. Original Excel export pairs absent; synthetic bytes and Export-Csv do not certify Excel. |
| 14. Awkward projection sources | Dates, multivalues, separator-bearing DNs, blanks, cultures and claimed runtime/object types; exact/over-limit behavior. | Eight native positive checks and offline boundaries passed. Eight later native boundary combinations remain unexecuted after interruption; PS7/compatibility unproven. |

### Tier 2: Multiple Controllers

| Case | Required Evidence | Current Disposition |
| --- | --- | --- |
| 15. One DC per operation | Trace selection and subsequent schema/user/write calls with alternate DCs available. | Units and single-DC trace support reuse. Multiple-choice locator stability remains unexecuted. |
| 16. Lagging target DC | Approved controlled lag, both DC states/metadata, error/loss and convergence. | Not executed. Common writer-DC policy can bound an accepted envelope, not prove this scenario. |
| 17. Distinct prefixes across DCs | Coordinated writes before replication, complete sets before/after convergence. | Not executed. Whole-attribute replication can affect different prefixes; one no-loss trial would not guarantee safety. |
| 18. Read-only DC | Permitted reads and exact write failure/referral/no-unexpected-mutation evidence. | [Set-ADUser excludes RODC writes](https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-aduser?view=windowsserver2025-ps#notes). Module-specific negative-path behavior is untested, not a supported write mode. |

Multi-DC hardware is unavailable in the owner's current lab. These are proposed
scope exclusions, not accepted deferrals or passed tests. No new cloud lab,
DNS alias, replication change or infrastructure purchase is authorized.

### Tier 3: Schema, Permissions, And Environments

| Case | Required Evidence | Current Disposition |
| --- | --- | --- |
| 19. Schema enablement | Preview/WhatIf without mutation, guarded Apply with all Expected values, immediate write, repeat AlreadyReady and claimed peer propagation. | No fresh schema-apply receipt. Single-DC subset needs separate disposable-schema authority and recovery; peer portion needs topology. |
| 20. Auxiliary-class readiness | Actual auxiliary-only inheritance without leftover direct allowance, graph/readiness and representative write. | Unit graph cases only; no custom-schema live proof or authority to create the fixture. |
| 21. Extended schemas | Existing graph resolves, truthful readiness and representative write in each claimed environment. | Read-only nine-class/13-edge RFC-containing graph observed; no Exchange markers. Partial, not Exchange or auxiliary-only certification. |
| 22. Least-privilege delegation | Non-admin actor, allowed inside write, denied outside row, accurate partial-import counts and unchanged forbidden state. | Unexecuted. A privileged actor with object-specific deny is not this role test. |
| 23. Read-only account | Reads/WhatIf work; writes fail for permission with no partial mutation or misleading log failure. | Unexecuted. Requires a separately provisioned actor and explicit fixture scope. |
| 24. Supported runtimes | Candidate-bound units and live baseline per claimed member-host RSAT/5.1, PS7 native and Windows-compatibility lane. | Native live 5.1 on the DC observed; hosted CI is not member-host or deserialized AD-object proof. |
| 25. Enterprise logging profiles | Approved redirected/OneDrive/junction profiles; correct log or best-effort refusal without affecting AD outcome. | Synthetic guards exist; representative Windows profile receipts absent. |
| 26. Scale | Authorized current 3,000-user run, complete counts, ADWS errors, memory, elapsed phases and read-only DC metrics. | Historical campaign is not current importer throughput. No fresh resource/scale receipt. |

## Recommended Release Decision

Keep release/tagging held. The [single-DC proposal](SINGLE-DC-ACCEPTANCE-PROPOSAL.md)
names a possible restricted envelope and remaining receipts; it does not
approve itself. A common writer DC cannot turn untested cases into success.

| Gate | Required Evidence / Scope | Current Disposition |
| --- | --- | --- |
| G0: Exact candidate and local safety | Strict decoding and projection adjudication/regressions, fresh release gate with Pester 5.7.1, four runtime/OS CI lanes plus docs, manifest/export/FileList/help parity. | Encoding-only `083e384` passed its scoped review/local/CI checks. New PR #17 test/doc changes require their own exact-head gates; earlier counts are not inherited. |
| G1: Authorized baseline and expanded live | Final candidate's twelve baseline cases plus selected Tier 1 and authorized expanded assertions, no failed/unexplained skipped/container errors, independent readback and cleanup. | Earlier 18-pass/one-skip suite is partial; later attempt interrupted. Fresh completed receipt is missing, including the new native boundaries and replacement capacity scenario if selected. |
| G2: Data integrity and operator behavior | Cases 1-13 and 22-23, case 12's single-DC portion with multi-DC limits retained, and case 24's native Windows 5.1/member-RSAT lane. Data loss, invalid-input access, inaccurate approval or failure accounting block recommendation. | Significant scoped evidence exists; large-range retrieval, after-final-refresh move, alias, authentic exporter, role and member-host gaps remain. Narrowing these gates requires explicit owner acceptance. |
| G3: Conditional support surface | Case 14 real-source/boundary claims, claimed PS7 modes in 24, enterprise profiles in 25 and current throughput claims in 26. | Native positive projection is separate from unexecuted boundaries/runtime/profile/scale. A known defect cannot become a deferral without an explicit supported-scope decision. |
| G4: Pre-1.0 program | Cases 15-21 and 26 by default, plus explicitly deferred conditional lanes. Record owner, prerequisites, receipt ID, revisit milestone and any promotion to release blocker. | Proposal only; no owners/milestones or risk acceptance are invented. Case 21 is partial RFC-containing readiness, not Exchange/schema-mutation certification. |
| G5: Owner release hold | Explicit owner decision after evidence and homepage artwork review, separate from technical checks. | Held. No merge, issue closure, tag or release follows automatically. |

Before a recommendation, reconcile exact candidate identity, independent
review, local/CI checks, explicitly accepted scope, required fresh live
assertions and cleanup. An incomplete aggregate cannot be replaced by a
source-hash comparison. Keep original exporter, actor, schema, runtime,
profile and scale gaps visible with owners and revisit criteria when accepted.

The encoding-only PR can be decided separately after its focused review and
checks; it need not inherit artwork, test-harness or live-capacity changes.
All issues stay open unless the owner separately requests closure.

## Reference Index

- [Data semantics](DATA-STORE.md), [operations](OPERATIONS.md),
  [testing and capacity bounds](TESTING.md), [CSV contract](HOW-TO-INGEST-CSV.md).
- [Acceptance proposal](SINGLE-DC-ACCEPTANCE-PROPOSAL.md),
  [interrupted attempt](SINGLE-DC-VALIDATION-2026-10-08.md),
  [expanded native evidence](POST-MERGE-LIVE-EXPANSION.md),
  [authentic Excel intake](EXCEL-CSV-VALIDATION.md).
- [Scoped writer](../DrunkenAD/Private/WriteOperation.ps1),
  [CSV reader](../DrunkenAD/Private/CsvMapping.ps1),
  [CSV importer](../DrunkenAD/Public/Import-ADUserDrinkCsvData.ps1),
  [schema resolver](../DrunkenAD/Private/SchemaStatus.ps1),
  [integration tests](../tests/DrunkenAD.Integration.Tests.ps1),
  [selection guards](../tests/Release.Unit.Tests.ps1).
