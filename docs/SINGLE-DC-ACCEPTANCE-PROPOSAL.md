# Restricted Single-DC Acceptance Proposal

Prepared at the owner's request after the October review. **Proposed, not yet
accepted.** This is a bounded acceptance decision for the reviewed candidate,
not a declaration that all 26 validation cases passed, a change to the public
API, or permission to merge, publish, close issues, or modify infrastructure.
The separate release/tag hold remains in force.

Tracking: [PR #17](https://github.com/jonathanweinberg/DrunkenAD/pull/17),
[issue #16](https://github.com/jonathanweinberg/DrunkenAD/issues/16), and the
[full review matrix](POST-MERGE-VALIDATION.md).

## Proposed Decision

Accept the inspected fixes and recorded evidence for **controlled single-DC
evaluation** within the envelope below, only after a fresh authorized final
one-user run completes its required assertions and cleanup. The latest attempt
was interrupted by a private harness/Pester skip-handling stall; its fixture
was removed and cleanup independently verified. See the
[interrupted-run receipt](SINGLE-DC-VALIDATION-2026-10-08.md). Explicitly retain
the gaps in this proposal as unproven, with the listed revisit triggers.
This is not an unrestricted production-readiness recommendation.

The owner authorized that one-user attempt and requested this proposal. That
attempt's approval is consumed, not reusable for a retry. Neither action
accepts the proposed deferrals. A later explicit acceptance
decision should name the final candidate and this scope. Merge and release
remain separate decisions.

## Evidence Envelope

| Area | Proposed Verified Claim / Operating Requirement |
| --- | --- |
| Runtime and host | Native ActiveDirectory module under Windows PowerShell 5.1 on a Windows Server 2025 domain controller. CI units on other runtimes are valuable but not live AD certification. |
| Directory target | One common designated writable DC, selected by its actual hostname across all producers of the affected objects' `drink` attribute, including different prefixes. Use it for reads feeding writes and coordinate any failover. Independent per-writer choices, aliases and NetBIOS domains do not establish this condition. |
| Schema | `drink` is already present and ready for users. The observed existing RFC-containing class graph resolves; no Exchange, custom auxiliary-only schema, or schema-enable/replication claim. |
| Mutation model | Small namespaced value sets with literal, non-overlapping owned prefixes. Preserve unrelated values using scoped Remove/Add. Serialize same-prefix producers externally; stale deltas can fail, replace values or leave combined sets. The read/plan/confirm/write workflow is not a serializable transaction or distributed lock. |
| Length | Enforce the actual schema `rangeUpper` on the complete prefixed string. Native generic boundary evidence already exists; final projection-boundary execution remains required below. No blanket Unicode/collation or object-capacity guarantee. |
| CSV | Strict supported-Unicode decoding and structural validation before directory access. Blank namespaces clear only when explicitly requested. Actual Excel save formats are not certified by constructed fixtures or Export-Csv tests. |
| Identity and operator flow | Recorded exact identity/literal-lookup checks, actual confirmation choices, GUID-based rename/move handling, no-op metadata, and bounded partial-failure accounting. These do not prove least-privilege delegation. |
| Recovery | A verified rollback prerequisite, owned disabled fixtures only, fresh state checks and confirmed deletion. Raw receipts and exact lab identities remain private. |

## Required Acceptance Receipts

| Requirement | Available Evidence / Remaining Action |
| --- | --- |
| Source identity | Candidate `07d26b9`, its archive and all 22 bundled file hashes were verified before execution. Production module source remains equivalent to `038013b`; see the [candidate receipt](SINGLE-DC-VALIDATION-2026-10-08.md). |
| Offline gate | `07d26b9` passed 393 local tests with 27 live cases excluded, plus all five exact-candidate CI checks. The receipt distinguishes Core and Windows PowerShell 5.1 counts and platform skips from live evidence. |
| Revised integration setup | The issue #18 repair passed offline selection/isolation tests. The latest native attempt created its single fixture but did not complete its result receipt. The corrected private launcher passed a synthetic-only native skip preflight, and eight watchdog controls passed on both tested runtimes; see the [preparation receipt](SINGLE-DC-VALIDATION-2026-10-08.md#synthetic-retry-preparation). This is not live proof. A retry still requires fresh authority, renewed prerequisites, exact launcher/candidate review and independent cleanup. |
| Projection boundaries | All eight added native command/culture/source cases remain unexecuted. A fresh authorized run must prove exact-limit round-trip and local overlimit rejection with complete value-set and metadata preservation. Offline controls are not substitutes. |
| Rename/move race boundary | Existing native evidence covers before-refresh and during-prompt changes, not after the final refresh. That remaining case-11 scenario needs separate authorization and a receipt, or an explicit scope disposition; it is not implicitly covered by GUID-based refresh. |
| Capacity gap | Historical 1,602-value setup rejection remains a skipped prerequisite, not range-retrieval proof. The replacement separately opted-in [capacity characterization](TESTING.md#bounded-capacity-characterization) has no live receipt yet. Require a recognized production Remove/Add rejection, unchanged full state/metadata, bounded requests and cleanup; reaching the bound without rejection is an Evidence Gap. Its fixture-specific bracket does not close large-range retrieval. |
| Final cleanup | The interrupted attempt's fixture absence and parent preservation were independently verified. A later acceptance run still requires zero failed tests/containers, no unexplained skips/not-run cases and its own cleanup receipt. A completed capacity-only skip leaves that suite partial, even if the restricted claim is later accepted. |
| Owner decision | Explicitly accept or revise this proposal after reviewing the final receipt. This document alone changes no acceptance or publication status. |

## Explicit Deferrals

These are proposed limits on the acceptance claim, not deletion of requirements
or claims that an untested environment is broken or unsupported by the API.
Maintainer ownership and a dated revisit milestone should be assigned when the
proposal is accepted; none is invented here.

| Cases | Unproven Scope | Revisit Trigger |
| --- | --- | --- |
| 8 | Greater-than-1,600-value retrieval/replacement after successful seed setup. Current environment rejects the prerequisite at its capacity limit. | Suitable separately authorized capacity environment, before large-value-set claims. |
| 12, 15-18 | Working DNS alias, multi-DC locator stability, lag/conflict convergence and RODC behavior. | Approved topology and trace plan, before multi-DC or alias stability claims. |
| 13 | Original Excel UTF-8/plain CSV provenance and exact cell/AD round-trip. The [intake protocol](EXCEL-CSV-VALIDATION.md) and synthetic source workbook are prepared, not exporter evidence. | Original exports with version/locale, followed by offline intake and separately authorized live fixtures, before promising that Excel workflow. |
| 19-20 | Schema enablement/cache refresh/peer propagation and custom auxiliary-only readiness. | Disposable schema authority and appropriate recovery, before those environment claims. |
| 21 | Existing extended-schema compatibility, including Exchange. The observed RFC graph/readiness evidence remains partial, not an Exchange or representative-write pass. | An existing authorized extended-schema environment and read permissions for graph/readiness inspection; separate fixture/write authority for a representative write. No extension installation is implied. |
| 22-23 | True delegated-write and read-only principals. A privileged actor with an object-specific deny does not substitute for either. | Pre-provisioned least-rights actors and explicit fixture/ACL scope, before least-privilege claims. |
| 14, 24 | PowerShell 7 native/compatibility AD objects and member-server RSAT runtime lanes. Native 5.1 projection results do not certify deserialized objects. | Approved existing hosts/runtime modes, before deployment guidance asserts those lanes were live-validated. |
| 25 | Redirected, OneDrive and junction-backed enterprise profiles. | Approved representative profiles and log-path expectations, before environment-specific logging claims. |
| 26 | Current 3,000-user throughput, resource use and ADWS behavior. | Explicit campaign authority and measurement plan, before renewed scale claims. |

## Review 5 Scope Option

The owner has reported that multi-DC hardware is unavailable. A target 0.13.2
envelope could require the common writer DC above, native Windows PowerShell
5.1 with RSAT, existing ready schema, and the documented Unicode CSV contract.
This remains a proposed policy, not an accepted support restriction or release.
The observed live host was the DC; member-host RSAT behavior remains unproven.

If explicitly adopted, cases 16-17 and the multi-controller portions of 12, 15
and 19 would be outside that accepted envelope **and still not executed**.
That would not validate routing/failover, replication freshness, other tools
writing on peers, or same-DC concurrency. RODCs are unsupported write targets
under Microsoft's Set-ADUser contract; case 18's exact failure and referral
behavior remains untested. Schema, actor, runtime, authentic-export and scale
work can remain a named pre-1.0 backlog, not silently become passes.

No new default warning, mandatory API parameter, endpoint rejection, schema
change, DNS alias, cloud lab or release is introduced by this proposal.

## Decision Record

- Proposal requested: yes.
- Additional isolated one-user run: authorized, attempted once and consumed.
- Latest run: interrupted in private harness/Pester skip handling; no completed
  test aggregate and none of the eight new boundary cases executed.
- Cleanup: independently verified; zero owned fixtures remain and parent intact.
- Synthetic preparation: corrected launcher skip preflight and bounded watchdog
  controls passed without AD access; no live retry occurred.
- Any retry: fresh authority required; the completed live acceptance receipt is
  still missing. The harness problem is not an accepted deferral.
- Restricted acceptance: pending owner review of this proposal and receipt.
- Release/tagging: explicitly held.
- Merge and issue closure: not performed or authorized by this proposal.
