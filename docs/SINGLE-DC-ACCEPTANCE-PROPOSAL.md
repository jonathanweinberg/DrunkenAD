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
evaluation** within the envelope below, after the newly approved final
one-user run passes its executable assertions and cleanup. Explicitly retain
the gaps in this proposal as unproven, with the listed revisit triggers.
This is not an unrestricted production-readiness recommendation.

The owner has authorized that one-user run and requested this proposal.
Neither action accepts the proposed deferrals. A later explicit acceptance
decision should name the final candidate and this scope. Merge and release
remain separate decisions.

## Evidence Envelope

| Area | Proposed Verified Claim / Operating Requirement |
| --- | --- |
| Runtime and host | Native ActiveDirectory module under Windows PowerShell 5.1 on a Windows Server 2025 domain controller. CI units on other runtimes are valuable but not live AD certification. |
| Directory target | One existing writable DC, selected by an actual DC hostname. Use the same selected DC for reads and writes; explicit aliases and NetBIOS domains do not establish physical-server stability. |
| Schema | `drink` is already present and ready for users. The observed existing RFC-containing class graph resolves; no Exchange, custom auxiliary-only schema, or schema-enable/replication claim. |
| Mutation model | Small namespaced value sets with literal, non-overlapping owned prefixes. Preserve unrelated values using scoped Remove/Add. Coordinate same-prefix writers externally and do not infer a transaction or distributed lock. |
| Length | Enforce the actual schema `rangeUpper` on the complete prefixed string. Native generic boundary evidence already exists; final projection-boundary execution remains required below. No blanket Unicode/collation or object-capacity guarantee. |
| CSV | Strict supported-Unicode decoding and structural validation before directory access. Blank namespaces clear only when explicitly requested. Actual Excel save formats are not certified by constructed fixtures or Export-Csv tests. |
| Identity and operator flow | Recorded exact identity/literal-lookup checks, actual confirmation choices, GUID-based rename/move handling, no-op metadata, and bounded partial-failure accounting. These do not prove least-privilege delegation. |
| Recovery | A verified rollback prerequisite, owned disabled fixtures only, fresh state checks and confirmed deletion. Raw receipts and exact lab identities remain private. |

## Required Acceptance Receipts

| Requirement | Available Evidence / Remaining Action |
| --- | --- |
| Source identity | Record exact candidate SHA, archive and individual file hashes. The prior live-validated module source is `038013b`; later test changes need their own execution receipt. |
| Offline gate | `cc76446` passed 393 local tests and all five CI checks. Revalidate the added live-test source and selection regression on its final candidate; do not reuse an older green check as that proof. |
| Revised integration setup | The prior issue #18 setup repair passed offline selection/isolation tests. The newly approved one-user run must prove actual selected initialization, original baseline cases and cleanup. |
| Projection boundaries | Run the eight added native command/culture/source combinations on the same fixture. Exact-limit records must round-trip; overlimit attempts must report the local validation error and leave the entire value set and metadata unchanged. |
| Capacity gap | Keep any recognized 1,602-value setup rejection visible as a skipped prerequisite with unchanged-state proof. It is not a range-retrieval pass; do not reduce the fixture to claim success. |
| Final cleanup | Require zero failed tests/containers, no unexplained skips/not-run cases, owned fixture absence and preservation of the pre-existing parent. A capacity-only skip leaves the overall suite partial, even if the proposed restricted claim is later accepted. |
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
| 19-21 | Schema enablement/cache refresh/peer propagation, custom auxiliary-only readiness and Exchange extensions. Existing RFC graph evidence covers only its observed graph. | Disposable schema authority and appropriate recovery, before those environment claims. |
| 22-23 | True delegated-write and read-only principals. A privileged actor with an object-specific deny does not substitute for either. | Pre-provisioned least-rights actors and explicit fixture/ACL scope, before least-privilege claims. |
| 14, 24 | PowerShell 7 native/compatibility AD objects and member-server RSAT runtime lanes. Native 5.1 projection results do not certify deserialized objects. | Approved existing hosts/runtime modes, before deployment guidance asserts those lanes were live-validated. |
| 25 | Redirected, OneDrive and junction-backed enterprise profiles. | Approved representative profiles and log-path expectations, before environment-specific logging claims. |
| 26 | Current 3,000-user throughput, resource use and ADWS behavior. | Explicit campaign authority and measurement plan, before renewed scale claims. |

## Decision Record

- Proposal requested: yes.
- Additional isolated one-user run authorized: yes, for this validation pass only.
- Final run and cleanup: pending; receipt will be linked after execution.
- Restricted acceptance: pending owner review of this proposal and receipt.
- Release/tagging: explicitly held.
- Merge and issue closure: not performed or authorized by this proposal.
