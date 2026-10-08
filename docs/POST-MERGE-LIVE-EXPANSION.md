# Expanded Single-Controller Review Receipt

Date: 2026-10-08. Tracking: [issue #16](https://github.com/jonathanweinberg/DrunkenAD/issues/16)
and [PR #17](https://github.com/jonathanweinberg/DrunkenAD/pull/17).
This supplements the [26-case matrix](POST-MERGE-VALIDATION.md), not a release
approval or a claim that every proposed environment has passed.

## Candidate And Boundaries

The loaded module was the immutable source at
`038013b804305bc2292b96c7f76b2a51059ca4b6`. All 20 module files were compared
with a SHA-256 manifest built from that Git tree. The independent gatekeeper
checked the manifest's completeness locally; the parent checked its remote
contents. Later test-isolation changes are separate and were not part of this
live run. Unchanged module bytes do not create a new-head live-suite receipt.

Runtime: Windows Server 2025, Windows PowerShell 5.1.26100.32684, native
ActiveDirectory 1.0.1.0, one writable controller. Native AD command provenance
was checked in fresh processes, separate from unit-test sessions. Endpoint
observations concern real command bindings and write-origin metadata, not
physical routing guarantees in other topologies.

Four disabled temporary users, one nonprivileged distribution group, and two
temporary OUs were created inside the pre-existing authorized test OU. Together
with the two prior one-user runs, this exhausted the conservative six-user
allowance. No further setup or integration run is implied. No schema, DNS,
infrastructure, existing-user, or seeded-campaign change was made. The rollback
point was verified before fixture creation.

All names below are synthetic row labels. Credentials, live identifiers, raw
transcripts, directory values, ACLs, and private paths remain outside Git.

## Results

| Review Case | Observed Result | Limit |
| --- | --- | --- |
| 5: Unicode supplement | Compatibility demo wrote accents, CJK and a supplementary character; generic and prefixed readers returned exact values; removal preserved the complete unrelated set. Source attribute and drink values restored. | Supplements the five-path integration receipt; not all Unicode/exporter/runtime combinations. |
| 6: Identity and ambiguity | 64 public-API checks passed: five identity modes across eight APIs, then employeeID/mail/pager two-match rejection across all eight. Independent state and metadata checks protected both decoys. | CSV remains SamAccountName-only by contract; no duplicate UPN provisioning. |
| 7: Literal LDAP characters | 32 public-API checks passed for mail and employeeID with star-only and combined star/parentheses/backslash values. A wildcard control matched the two intended fixtures; literal lookups selected only the exact target. | Native runtime and these attribute/character combinations only. |
| 10: Real confirmation | Four actual ConsoleHost scenarios passed: mixed choices, No to All, owned drift rejection, and unrelated drift preservation. Prompt observations are recorded below. | No claim of an atomic lock after the final read. |
| 11: Rename/move | Both pre-refresh and during-target-prompt moves/RDN/account-name changes succeeded using the captured ObjectGUID; four rows written with complete independent state checks. | No after-final-refresh atomic rename guarantee. |
| 11: Partial failures | Three temporary property-denial variants and a controlled middle-row deletion passed with reconciled counters, unchanged pending rows, and independent read-back. | Privileged actor with an object-specific deny is not a least-privilege or read-only account test. |
| 12: Endpoint forms | Seven forms passed: omitted, domain DNS, NetBIOS domain, controller FQDN, controller short name, IPv4, and explicit port 389. Each recorded 13 native AD binding events, one write, full-state equality and matching originating-controller metadata. | Existing DSA-alias prerequisite failed DNS resolution before any write; overall case remains Partial. Single-controller success does not prove multi-controller locator stability. |
| 14: Native projection | Eight public checks passed: projection and compatibility wrapper, populated and emptied sources, en-US and de-DE. Actual proxyAddresses, separator-bearing membership DN, typed whenCreated and department produced equal invariant results. | Native 5.1 only; PowerShell 7 compatibility objects remain untested. |

Cases 6, 7 and 14 comprise **104 public-API checks**, not 104 Pester cases.
Guard/assertion counts are not added to test counts. The ten confirmation and
failure scenarios are separate from the checked-in 19-case integration suite.

### Prompt Attestation

The parent observed the real ConsoleHost prompts and supplied each answer only
after the expected prompt appeared. Any second-process interference completed
and saved its state before the parent answered. The harness independently
asserted output statuses, complete directory sets and relevant metadata.
The gatekeeper reviewed this method but did not independently witness prompts.

| Scenario | Observed Prompts And Choices | Result |
| --- | --- | --- |
| Mixed choices | A: Yes; B: No; C: Yes to All; no D prompt | Written, Declined, Written, Written |
| No to All | A: No to All; no subsequent prompts | Four Declined; all values and drink versions unchanged |
| Owned drift | A paused; an owned value added; A: Yes | Plan-changed failure; zero completed, three pending; no module change after interference |
| Unrelated drift | A paused; an unrelated value added; A: Yes to All | Four Written; unrelated addition retained |
| Move before target refresh | A paused; B moved/renamed; A: Yes to All | Four Written; B found by GUID at its new location |
| Move during target prompt | A: Yes; B paused and moved/renamed; B: Yes to All | Four Written; second GUID/location check passed |
| Declined then denied | A: No; B: Yes | A Declined; B failed; C and D untouched |
| Deleted middle row | A paused; B removed by recorded GUID; A: Yes to All | A Written; B refresh failed; C and D untouched |

### Failure Accounting

Every failure reported `DrunkenADCsvWriteFailed`. Row numbers include the CSV
header. Each B failure had Prepared=4, Completed=1, FailedRowNumber=3, Pending=2.
Written, NoChange and Declined variants each counted exactly one corresponding
completed outcome and zero in the other counters. Owned drift at A had
Prepared=4, Completed=0, FailedRowNumber=2, Pending=3 and all outcome counters
zero. The failing row is neither completed nor pending. Earlier successful
writes were retained; no rollback claim is made.

The real denial was native `Microsoft.ActiveDirectory.Management.ADException`
with error code 8344. The temporary deny applied only to WriteProperty(drink)
for the current actor on one owned disabled user. Original DACL bytes were
saved before mutation and exact original SDDL verified after every variant.

## Harness Findings And Recovery

- The first owned-drift attempt stopped the write, but recursively serializing
  its full ErrorRecord consumed excessive resources. Only that verified test
  process was stopped; bounded error fields replaced recursive serialization.
  Independent state checks showed no module write after interference. That
  attempt was not counted as a pass; the corrected run passed.
- A permission setup guard initially read an adapted DirectoryEntry property
  instead of its base Guid property and stopped before applying the deny.
  A read-only comparison verified the intended object via both base Guid and
  objectGUID. Base-member access corrected the private harness; restoration
  was checked before retry. No project runtime change followed.
- The first denied-import assertion incorrectly expected a .NET
  UnauthorizedAccessException. The importer correctly retained the native AD
  exception. The revised assertion requires its exact native type and a
  recognized denial code, plus all state/counter checks. The failed-attempt
  receipt was preserved and the corrected scenario rerun.
- Cleanup reconciles a successful exact-GUID absence query after an interrupted
  delete without treating access or transport errors as absence. This recovery
  logic was inspected; no artificial cleanup crash was injected.

These corrections fix review tooling assumptions, not evidence of production
defects. They do not relax ownership or complete-state assertions.

## Cleanup

Cleanup and a separate read-only verification both passed: all four user GUIDs,
the group GUID, and both OU GUIDs are absent; zero marked objects remain; the
original parent OU remains. No temporary ACL or import process remains.
Only owned objects were removed, and OUs were deleted only when empty.

## Three Review Standards

| Standard And Role | Method | Contribution | Evidence Boundary |
| --- | --- | --- | --- |
| Contract correctness: builder | Trace all eight public identity APIs to shared resolution/writes; construct independent ordinal expectations and restoration guards. | Produced executable identity, ambiguity, LDAP-character and native projection matrices. Parent executed all 104 checks successfully. | Builder's offline checks alone were not live proof. |
| Test integrity: critic | Reproduce leaks in fresh processes, use absent/preexisting sentinels, repeat runs, and test default/excluded integration with live flags set. | Confirmed global AD-function leakage, module-local logger stub leakage, and integration discovery initialization; tracked separately in [issue #18](https://github.com/jonathanweinberg/DrunkenAD/issues/18). | Fix/test receipts must identify their own candidate; no production mutation was delegated. |
| Operational acceptance: strategist/gatekeeper | Map all 26 proposals to authorization, topology, real-host evidence, cleanup and supported-scope claims. Independently inspect private harness and source manifest. | Required prompt-count attestation, resumable exact-GUID cleanup, explicit ACL restoration on setup failure, and visible environment gaps. | Did not execute the parent's live commands or independently certify every helper. |

The methods agreed on GUID-bound writes, independent read-back, and not
substituting mocks for directory evidence. They differed productively: the
builder expanded behavior coverage; the critic found defects in the test
environment rather than the module; the gatekeeper showed why successful
tests still cannot support a blanket release recommendation. Parent adjudication
combines their scoped findings without counting three reviews as three live runs.

## Remaining Evidence Gaps

### Test Integrity Follow-Up

Commit `53e2986984b6c02b5dc5042889c7f9dc1716e394` addresses issue #18 in eight
test files plus testing documentation and changelog. Production module bytes
are unchanged from the live-validated `038013b` tree.

- Scope-qualified Function-provider reads/removals failed to capture and
  remove global replacements. Correct provider paths now preserve original
  script blocks and remove only fixture-owned replacements. The logging fixture
  also removes its module-local replacement correctly.
- Handler variables now initialize inside their owning setup and are restored
  or removed during teardown, instead of leaking from discovery.
- Selected integration setup, not file discovery, imports directory modules and
  checks readiness. Primary opt-in is revalidated at execution time.
- Six process-isolated regressions cover absent/preexisting state twice and
  four integration selections. Synthetic modules and import guards prove
  excluded discovery performs zero directory initialization, even with live
  flags set. Synthetic selected readiness deliberately returns not-ready;
  these tests do not prove real integration fixture creation or cleanup.
- Local release gate: 385 passed, zero failed/skipped, 19 excluded. Four
  additional full-runner invocations each passed 385 and preserved the exact
  eight function and eight variable states after each run. Red-first failures
  established both leakage and discovery defects before repair.
- Windows PowerShell 5.1.26100.32684, Pester 5.7.1: 384 passed, zero
  failures/errors, one platform-specific skip and 19 integration excluded.
  Archive SHA-256 was verified and all 123 candidate files matched their Git
  digests. No AD-named function leaked and the real ActiveDirectory module was
  not loaded. The full gate first stopped because Git was absent on the lab
  host; no tooling was installed. This subsequent result is the direct unit
  runner, not a full lab-host release-gate pass. CI owns that platform gate.
- New native child processes follow the existing test pattern and have no
  internal hard timeout. No stuck child remained after verification; a future
  timeout improvement would be a separate runner design change.

The live suite was not rerun after this test-harness change: the authorized
fixture allowance is exhausted. Module equivalence supports the bounded
behavior evidence, not a claim that the changed integration setup ran live.

### Unproven Environments

The large-value-set case remains capacity-blocked before retrieval. Actual Excel
exports, a working alias, multi-DC/RODC behavior, schema changes/extended-schema
fixtures, least-privilege/read-only actors, member-server RSAT, PowerShell 7
native/compatibility, enterprise logging profiles, and scale remain unproven.
No missing prerequisite authorizes installation, account enablement, new
fixtures, infrastructure changes, or a campaign. Deferrals require an explicit
owner decision with support restrictions; they are not silently accepted here.

Release/tagging remains explicitly held by the owner. No issue closure or merge
is implied by this receipt.
