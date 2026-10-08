# Post-Merge Review And Release Evidence Matrix

Date: 2026-10-08. Source baseline: `main` at
`55906b1087a258a09dffdd238fdecb7b87b7cc9b` (`55906b1`). The manifest declares
`0.13.2`; a manifest version is not evidence of a published release.

Tracking: [issue #16](https://github.com/jonathanweinberg/DrunkenAD/issues/16).
The final fixed candidate, including the work below, must receive live
validation. A run of the old `55906b1` alone cannot satisfy release acceptance.

### Current Evidence Summary

This table supersedes baseline-only gap statements where explicitly noted.
The local release gate passed with Pester 5.7.1 on PowerShell 7.6.3: 379 passed,
zero failed, and 19 integration cases excluded (12 baseline plus seven Tier1).
This includes all new byte-decoding, projection, help, and endpoint regressions.
The atlas rendered on desktop and mobile with seven working flows, 34 nodes,
no horizontal overflow, and no browser errors. Six Mermaid flows rendered.
These are local source/visual checks, not final-candidate CI or live proof.

| Item | Latest Evidence And Decision | Remaining Receipt |
| --- | --- | --- |
| CSV defect and repair | Reported local byte testing confirmed real bytes `ren` plus `0xe9` were accepted with replacement at baseline. Current [CSV reader][CSV] now uses strict exception-fallback decoding: UTF-8 by default and BOM-selected UTF-8/UTF-16/UTF-32, preserving both byte orders where applicable. [UT] adds actual-byte positive/negative fixtures, including malformed Unicode, invalid unmapped data, literal paths and empty input. | Final-candidate unit/CI and live case 5/13 receipts. Source repair is inspected, not a fresh pass here. |
| Correct encoding contract | No blanket U+FFFD ban and no broad Encoding parameter. Validly encoded U+FFFD is legitimate input and is included in positive fixtures. Invalid bytes fail before AD access; already-corrupted valid Unicode cannot reliably be detected or repaired. | Document exact supported encodings and verify no legacy-codepage guessing. |
| Projection adjudication | Reported unit evidence found no production bug: on PowerShell 7.6.3, helper string casts give equal en-US/de-DE dates/numbers while a `.ToString()` control changes with culture. Six added parameter-expanded regressions in [WT] cover typed values, multivalue/DN strings and blank-source clearing. Production projection code is unchanged. Preserve existing invariant general-format dates; do not introduce ISO formatting as an unsolicited compatibility change. | Execution receipt pending for the reported unit run; final gate and real AD/native/compatibility case 14 remain distinct. |
| Tier 1 implementation | The current integration file adds seven opt-in areas for numbered cases 1, 2, 3, 4, 5, 8, 9 in existing [IT], using its one owned disabled temporary user. Both integration opt-in and `DRUNKENAD_RUN_TIER1=1` are required; baseline twelve-case scope is retained. | No live run reported. Record baseline and Tier1 executed/skipped counts separately; new tests are coverage, not proof. |
| Documentation/endpoint corrections | About-topic and DATA-STORE blank retention, alias-pinning prose, and CSV endpoint wording are corrected. A help regression and explicit NetBIOS pass-through testcase were added; no production endpoint rewrite. | Included in the passing local gate; remote matrix and live endpoint evidence remain separate. |
| Expanded live approval | User reports direct authorization for up to six disabled temporary users, one group and two OUs inside the existing lab test OU; only owned-object attributes, renames, moves and temporary permissions. Verify snapshot and cleanup. No schema, DNS, infrastructure, existing-user or campaign mutation. | Bind execution to final fixed candidate, exact allowed fixtures and sanitized per-case receipts. Execution receipt pending; this local review ran no live commands. |
| Published release / owner hold | Reported release-state verification identifies latest GitHub release `v0.13.1`, published 2026-05-15. Owner explicitly declined release/tagging for now, pending review of homepage imagegen artwork versus Mermaid presentation. This is an owner hold, not an unanswered approval question. | No tag/release until owner explicitly lifts the hold after review. Live authorization does not authorize publication or issue closure. |
| Artwork refresh, separate scope | Git history confirms six original imagegen PNG replacements in `43fccb3`, then five README thumbnail removals in `c2949ef`. The owner approved refreshing the original illustrated style with corrected content, restoring thumbnails, and keeping Mermaid in detailed docs. | Generate and inspect the corrected artwork; restore image-forward presentation without obsolete behavior or test-result claims. Release remains held. |

Cases requiring schema changes, multi-DC infrastructure preparation, enterprise
profile changes or a 3,000-user campaign are not authorized by the expanded
fixture allowance. Even within six users/one group/two OUs, each scenario must
remain inside the existing approved parent and clean up only objects it owns.

## Scope And Evidence Discipline

This is a sanitized adjudication of the supplied
"DrunkenAD Code Review: Post-Merge Assessment" and its numbered live cases
1-26. The attachment is reviewer input, not an authoritative specification,
release approval, or permission to mutate a directory. Its proposed outcomes
are hypotheses until checked against the implementation, platform contract,
and an authorized exact-candidate run. A passing stub test proves the modeled
behavior, not the corresponding Active Directory behavior.

The baseline code, test bodies, contribution guidance, release scripts,
workflows, and current operator documentation were inspected. No applicable
`AGENTS.md` was found in the repository or checked ancestor locations.
Current execution evidence is summarized above and in issue #16; the matrices
below retain baseline observations separately from later checks. The rollback
point and a Windows Server 2025 / Windows PowerShell 5.1 test environment were
reverified read-only. No live case is passed until its assertions and cleanup
actually complete. Subsequent candidates must be revalidated. No release or
issue closure is authorized.

| Evidence Label | Meaning | May Support A Release Pass? |
| --- | --- | --- |
| Inspected | Source/test/docs behavior checked in this review. | Static contract only; not execution success. |
| Reported | Attachment or dated repository ledger says a check ran. | Only after its receipt, candidate, environment, and scope are reconciled. |
| Pending | Required execution or receipt absent from this review. | No. Missing authorization, topology, or permissions is an Evidence Gap. |
| Deferred | Explicitly proposed for pre-1.0 or a narrower support claim. | Not a pass; needs owner, scope restriction, and revisit trigger. |
| Failed / Blocked / Skipped | A future run fails, cannot establish prerequisites, or omits assertions. | Never silently promote to Passed. |

### Baseline Receipt Ledger

| Item | Evidence Available Here | What Is Still Needed |
| --- | --- | --- |
| Candidate and tree | Read-only Git inspection confirmed `55906b1`; working tree was clean at intake. | Final release candidate SHA, module/input hashes, and clean-candidate check after all candidate changes are finalized. |
| Reviewer runtime | Attachment reports hash-verified portable PowerShell 7.6.6 and Pester 5.7.1. | Sanitized runtime provenance and receipt hashes. No installation or reproduction here. |
| Reviewer full gate | Attachment reports 349 passed, zero failed, 12 integration skipped. | Candidate-bound Pester result, discovery/container outcome, exit status, and skipped/not-run distinction. This is not a fresh local pass. |
| Earlier unit/live receipts | [October ledger][REVIEW] records several earlier counts; latest recorded live coverage applies to `7071a7d`, not this baseline. | Fresh candidate-bound live evidence. Do not combine different candidates' counts or treat the older ten-case run as twelve current passes. |
| CI and upload | Attachment reports five green checks and upload in run `37836783064`. [Workflow][CI] defines three Core OS lanes plus Windows PowerShell 5.1; separate docs workflow exists. | Remote run-to-SHA association, each job conclusion, runtime versions, and retained artifacts. Source inspection is not current CI verification. |
| CI artifact scope | Core lanes configure NUnit XML and upload with `always()`; missing files are ignored. The 5.1 lane has no matching XML/upload step at baseline. | Confirm actual Core XML presence, not just successful upload-step status; retain a 5.1 result/exit receipt separately. |
| CSV probes | Attachment reports 20 comparison files and 46 ms versus 16 ms on 3,000 rows. | Reproducible byte fixtures, hashes, runtime, exact assertions and timing method. Not an AD import benchmark or exhaustive CSV equivalence proof. |
| Endpoint probes | Attachment says 14 values; its displayed groups expand to 13 named inputs. | Complete probe manifest and per-input results. Preserve this count discrepancy instead of inventing an omitted input. |
| Release and issues | Attachment reports merged PRs #12/#15 and open #5, #7-#11, #13. Reported release-state verification subsequently identified latest GitHub release `v0.13.1`, published 2026-05-15; this pass is tracked by #16. Local manifest/changelog describe 0.13.2. | Retain remote-state receipt. Release/tagging is explicitly on owner hold for artwork review; no inferred issue closure. |

## Review Item Matrix

### Previously Reported Fixes To Retain

All rows below are inspected implementation/coverage, not fresh test passes.

| ID / Reviewer Item | Current Code And Test Evidence | Acceptance Receipt / Remaining Gap | Disposition |
| --- | --- | --- | --- |
| R1: Generic examples owned `Profile-` | Generic examples now use application prefixes; [ownership tests][OWN] parse examples and compare them with default projection. Shipped CSV uses `CsvProfile-`/`CsvRouting-`. | Exact-candidate ownership suite plus twelve-case integration, including both execution orders. Custom maps still require ownership review. | Retain; release regression gate. |
| R2: Blank CSV cells cleared by default | [CSV mapping][CSV] only inserts empty namespace replacements with `ClearBlankNamespaces`; [write tests][WT] cover all-blank skip/opt-in clear; [integration][IT] has both modes. | Preserve existing owned data by default, clear only opted-in blank namespaces, retain unrelated values. Correct stale prose in D1 below. | Retain compatibility; release gate. |
| R3: Truncated/extra-field records | `Read-DrunkenADCsvRows` validates record widths before context creation; [unit tests][UT], `CSV record structure`, cover short, hash-prefixed short, long, and complete empty/multiline cells. | Malformed quoting, width errors, and invalid encoding must fail before any AD access. The missing-closing-quote probe is reported, not a dedicated checked-in regression at this baseline. | Retain and extend local regression coverage; release gate. |
| R4: Explicit servers rewritten | [schema resolver][SCHEMA] preserves explicit endpoints; [schema tests][ST] cover authoritative domain DNS matching, ports, IPv4/IPv6, short aliases, and invalid forms. | Cases 12/15; endpoint preservation is not proof of one physical DC behind an alias. See adjudication below. | Retain; do not reintroduce blanket rewriting. |
| R5: Stale confirmation | [importer][IMPORT] refreshes before approval and verifies ordinal Remove/Add sets after approval. [write tests][WT] exercise prompt-time owned/unowned drift and All choices. | Case 10 proves real-host prompting; case 11 proves failures. No lock or compare-and-swap is implemented after the final read. | Retain; release gate. |
| R6: Logger identity and warnings | [core logger][CORE] and [writer][WRITE] log canonical ObjectGUID/counts and best-effort warnings; [logging tests][LOGT] cover unavailable GUIDs and suppression. | No account names/payloads, no preview log writes, logging failure cannot turn an AD success into a reported failure. GUIDs remain sensitive persistent identifiers. | Retain safeguards; enterprise-profile evidence is case 25. |
| R7: Incomplete allowlist / duplicate CI tests | [runner][RUNNER] compares explicit top-level allowlist with discovered top-level files and rejects non-Passed overall results. [release tests][RT] cover omissions, additions, duplicates, child-process failures, and XML forwarding. CI invokes units once per lane through the release gate. | Fresh full gate, all platform conclusions, discovery/container health, and actual artifacts. [Testing guide][TESTING] still describes a separate unit execution in CI; reconcile prose. | Release process gate. |
| R8: Unterminated quotes silently merge users | Framework parser validates the same decoded text later passed to `ConvertFrom-Csv`; the reviewer reports rejection of a missing closing quote. | Add/retain executable unterminated-quote fixture, exact row-count/value assertions, zero-AD-access assertion. Before-header type/comments are not permission to discard hash-prefixed identities after the header. | Parser improvement supported by source; broader probe equivalence remains unverified. |

### Current Findings, Minor Items, And Process

| ID / Item | Adjudication And Current Coverage | Required Evidence / Decision | Priority |
| --- | --- | --- | --- |
| F1: Non-UTF-8 CSV corruption | Confirmed by reported actual-byte testing of `ren` plus `0xe9`. Strict Unicode decoding and byte-level fixtures are now present in [CSV]/[UT]; UTF-8 default, BOM-marked UTF-16/32 retained. No blanket U+FFFD ban or broad Encoding option. | Require final-candidate rejection-before-AD and valid Unicode receipts (cases 5/13). Do not label every plain Excel CSV Windows-1252: exporter version, locale, format, BOM, and actual bytes must be recorded. | Source repair inspected; release still gated on validation. |
| F2a: Fixes not released | 0.13.2 is declared in [manifest][MANIFEST] and [changelog][CHANGELOG]; reported release-state verification identifies latest GitHub release as v0.13.1 (2026-05-15). These are different evidence classes. | Assemble evidence without publishing. Owner explicitly holds release/tagging pending homepage artwork review; only a later explicit owner decision can lift that hold. | Owner-held, not an unanswered approval request. |
| F2b: Current code not live validated | Twelve baseline live cases and seven new opt-in Tier1 areas are present; no live execution reported for the final fixes. Expanded bounded authorization is now received, within the limits above. | Final fixed candidate, baseline twelve and applicable expanded cases executed with zero failures/unexplained skips/container errors, plus verified cleanup. Old 55906b1 evidence alone cannot close this gap. | Block recommended release pending receipts, not pending already-received bounded authorization. |
| M1: NetBIOS domain / aliases not pinned | Pass-through is confirmed by resolver structure; it does not query a domain's NetBIOS name. A single-label input can also be an explicit short DC hostname. Blanket classification would break the preserved-endpoint contract. | Keep explicit short host behavior. Cases 12/15 separately establish known domain, short host, and alias behavior; any future classification needs authoritative metadata and ambiguity handling. | Document limitation now; classifier redesign can defer. |
| M2: Three user reads per changed CSV row | [write tests][WT], `uses one schema check, one preflight resolve and two fresh reads per changed CSV row`, explicitly asserts the design. Reads serve different consistency boundaries; see tradeoff table. | Case 26 measures cost; case 10/11 regression receipts are mandatory before any optimization. 9,000 is a modeled count for 3,000 approved changed rows, not measured latency. | Preserve safety now; optimization deferred. |
| M3: Logger complexity and legacy-only automatic path | Automatic default-path opt-in is on `Update-ADUserDrinkAttribute -EnableLogging`; other supported writers expose explicit `LogPath`. [LOGT] tests retention, ownership, reparse rejection, preview, and error isolation. Reviewer line/test-block counts are not a defect measurement. | Retain protections and existing switch; case 25 checks normal enterprise profiles. Refactoring needs equal safety coverage and an explicit performance/maintenance benefit. | No simplification prerequisite for release. |
| M4: Public API / repeated identity declarations | Manifest has 12 exports; shared identity forwarding is private, while eight public identity-bearing commands retain explicit declarations for binding/help. "Three write entry points" describes overlapping setter APIs, not all commands capable of writes (CSV/projection/removal/demo also matter). | Preserve exports, parameter sets, wrappers, return shapes, and AutoConfirm. Adopt documentation-first pre-1.0 migration proposal below, without immediate warnings/removals. | Nonbreaking proposal; design deferred. |
| M5: Code/test size growth | Attachment reports module 1,130 to 1,492 lines and units 1,378 to 4,114 under its counting rules. Not independently recounted; parameterized test blocks are not executed test counts. | Reproduce base/ref, file selection, comment/blank rules before using as a metric. Prioritize measured complexity, risk, and maintainability over reducing counts. | Informational, not release blocker. |
| P1: All earlier risk gone / CI green | Too broad. Source contains scoped deltas and stronger input guards, but encoding, final-read races, same-prefix concurrency, cross-DC convergence, ACLs, and operational support remain distinct risks. | Use bounded claims: source repair, candidate-specific unit evidence, and authorized live evidence separately. No "nothing serious" conclusion from stub coverage alone. | Release language gate. |
| P2: Issues remain open | Attachment says #5 and #7-#11/#13 await evidence; [October record][REVIEW] distinguishes implementation and validation. Current issue states were not queried here. | Map each issue's acceptance to sanitized receipts, identify intentionally deferred items, and obtain closure approval. Never close based solely on merge or this review. | Process follow-up, not blanket closure. |
| P3: Run suite then tag / suggested order | Useful prioritization, not authority. Tier 1 alone cannot prove two-DC pinning, enterprise profiles, or all runtimes. A new fix changes the candidate to validate. | Gates below supersede automatic "then tag" wording; owner must accept any restricted-scope deferrals and authorize release separately. | Release decision required. |
| D1: Stale current documentation | Corrections address about-topic default clearing, DATA-STORE blanket alias pinning, CSV endpoint wording, and the different blank-clearing contracts for projection and CSV. Help and NetBIOS regressions are present. | Retain the corrected projection/CSV distinction and validate the final candidate in CI. | Local docs/help/endpoint gate passed. |
| D2: Projection typed-source expectations | Reported unit evidence finds no bug on PS7.6.3: existing PowerShell string conversion is invariant for tested dates/numbers across en-US/de-DE; `.ToString()` control differs. Six new [WT] cases are inspected; [PROJ] unchanged. | Preserve current general-format invariant dates, not ISO. Execution receipts pending for the reported unit run and final gate; case 14 still tests actual AD/native/compatibility sources. | Hypothesis not sustained as a production defect; regression coverage improved. |

## Specific Design Adjudications

### NetBIOS Domains Are Not Short DC Names

Microsoft explicitly permits NetBIOS names for both a domain and an individual
directory server in [Get-ADRootDSE's Server contract](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adrootdse?view=windowsserver2025-ps#-server).
Therefore a dot-free string, capitalization, or the server that answered one
RootDSE query cannot establish the caller's intended name category.

The current resolver compares a DNS-shaped name converted to `DC=...` labels
with RootDSE `defaultNamingContext`. An omitted value or a matching domain DNS
name is replaced with `dnsHostName`, preserving the supplied port. Other
explicit inputs remain unchanged. A single-label DNS domain could also match
that comparison; the precise rule is metadata equality, not dot count.
There is no general authoritative NetBIOS-domain classification at baseline.

| Input Category | Baseline Contract / Gap | Acceptance |
| --- | --- | --- |
| Omitted/empty or authoritative domain DNS name, including case/trailing dot and valid port | RootDSE discovery followed by selected hostname reuse. | Same selected DC for subsequent schema/user/write operations; original discovery is a separate phase. |
| Explicit DC FQDN or verified short DC name | Preserved, including valid supplied port. Short-name resolution still needs environment evidence. | No silent rewrite to an unrelated RootDSE hostname; successful intended-host access or clear endpoint/authentication failure. |
| Known NetBIOS domain name | Normally preserved where it does not equal the DNS-domain metadata comparison; locator behavior remains an operational gap. | Record resolved targets, do not claim host pinning. Use a verified actual DC hostname for coordinated writers. |
| DNS alias, tunnel, IPv4, bare/bracketed IPv6 | Explicit input preserved. Syntax acceptance does not promise reachability, authentication, write eligibility, or physical-server stability. | Retain routing/port intent; document unsupported combinations. An alias or proxy can change physical targets even when the string is constant. |
| Invalid port / malformed bracketed address | Validation precedes RootDSE access. | Deterministic failure with zero directory calls. |

A future enhancement could consult authoritative domain metadata and distinguish
it from an explicit host, but needs a reviewed ambiguity policy and tests for
collisions, child/single-label domains, lookup failure, permissions, ports, and
compatibility. Do not implement a heuristic in this release merely because
the reviewer supplied a NetBIOS example. Rewriting every explicit endpoint to
RootDSE's answer would undo an intentional compatibility repair.

### Three Reads: Cost Versus Consistency

These are three AD user reads, not three disk reads of the CSV. The CSV text is
captured once and structurally parsed before conversion from that same snapshot.

| Stage | Safety Purpose | Consequence If Removed |
| --- | --- | --- |
| All-row preflight resolution/length validation | Detect a later invalid identity or overlength row before any mutation; capture GUID/DN. | Avoidable partial imports can return. |
| Refresh before ShouldProcess | Present counts from a current row plan, not from possibly old whole-file preflight. | Approval can describe stale changes. |
| Refresh after approval, compare exact Remove/Add sets | Reject owned-delta drift during prompting while tolerating unrelated namespace changes. | Approved and executed deltas can diverge. |

For a completed invocation with `P` prepared rows and `A` approved changed
rows, modeled user-read calls are `2P + A`: one preflight plus one pre-prompt
read per prepared row, and another for each approved change. Thus 3,000 all-
changed, approved rows imply about 9,000 user reads, excluding schema queries,
writes, read-back verification, and retries outside the importer. All-no-op,
declined, or WhatIf rows need two; skipped blank rows need none. Early failure
changes the count. `Confirm:$false` still uses the final validation path even
when the last two reads are adjacent.

Keep this behavior for the safety release. Consider removing/coalescing a read
only after case 26 measurements and a separately reviewed consistency contract,
including prompt/no-prompt, Yes/No to All, GUID refresh, no-op, and failure
counts. The last read still leaves a race before `Set-ADUser`; three reads are
neither serialization nor an atomic conditional update.

### Logger Safeguards Versus Complexity

| Safeguard At Baseline | Reason To Retain | Residual Gap |
| --- | --- | --- |
| Per-user default path; no shared-temp fallback | Avoid accidentally sharing logs across users. | Cannot assume every enterprise profile resolves to a usable private path. |
| Two owned files, each at most 1 MiB; ownership header; path mutex | Bound retention and coordinate rotation without deleting arbitrary files. | Not a general audit service or a complete filesystem-race defense. |
| Reparse/symlink rejection on file and ancestors | Avoid following redirected paths into unintended targets. | Can deliberately refuse legitimate junction-backed profiles; case 25 must record this visibly. |
| Counts, session, canonical GUID; no attribute payload/account names | Correlate outcomes with reduced data exposure. | GUID is not anonymous; permissions/retention still matter. Public receipts must replace it with a synthetic token. |
| WhatIf exits before logging; failure warns separately | Preview cannot rotate files; successful AD writes stay successful when logging fails. | Suppressed warnings can make missing log entries less visible. A Written result does not prove a log entry exists. |
| Explicit paths stay caller-managed | Preserves existing cross-command log option without hidden rotation. | Same link guard applies; caller must manage access and retention. |

Keep the legacy logging switch and tests. Complexity reduction is a maintenance
proposal, not permission to remove guards. Do not add an export simply to make
the convenience default reachable everywhere. Normal-profile rejection should
be documented with a vetted non-linked explicit path option, not silently
bypassed, and any new path allowance needs a separate filesystem-risk review.

### Nonbreaking Pre-1.0 API Proposal

This is a proposal only: no export is deprecated or removed by this document,
and no runtime warning or new default behavior is introduced.

| Existing Surface | Preferred Migration Direction | Compatibility Conditions |
| --- | --- | --- |
| `Get-AdUserDrinkPrefixedData` | `Get-ADUserDrinkData -Prefix` | Verify identity binding, literal prefix semantics, output/empty shapes, and error behavior. |
| `Set-ADUserDrinkPrefixedData -PrefixMap` | `Set-ADUserDrinkData -DataMap` | Preserve map semantics, confirmation, WhatIf, endpoint intent, logging, and string-array PassThru. |
| `Update-ADUserDrinkAttribute` | Generic setter with an explicitly converted data map; AutoConfirm intent maps to `Confirm:$false` | Document array-to-map rules and explicit Confirm precedence. `EnableLogging` has no drop-in generic equivalent; retain wrapper until a supported logging migration exists. |
| `Invoke-ADUserDrinkDataDemo` | `Set-ADUserDrinkProjection` | Verify default projection, identity options, preview and summary return contracts. |
| Explicit identity parameters and status aliases | Retain at the public boundary; share internals where useful | Help/binding discoverability and downstream result consumers outweigh cosmetic deduplication. CSV remains SamAccountName-only. |

Before 1.0, publish a maintainer-approved migration table with examples and
compatibility tests, collect caller feedback without new telemetry, and decide
whether any removal is warranted. Keep all 12 exports and AutoConfirm during
the 0.13 series. Any future warnings must be announced and evaluated for script
compatibility; a removal needs an announced support window and an explicit
breaking-version decision, not just the label "pre-1.0". CSV/projection/removal
are distinct workflows, not redundant setters to eliminate for an export count.

## Live Validation Prerequisites And Receipts

No row below expands execution authority. All execution results are Pending in
this local review. The owner authorization above permits the bounded
expanded fixture run, not every setup in this matrix. Bind it to the final
fixed candidate, accounts/roles, namespaces, topology and cleanup/recovery
plan. Additional scope requires separate approval. Existing lab access or an
old receipt is not consent for an unrelated run.

| Prerequisite Code | Required Setup And Permissions |
| --- | --- |
| B: Bounded writable baseline | Approved disposable users/OU; writable DC; reachable AD services; RSAT/ActiveDirectory and recorded PowerShell/module versions; schema presence/readiness and actual range metadata; schema and user reads plus Write drink rights. Separate setup/cleanup role may create/delete users. No schema-admin rights assumed. |
| X: Controlled interference | B plus separately authorized out-of-band edits, pause/barrier mechanism, exact account correlation and before/after capture. Rename/move/delete and ACL changes require explicitly scoped elevated setup rights. |
| M: Multi-DC | At least two writable DCs, known replication topology/health, per-DC reads, metadata permission, synchronized timestamps and approved fault/replication-window controls. No production replication disruption. |
| S: Disposable schema | Isolated disposable forest or approved whole-forest recovery plan, schema master and schema-change authority; direct LDAP cache-refresh access and AD cmdlet access. A snapshot of one DC is not by itself a multi-DC forest rollback plan. |
| D: Delegation | Pre-created in-scope/out-of-scope users; tested role with schema/user reads and only delegated Write drink where intended; distinct authorized setup/cleanup operator. |
| E: Environment | Recorded host, OS, runtime and AD-module mode, culture/exporter/profile type as appropriate; private writable receipt storage and read-only metrics/log access when needed. |

Every case needs the common receipt below plus its row-specific additions.
Use public synthetic labels such as DC-A, DC-B, USER-01, and RUN-01. Never copy
real hostnames, domain/OU DNs, usernames, GUIDs, IPs, profile paths, passwords,
tokens, raw CSVs, transcripts, screenshots, schema dumps, or live artifacts
into this document, release notes, or ordinary issue comments. Hashing a
private identity/value is not sufficient anonymization. Keep private mappings
and raw receipts under access-controlled operator storage; ignored output is
not automatically sanitized or safe to publish.

| Receipt Field | Required Sanitized Evidence |
| --- | --- |
| Provenance | Case/subcase ID, candidate SHA, module and synthetic fixture hashes, UTC interval, runtime/AD-module/Pester version and mode, receipt ID and reviewer. |
| Authority and boundary | Approval reference, synthetic scope, actor-role label, topology/permissions prerequisite result, recovery preparation and cleanup owner. No credential material. |
| Planned versus actual | Scenario/barrier, planned operation and counts, observed status/error category, assertions, expected/actual counts or Boolean equality verdicts; no live payloads. |
| Directory result | Independent same-DC read-back after success/failure; owned and unowned value-set assertions, then per-DC convergence assertions where applicable. Module `FinalDrinkValues` is computed, not read-back proof. |
| Metadata and call targets | Before/after `drink` version and sanitized originating-DC labels, collection server, and request-target tracing when pinning matters. Missing metadata/traces remain gaps. |
| Run health | Exit status, discovered/passed/failed/skipped/not-run cases and failed containers; partial import counters; cleanup verified against the exact temporary identities. |
| Disposition | Passed / Failed / Blocked / Skipped with cause; separate owner-approved deferral, support restriction, owner, revisit milestone, and private receipt reference. |

[Get-ADReplicationAttributeMetadata](https://learn.microsoft.com/en-us/powershell/module/activedirectory/get-adreplicationattributemetadata?view=windowsserver2025-ps)
provides attribute replication metadata. It is useful write evidence, but does
not record which DC served every preceding schema/user read. Inference from a
single originating-DC field cannot prove case 15; capture selected context and
per-call target evidence, with server-side tracing where available. Ordinary
ADWS/LDAP read calls need not increment metadata. A no-op comparison must use
the same object/DC with other writers excluded.

### Existing Twelve-Case Integration Scope

[Integration source][IT] at baseline contains twelve parameter-expanded cases, using a
temporary user, SamAccountName operations, and one configured endpoint. The
runner needs explicit integration opt-in and target settings. Setup requires
user creation/deletion and attribute writes, but source does not require a
domain-admin identity; least-privilege tests must separate setup rights from
the actor under test. Blocked readiness may skip write assertions, so an
overall passing invocation is insufficient without case counts. The current
worktree additionally contains seven Tier1 tests for the specified numbered
areas; do not keep reporting twelve as the total expanded suite size. Inspect
the final discovered manifest and require explicit Tier1 execution receipts.

| Cases In Checked-In Suite | Concrete Assertions / Gap |
| --- | --- |
| 1 readiness; 2 literal write/read; 3 replace; 4 remove | Readiness or blocking reason, literal prefix values, unrelated namespace preservation. Readiness alone is not ACL proof. |
| 5 CSV; 6-7 blank modes; 8 projection | Mapped read-back, explicit clearing versus retention, expected default projection values. No encoding/exporter or typed/culture matrix. |
| 9-10 CSV/projection both orders; 11 case-only spelling | Final expected combined sets and retained sentinel; exact case comparison. No deliberate duplicate collision. |
| 12 unrelated addition after snapshot | Injects a real unrelated addition between captured snapshot and private writer. Does not cover stale owned removals/additions or distributed writers. |
| Setup/teardown, not a thirteenth case | Terminating delete and verified absence. Require cleanup receipt; teardown failure prevents a clean live pass. |

## Numbered Live Case Matrix

The numbering preserves the attachment's 1-26 list, not the twelve integration
case numbers above. `G` means recommended 0.13.2 release gate; `C` means release
gate for the claimed support surface, otherwise explicit restricted-scope
deferral before 1.0; `D` means planned pre-1.0 evidence, promoted to a gate if
the release claims that topology/environment. All coverage descriptions are
static inspection; no live pass is asserted.

The following current additions supersede the baseline test-gap statements in
the corresponding rows. They do not supersede the required live receipts.

| Numbered Case | Newly Inspected Tier1 Coverage In Existing Integration File | Still Needed |
| --- | --- | --- |
| 1 | Stale planned Remove after out-of-band removal; complete-state assertion and directory-error validation. | Authorized final-candidate observed error and atomicity receipt. |
| 2 | Duplicate Add permits an observed clean error/unchanged state or complete duplicate-ignored update; rejects half-applied state. | Record which branch real AD takes and reconcile the operator contract. |
| 3 | Case-variant collision checks ordinal state, existing spelling and whole-update outcome; baseline case-only replacement retained. | Real collision and case-only receipts, not only one branch's fixture assumption. |
| 4 | Actual rangeUpper, exact/overlong and supplementary-character boundaries with local rejection and controlled direct-server comparison. | Confirm host/schema Unicode length behavior and retain negative-call receipts. |
| 5 | Unicode through generic, prefixed, legacy, CSV and projection paths, with fresh exact reads. Projection uses the owned user's drink source to avoid unrelated attribute changes. | Live round-trip results; self-projection does not establish all real source types, demo-wrapper behavior or case 14. |
| 8 | Complete 1,600-plus-value retrieval and replacements retaining a large unrelated namespace; both reader APIs exercised. | Observed complete sets and actual retrieval-limit context. |
| 9 | CSV and projection reruns assert NoChange and unchanged same-DC replication metadata. | Real metadata access, version comparison and no-competing-writer receipt. |

These tests use only the one captured, owned disabled integration user and
require both environment opt-ins. They do not create a campaign, broaden the
user allowance, or cover all other numbered cases. Test names and conditional
assertions remain hypotheses until the final authorized run.

### Tier 1: Single Writable DC

| Case / Gate | Prerequisites And Procedure Scope | Concrete Pass Evidence And Added Receipts | Current Coverage Versus Gap |
| --- | --- | --- | --- |
| 1. Remove already-absent value / G | B+X; capture a plan, remove its owned value out-of-band, then execute the stale delta on the same DC. Also exercise CSV's final-read boundary separately. | Controlled stale request must not silently half-apply the companion Add or alter unowned values. Record actual AD error/success category and independent state immediately before/after the attempt. Reviewer expects clean failure; establish the real outcome before turning that into a contract. | [WRITE] sends combined Remove/Add; [WT] models unrelated additions, not real absent-remove semantics. CSV may stop earlier with plan-changed error; that alone does not prove the server's stale-delta behavior. |
| 2. Add already-present value / G | B+X; insert exact desired value after snapshot; retain a companion removal to detect partial behavior. | Final value appears once; observed success/error, remaining owned set, unrelated sentinel and metadata agree with documented behavior. On error, verify no partial request effects beyond the deliberate interference. | Ordinal planning and desired-value deduplication exist; stub mutation cannot prove duplicate-add behavior. Needs deterministic race receipt and live read-back. |
| 3. Case-variant collision / G | B+X; separate exact-case replacement and attempted coexisting case-variant scenarios, with controlled initial sets. | Case-only desired spelling lands; duplicate/collision result is recorded; no half-applied Remove/Add or unrelated loss. Use ordinal assertions, not case-insensitive test equality. | [IT] case-only spelling; [WT] case-sensitive deltas/case-insensitive desired deduplication. Real collision semantics and combined-operation failure are untested here. |
| 4. Length boundaries / G | B; record live `rangeUpper`; test full prefix+payload at limit and limit+1, then supplementary Unicode near boundary. Do not alter production schema to manufacture a limit. | Limit accepted/read back; over-limit rejected before Set-ADUser; record UTF-16 units, code points and server outcome for emoji. Unknown limit is reported unknown, not invented. A mismatch blocks unrestricted non-ASCII length claims. | [WRITE] uses string Length; [ST] tests range metadata; [WT] tests overlength. No proof yet that server counting matches every Unicode boundary. |
| 5. Non-ASCII round-trip / G | B+E; synthetic accents, CJK, supplementary characters through generic/prefixed/legacy setters, CSV, projection and demo; verify read APIs and safe removal. | Compare exact ordinal values from independent reads (unordered sets, no normalization). Record fixture encoding/hash and zero substitution. "Byte-for-byte" means a defined serialization, since AD returns strings, not the original CSV bytes; deliberate trim/split mapping remains contractual. | Basic string paths exist; no exhaustive Unicode/path/runtime test matrix at baseline. CSV F1 is a separate blocker. |
| 6. Every identity type / G | B with separately provisioned unique UPN, employeeID, mail and pager; duplicates for non-unique attributes and a sentinel decoy. | Each public identity-bearing read/write wrapper resolves the intended object; two matches fail with matched-count error before mutation. CSV remains SamAccountName-only. Receipt records identity kind, match count, synthetic object match and zero writes on ambiguity. | [UT] exact mail and ambiguity stubs; [ST] forwards all identities through readers; [IT] uses SamAccountName. Live alternate-identity and duplicate coverage missing. |
| 7. LDAP special characters / G | B; approved synthetic mail/employeeID values containing literal star, parentheses and backslash, plus a wildcard decoy; record if schema/setup rejects a fixture. | Exact intended object alone selected; decoy unchanged; escaped-filter expectation and read-back verdict. Fixture setup failure is Blocked, not proof of lookup safety. | [CORE] escapes NUL and LDAP metacharacters; [UT] exact escaped-mail filter; [ST] schema escaping. Real directory match behavior remains pending. |
| 8. Large multivalue set / G | B+E; more than 1,600 distinct allowed values, including owned/unowned sentinels, with expected full set and independently verified effective retrieval limits. | Returned cardinality and entire expected set match; replacement removes every stale owned value while preserving every unowned value. Store count/set-equality receipts, not payload dumps. Do not treat 1,500 as an invariant forest setting. | No explicit range-retrieval implementation/test in inspected module. The reviewer threshold is a fixture target; whether the AD module retrieves all ranges needs proof. |
| 9. Real no-op / G | B; stable fixture, no competing writers; run CSV twice and projection twice with PassThru as appropriate. | Second runs report NoChange for prepared unchanged rows, zero mutation calls where observable, and unchanged same-DC drink version/state. Deliberately skipped blank CSV rows produce no result, not NoChange. | [UT]/[WT] prove mock no-write/no-op outcomes; [IT] does not assert metadata stability on rerun. |
| 10. Interactive confirmation / G | B+X+E; real interactive host with at least three changed rows; separate runs for Yes/No/Yes to All and No to All, and a paused-prompt owned change. | Written/Declined and prompt counts match choices; All applies to remaining rows only. Owned delta change stops with plan-changed and no module write for that row; separate unowned change can proceed and remains preserved. Receipt includes synthetic prompt decisions, statuses and independent states. | [WT] custom-host All-choice and freshness tests exist. No real-host/AD prompt receipt for candidate. One run cannot exercise both All choices after prompting has stopped. |
| 11. Mid-import failure, rename/move / G | B+X; controlled deletion after preflight, separate rename/move before refresh, separate denied-write row; include unchanged/declined rows and later pending rows. | Deleted/denied row stops import; earlier writes remain and later rows untouched. Completed and per-status counts plus FailedRowNumber/Pending/Prepared reconcile. Rename/move succeeds via captured GUID and refreshed DN, not account-name rebinding. Test moves after final refresh separately: no atomic rename guarantee. | [WT] covers GUID refresh, resolution/length preflight, refresh/write failure counters with mocks. Real disappearance/ACL/rename behavior missing. |
| 12. Server forms with real resolution / G; M needed for full proof | B+E, add M for locator variability; omitted input, domain DNS, known NetBIOS domain, DC FQDN, verified short DC, IP, explicit valid port and alias; malformed forms remain local negative tests. | For each form, record intended category, sanitized selected endpoint, per-call targets and write-origin metadata; explicit endpoint retained, discovery-pinned forms reused. NetBIOS/alias stability is observed, not promised. Port syntactic validity is not proof of writable service or authentication. | [ST] extensive endpoint mocks, including short alias preservation; attachment's probe count mismatch unresolved. Single-DC success cannot prove locator stability with multiple choices. |
| 13. Excel-produced CSV / G | B+E; actual exporter/version/locale recorded; UTF-8 with/without BOM, plain legacy-format bytes with accents, embedded newlines; retain synthetic fixture hashes. | Valid supported encoding round-trips and preserves record count; unsupported/malformed encoding fails closed before AD access with actionable guidance. No decoding substitution; valid encoded U+FFFD remains accepted. Use strict UTF-8/default or BOM-selected UTF-16/32 contract, not a guessed Excel default. | Current [UT] adds real-byte valid/invalid Unicode cases alongside empty/multiline/type/hash structure. Need final gate and exporter/live receipts; baseline corruption reproduction is supported by reported actual-byte evidence. |
| 14. Awkward projection sources / C | B+E; separately provisioned proxyAddresses, memberOf with separator-bearing DNs, whenCreated/date and empty attributes; en-US/de-DE; include native and compatibility objects if claimed. | Existing invariant general-format output and counts agree across cultures; no unrequested ISO change. Prefix+rendered lengths validated; multivalues preserved; cleared source removes only its namespace. Record source type, culture, synthetic expected rendering and read-back equality. DN separators remain literal payload. | Reported unit evidence found no production bug on PS7.6.3; six inspected new [WT] cases cover typed values, multivalue/DN strings and blank clearing. Production unchanged. Real AD/compatibility-source evidence and final-candidate execution remain pending. |

### Tier 2: Multiple Controllers

| Case / Gate | Prerequisites And Procedure Scope | Concrete Pass Evidence And Added Receipts | Current Coverage Versus Gap |
| --- | --- | --- | --- |
| 15. One DC per operation / D | B+M; omitted Server through each public write path, including wrappers, removal, CSV and projection; trace discovery and all subsequent phases. | After initial RootDSE selection, schema reads, user reads and mutation reuse selected DC. Record per-call endpoint evidence plus metadata; do not demand the discovery call already knew the selected hostname. Independent operations may select different DCs. | [ST]/[WT] assert mocked server arguments; no multi-DC runtime trace. Metadata alone proves neither every read target nor alias stability. |
| 16. Lagging target DC / D | B+M+X; controlled verified lag, write on DC-A then pinned DC-B; observe both before and after convergence. | Record preconditions, per-DC values/versions, actual error/merge/loss, convergence and policy outcome. Outcome must match a bounded documented limitation; unexpected silent loss invalidates any stronger claim. | Scoped local deltas and [DATA]/[REVIEW] concurrency cautions only. No conflict resolution or cross-DC freshness protocol implemented. |
| 17. Concurrent distinct prefixes across DCs / D | B+M+X; coordinated writes on DC-A and DC-B before replication, non-overlapping prefixes, baseline and convergence checks. | Record both initial successes/failures, originating labels/versions, intermediate and converged set-equality verdicts. Reviewer predicts possible whole-attribute replication loss; neither guaranteed loss nor guaranteed merge is a pass assumption. Publish a single-writer-DC/external-serialization policy consistent with observations. | Same-DC unowned-add [IT] cannot prove cross-DC behavior. Documented nonlinked-attribute risk remains; one no-loss trial cannot establish safety. |
| 18. Read-only DC / D | B+M with actual RODC and writable peer, permitted reads, controlled attempted write and cross-DC verification. | Reads succeed within permissions; writes fail clearly with no unexpected referred/partial mutation on any peer. Preserve error category and metadata/state checks. Microsoft [Set-ADUser notes](https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-aduser?view=windowsserver2025-ps#notes) exclude RODC writes; this is negative-path evidence, not a new supported write mode. | No RODC integration case or early RODC role check at baseline. Schema readiness does not establish controller writability. |

### Tier 3: Schema, Permissions, And Environments

Schema mutation cases 19-20 require S. Cases 21-26 need their specific setup
and permissions, not automatic Schema Admin privileges or schema changes.

| Case / Gate | Prerequisites And Procedure Scope | Concrete Pass Evidence And Added Receipts | Current Coverage Versus Gap |
| --- | --- | --- | --- |
| 19. Schema enablement end to end / D | S+B+M; initially not allowed; preview, Apply+WhatIf, guarded Apply with all three Expected values on schema master; immediate write there, replicated write on peer, repeat Apply. | Preview/WhatIf cause no schema/cache mutation (WhatIf also no report file); Apply report/state agrees, immediate real write succeeds without arbitrary sleep, peer succeeds after verified propagation, repeat yields AlreadyReady. Capture cache-refresh and failure-state receipts; refresh failure is not rollback. | [enablement tests][SET] cover guards, no-op, refresh, report, errors; no new schema-apply receipt. AlreadyReady metadata alone does not prove server cache/write success. |
| 20. Auxiliary-class readiness / D | S+B; approved custom class/OID ownership and association; drink allowed only through auxiliary inheritance, not a leftover direct allowance. | ReadyForUserWrite derives from actual inherited path and real user write/read-back succeeds; sanitized graph shape and direct-allowance-absent assertion. Record every change and recovery verification. | [ST] inherited/auxiliary/systemAuxiliary, OID/DN/name, cycles/ambiguity tests; no real custom-schema receipt. Module does not provision this custom class. |
| 21. Extended schemas / D | B+E; existing authorized Exchange/RFC 2307 extended-schema fixtures; verify actual relevant class graph without assuming every installation attaches the same classes. No extension install implied. | Complete graph resolution, no spurious ambiguity/unresolved error, explicit readiness and representative user-write result if ready. Retain sanitized class/reference counts and supported environment labels. Genuine malformed metadata must still fail closed. | [ST] broad synthetic graph coverage; no enterprise-schema proof or blanket support certification. |
| 22. Least-privilege delegation / G | B+D; actor can read required schema/user metadata, Write drink only in one OU; separate setup operator creates inside/outside users and ACL boundary. | Inside write/read-back succeeds; import reaches denied outside row and stops with accurate processed/written/no-change/pending counts; prior rows retained, later untouched. No admin membership in test actor. | Readiness is legality, not an ACL probe; [WT] mocked failure progress only. Full integration setup privileges must not mask the negative role test. |
| 23. Read-only account / G | B+D with read-only actor; prepared fixtures and no incidental log-path failure masking AD results. | Reads and WhatIf succeed, preview leaves directory/logs unchanged, actual attempted writes fail cleanly without partial state change; receipt distinguishes permission denial from authentication/connectivity failure. | [UT]/[WT] WhatIf and [LOGT] preview guards; no live least-rights negative-path proof. |
| 24. Supported runtimes / G for Windows 5.1; C for each advertised PS7 mode | B+E; Windows member host with RSAT for 5.1, PowerShell 7 native AD loading, and PowerShell 7 Windows-compatibility remoting as separate lanes; exact versions and loading mode recorded. | Full local gate and twelve-case integration per claimed lane; ObjectGUID identity, drink multivalues, DN, preview and error progress work with actual returned object types. No skipped writes hidden by overall success. | CI includes four OS/runtime unit lanes but no AD environment. Deserialized-object handling and PS7 native/compatibility availability cannot be inferred from PowerShell Core CI. Unsupported/unavailable modes require a documented restriction or Blocked receipt. |
| 25. Enterprise logging profiles / C | B+E; redirected/OneDrive-backed/junction profile variants plus ordinary profile; actor owns test logs; exercise EnableLogging and approved explicit path. | Log stored correctly or guard refusal produces documented best-effort warning without changing AD result; suppression honored; no payloads, unsafe fallback, preview bytes or rotation surprises. Record profile category and warning/status/counts, never actual path/GUID log content. | [LOGT] synthetic linked ancestor and platform-specific case; no Windows enterprise-profile receipts. Not every OneDrive profile redirects LocalApplicationData. A protective rejection is not automatically a bug. |
| 26. Scale / D; G before renewed 3,000-row throughput claims | B+E; approved bounded 3,000-user fixture/rollback, instrumented ADWS and DC metrics with read-only monitoring rights; WhatIf then changed real import, plus no-op comparison. | Complete intended counts with no ADWS/throttling failures, bounded measured memory, wall time/phase counts, DC CPU and observed user queries. Distinguish preview's approximately 6,000 from approved changed import's approximately 9,000 user reads; do not promise fixed performance. | Campaign Full profile supplies scale inputs, but historical durations and parser microbenchmark do not measure current triple-read importer. No candidate-specific resource/throughput receipt here. |

## Recommended Release Decision

The attachment's earliest-run subset (1-2, 4, 8, 10-12) is a useful execution
order, not sufficient release evidence by itself. Recommended gates below are
deliberately explicit; the owner may approve a narrower support envelope, but
must record deferred scope rather than claiming it passed.

| Gate | Evidence Required Before Recommending 0.13.2 | Current Disposition |
| --- | --- | --- |
| G0: Exact candidate and local safety | Strict Unicode repair and regression receipts, projection no-bug adjudication plus six regressions, documentation reconciliation, fresh [release gate][GATE], pinned Pester 5.7.1, all four runtime/OS CI results and docs check, manifest/export/FileList/help parity. Record final counts, not an immutable target of 349. | Implementation/test additions inspected; final gate and CI receipts pending here. |
| G1: Authorized baseline and expanded live | Baseline twelve cases plus selected opt-in Tier1 and authorized expanded cases, with required assertions executed, zero failed/unexplained skipped/container errors, read-back and cleanup proof on final fixed candidate, not old 55906b1. | Bounded expanded authorization received as reported by user; execution and receipts pending. |
| G2: Data integrity and operator behavior | Cases 1-13 and 22-23; single-DC parts of 12 now, multi-DC limitation explicitly retained. Case 24 on Windows PowerShell 5.1/RSAT. Failures in data preservation, invalid-input rejection, approval accuracy or failure accounting block recommendation. | Pending. Stub coverage is insufficient. |
| G3: Conditional support surface | Case 14 real-source evidence after no-bug projection adjudication; case 24 claimed PS7 modes; case 25 enterprise logging; case 26 if making current throughput claims. Confirmed defects cannot be relabeled deferred without an explicit supported-scope decision. | Projection local adjudication reported; live/environment evidence or owner-approved restrictions pending. |
| G4: Pre-1.0 program | Cases 15-21 and 26 by default, plus conditional cases deferred with a restricted 0.13.2 claim. Track owner, setup requirement, receipt ID, revisit milestone and whether any discovery promotes a release blocker. | Deferred proposal only, not accepted risk or task authorization. |
| G5: Owner release hold | Evidence collection and the separate visual comparison may continue. Owner must explicitly lift the release/tag hold after homepage artwork review and evidence review before any publication. Passing technical gates cannot override that hold. | Explicitly held by owner; no tag/release or issue closure implied. |

Known limitations must remain in release communication: explicit aliases and
NetBIOS domain inputs are not general physical-DC pinning guarantees;
concurrent same-prefix or cross-DC writers need external coordination;
preflight is not an ACL test, transaction or rollback; pass-through values are
computed; logs are best effort; schema metadata readiness is not proof of cache
refresh, permissions, replication, or actual write success.

Microsoft documents Remove-before-Add ordering for combined
[Set-ADUser operations](https://learn.microsoft.com/en-us/powershell/module/activedirectory/set-aduser?view=windowsserver2025-ps#-add).
That ordering informs the implementation but is not, on its own, evidence of
the error/atomicity outcomes demanded by cases 1-3. Capture those outcomes
instead of adopting the reviewer's expected errors as facts.

## Reference Index

Links below point to current repository files; named functions/test contexts
above identify the inspected assertions. Reconcile changes against `55906b1`
before reusing this matrix for a later candidate. Historical notes are evidence
of their dated scope, not permission to publish new lab details.

| Area | Primary References |
| --- | --- |
| Guidance and prior adjudication | [Contributing][CONTRIB], [October review record][REVIEW], [testing][TESTING], [live guide][LIVE], [host-method boundary][HOST], [schema operations][SCHEMADOC] |
| Input/write implementation | [CSV mapping][CSV], [importer][IMPORT], [prefix planning/writer][WRITE], [identity/logger core][CORE], [schema resolver][SCHEMA], [projection conversion][PROJ], [projection public command][PROJPUB] |
| Test evidence | [general units][UT], [write-operation units][WT], [schema units][ST], [logging units][LOGT], [ownership units][OWN], [enablement units][SET], [release units][RT], [live campaign units][CAMPT], [integration][IT] |
| Release contract | [manifest][MANIFEST], [changelog][CHANGELOG], [trusted runner][RUNNER], [release gate][GATE], [PowerShell CI][CI], [docs CI][DOCSCI] |
| Operator semantics | [data model][DATA], [CSV guide][CSVGUIDE], [operations][OPS] |

Issue #16 tracks acceptance and execution receipts. Projection unit tests found
no production defect; six regressions were added without changing its behavior.
Authorized live validation must stay inside the approved fixture scope and
collect common plus per-case receipts. The owner also approved an illustrated
artwork refresh, with current technical text and Mermaid retained in detailed
docs. Release/tagging remains held, and no automatic schedule is created.
Reported external counts are not promoted to tests performed by this review.

[CONTRIB]: ../CONTRIBUTING.md
[REVIEW]: issues/013-october-review-hardening.md
[TESTING]: TESTING.md
[LIVE]: LIVE-VALIDATION.md
[HOST]: LIVE-CAMPAIGN-HOSTS.md
[SCHEMADOC]: SCHEMA-ENABLEMENT.md
[CSV]: ../DrunkenAD/Private/CsvMapping.ps1
[IMPORT]: ../DrunkenAD/Public/Import-ADUserDrinkCsvData.ps1
[WRITE]: ../DrunkenAD/Private/WriteOperation.ps1
[CORE]: ../DrunkenAD/Private/Core.ps1
[SCHEMA]: ../DrunkenAD/Private/SchemaStatus.ps1
[PROJ]: ../DrunkenAD/Private/ProjectionMap.ps1
[PROJPUB]: ../DrunkenAD/Public/Set-ADUserDrinkProjection.ps1
[UT]: ../tests/DrunkenAD.Unit.Tests.ps1
[WT]: ../tests/WriteOperation.Unit.Tests.ps1
[ST]: ../tests/SchemaStatus.Unit.Tests.ps1
[LOGT]: ../tests/Logging.Unit.Tests.ps1
[OWN]: ../tests/SampleOwnership.Unit.Tests.ps1
[SET]: ../tests/SchemaEnablement.Unit.Tests.ps1
[RT]: ../tests/Release.Unit.Tests.ps1
[CAMPT]: ../tests/LiveCampaign.Unit.Tests.ps1
[IT]: ../tests/DrunkenAD.Integration.Tests.ps1
[MANIFEST]: ../DrunkenAD/DrunkenAD.psd1
[CHANGELOG]: ../CHANGELOG.md
[RUNNER]: ../tests/Invoke-DrunkenADTests.ps1
[GATE]: ../scripts/Test-DrunkenADRelease.ps1
[CI]: ../.github/workflows/powershell-ci.yml
[DOCSCI]: ../.github/workflows/documentation-ci.yml
[DATA]: DATA-STORE.md
[CSVGUIDE]: HOW-TO-INGEST-CSV.md
[OPS]: OPERATIONS.md
