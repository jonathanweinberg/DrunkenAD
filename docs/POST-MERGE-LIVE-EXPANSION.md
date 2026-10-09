# Expanded Single-Controller Review Receipt

Historical receipt, 2026-10-08. Tracking: [issue #16](https://github.com/jonathanweinberg/DrunkenAD/issues/16)
and [PR #17](https://github.com/jonathanweinberg/DrunkenAD/pull/17).
Full prompt attestations, failure counters, harness corrections, manifests and
raw native receipts are preserved privately. This sanitized summary supplements
the [26-case matrix](POST-MERGE-VALIDATION.md), not a release approval.

## Candidate And Boundaries

All 20 module files matched source `038013b804305bc2292b96c7f76b2a51059ca4b6`.
Runtime was native ActiveDirectory under Windows PowerShell 5.1 on Windows
Server 2025, with one writable DC. Fresh processes and command provenance were
checked; unchanged module bytes do not create a later-head live-suite receipt.

Four disabled users, one nonprivileged distribution group and two OUs were
created inside the approved test parent. With two preceding one-user runs,
this exhausted the six-user allowance. Rollback was verified beforehand.
No schema, DNS, infrastructure, existing-user or seeded-campaign change occurred.

## Results

| Case | Observed Result | Limit |
| --- | --- | --- |
| 5: Unicode supplement | Exact accents, CJK and supplementary-character round-trip through demo/read/removal, preserving unrelated values. | Not every Unicode/exporter/runtime combination. |
| 6: Identity/ambiguity | 64 public checks passed across five identity modes/eight APIs and employeeID/mail/pager two-match rejection. Decoys and metadata preserved. | CSV remains SamAccountName-only; no duplicate UPN fixture. |
| 7: LDAP literal characters | 32 public checks passed for mail/employeeID with star and combined metacharacters, using a wildcard decoy control. | These native attribute/character combinations only. |
| 10: Confirmation | Four actual ConsoleHost scenarios passed: mixed choices, No to All, owned drift rejection and unrelated drift preservation. | Not an atomic lock after the final read. |
| 11: Rename/move | Before-refresh and during-prompt changes succeeded via captured GUID and refreshed DN, with independent full-state checks. | No after-final-refresh atomic rename guarantee. |
| 11: Partial failures | Three temporary property-denial variants and middle-row deletion passed with reconciled counters and untouched pending rows. | Privileged actor with object-specific deny is not least-privilege/read-only role proof. |
| 12: Endpoints | Seven forms passed: omitted, domain DNS, NetBIOS domain, FQDN, short DC name, IPv4 and explicit port. Each recorded 13 AD binding events, one write, full-state equality and originating metadata. | Alias resolution failed before mutation. Single-DC success cannot prove multi-DC locator stability. |
| 14: Native projection | Eight checks passed across both projection commands, populated/empty sources and en-US/de-DE. Native dates, multivalues and separator-bearing DNs agreed. | Native 5.1 positive cases, not later boundary rejection or PS7 compatibility proof. |

Cases 6, 7 and 14 total **104 public-API checks**, not Pester cases. Ten
confirmation/failure scenarios were separate from the then-19-case integration
suite. The eight prompt-attestation rows span cases 10 and 11; they are not
eight independent case-10 confirmation tests.

### Prompt Attestation

The executing parent observed and answered actual prompts. Controlled second
process changes completed before answers; private receipts preserve choices,
status counts, whole sets and metadata. The gatekeeper reviewed the method but
did not independently witness the interactive prompts.

### Failure Accounting

The importer stopped at the failing row, retained prior successful writes and
left pending rows untouched. Prepared/completed/failed/pending and per-status
counts reconciled. The native denied write was ADException 8344; temporary
WriteProperty denial was confined to one owned user and exact original ACL
state was verified after each variant. No whole-file rollback is claimed.

## Harness Findings And Recovery

An unbounded error-serialization attempt was stopped and corrected, an adapted
property/base-member mismatch blocked setup before ACL change, and an expected
.NET exception type was corrected to the observed native AD exception. Earlier
failed attempts remain in private receipts; corrected scenarios have their
own results. Harness repairs are not manufactured production fixes.

## Cleanup

Cleanup and independent read-only verification confirmed all four users, the
group and both OUs absent, no temporary ACL/process left, and parent preserved.
Only owned objects were removed; OUs were deleted only when empty.

## Three Review Standards

| Standard / Role | Method And Contribution | Evidence Boundary |
| --- | --- | --- |
| Contract correctness / builder | Traced public APIs; built independent identity, ambiguity, literal-lookup and projection matrices. Parent executed 104 checks. | Offline construction alone was not live proof. |
| Test integrity / critic | Fresh-process absent/preexisting sentinels, repeated runs and excluded integration discovery exposed function/logger/handler leaks and discovery initialization. Tracked in [issue #18](https://github.com/jonathanweinberg/DrunkenAD/issues/18). | Test-harness findings, not production AD mutation. |
| Operational acceptance / strategist-gatekeeper | Compared all 26 proposals against scope, source identity, prompts, restoration, cleanup and topology. | Reviewed methods; did not independently execute every live assertion. |

The builder expanded behavior coverage; the critic found defects in the test
environment; the gatekeeper constrained conclusions. All required GUID-bound
ownership, independent readback and truthful gaps. Three reviews are not three
independent live runs.

## Remaining Evidence Gaps

### Test Integrity Follow-Up

`53e2986` repaired function/handler/logger restoration and moved integration
initialization into selected runtime setup. Its own offline receipt had 385
local passes and a direct native-Windows unit run with 384 passes/one platform
skip; 19 live cases were excluded. The Windows full release gate was blocked by
missing Git, so that direct unit result is not a full gate pass. Production
source stayed unchanged. Later counts belong to their own candidates.

No authorized live setup was rerun under that exhausted allowance. The later
separate one-user attempt was [interrupted and cleaned up](SINGLE-DC-VALIDATION-2026-10-08.md),
not a completed new integration result.

### Unproven Environments

Range retrieval, authentic Excel exports, aliases/multi-DC/RODC behavior,
schema mutation/representative extended schemas, least-rights actors,
member-host and PS7 native/compatibility runtimes, enterprise profiles and
current scale remain separate gaps. The replacement capacity test also needs
its own fresh authorized receipt. No gap authorizes new infrastructure,
installation or fixture mutation. Restricted deferrals need owner acceptance;
release/tagging remains held and no issue closure or merge is implied.
