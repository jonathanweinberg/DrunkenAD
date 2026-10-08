# Single-DC Validation Attempt And Cleanup

Date: 2026-10-08. Tracks [issue #16](https://github.com/jonathanweinberg/DrunkenAD/issues/16),
[issue #18](https://github.com/jonathanweinberg/DrunkenAD/issues/18), and
[draft PR #17](https://github.com/jonathanweinberg/DrunkenAD/pull/17).
This receipt supports review of the
[restricted single-DC proposal](SINGLE-DC-ACCEPTANCE-PROPOSAL.md); it does not
accept that proposal, authorize another fixture, or permit merge, issue
closure, release or tagging.

## Candidate And Safeguards

- Tested source: `07d26b914000012cb4b505cdd5c1c0bc89a3f0a2`.
- Archive SHA-256: `1a5fc4b78d079d73fd36df0e8b3c1f8f83e6d82f0d22f370f670d8b372f44c5d`.
- All 22 bundled files were checked against their Git-derived hashes: 20 module
  files, the integration suite and its required sample CSV mapping. The
  production module is unchanged from `038013b`.
- A fresh native Windows PowerShell process verified the candidate module and
  effective ActiveDirectory cmdlet bindings, including the module call scope
  after Pester discovery. No unit-test session was reused.
- Read-only discovery required 27 cases, including 15 opt-in Tier1 cases.
- Existing rollback and directory prerequisites were reverified before the
  owner-authorized run. An approval-scoped atomic marker prevents another
  execution under this approval, even if the candidate changes; it is retained
  on completion or failure.
- One owned disabled temporary user was created inside the pre-existing test
  parent and subsequently removed. No group/OU creation, ACL, schema, DNS,
  infrastructure, existing-user or campaign changes occurred.

Raw XML/JSON, launcher details and exact lab identities stay private. Public
results contain only source identity, sanitized counts, behavior and limits.

## Offline And CI Evidence

The local release gate passed 393 tests, zero failed/skipped, with 27 live cases
excluded. The integration selection regression reflects the expanded suite;
discovering those cases is not executing them against AD.

All five checks passed for the exact candidate:
[PowerShell matrix](https://github.com/jonathanweinberg/DrunkenAD/actions/runs/37855061207)
and [documentation check](https://github.com/jonathanweinberg/DrunkenAD/actions/runs/37855061230).
Downloaded Core result artifacts report macOS 393 passes and Windows/Linux
392 passes plus one platform-specific skip, with zero failures/errors. The
Windows PowerShell 5.1 CI log separately reports 392 passes, zero failures,
one platform skip and 27 live cases excluded. These are unit/CI receipts, not
native AD evidence on those hosted runners.

## Native AD Receipt

**Result: Interrupted - Evidence Gap.** There is no completed Pester result for
this candidate. Do not invent a fresh pass/skip count from earlier receipts,
or report the newly added boundary checks as executed.

- The process stalled in Pester 5.7.1's `Set-ItResult` while recording the
  recognized capacity-prerequisite skip. A read-only runspace stack located
  the call in the integration suite's 1,602-value case. Replication metadata
  remained unchanged across two progress observations while CPU time grew.
- A caller-scope `$file` object in the private launcher was isolated as the
  trigger in a two-case synthetic test, with no AD calls. On both local
  PowerShell 7.6.3 and native Windows PowerShell 5.1, the variant with that
  variable timed out at ten seconds; without it, one test passed and one
  intentional skip completed, followed by normal termination. This identifies
  a private harness/Pester interaction, not a demonstrated module defect.
- The owned process was stopped after verifying its launch identity. The one
  disabled fixture was captured and removed by GUID, with exact absence checks.
  A separate fresh read-only process independently confirmed zero current test
  accounts, zero prior fixture GUIDs remaining, the original parent preserved,
  the owned process absent and the approval marker retained.
- The one-user approval is consumed. No integration retry occurred. The
  executed launcher is preserved privately; a corrected private launcher uses
  nonconflicting variable names. Its synthetic correction is not a new live
  receipt. A future attempt needs fresh authority, an exact reviewed launcher
  and candidate, a synthetic skip preflight and a bounded execution watchdog.

The eight new cases were **not executed**. They cover both public projection
commands, en-US/de-DE and actual native `whenCreated`/`DistinguishedName`
sources on the same fixture.
Each requires exact-limit read-back, invariant rendering, whole-state
preservation and unchanged metadata on overlimit rejection. The DN branch
includes BMP and supplementary characters in the literal prefix. These are
scalar native-source checks, not every multivalue/runtime combination.

## Acceptance Boundaries

The known 1,602-value capacity prerequisite can remain an explicit skip in a
completed run, but must verify unchanged state. Such a completed result would
be `Partial - Evidence Gap`, not a large-set retrieval pass or full acceptance.
This interrupted run did not reach that completed result. The harness stall
must be resolved and the required live assertions rerun before recommending
even the restricted acceptance; it is not an environment deferral to waive.

Actual Excel exports, a working alias/multi-DC/RODC topology, schema enablement
and Exchange/custom-schema environments, least-rights actors, additional
native/compatibility runtimes, enterprise profiles and current scale evidence
remain separate. The proposal lists their revisit triggers. No known gap is
silently converted into accepted risk; the owner must review and explicitly
accept or revise the proposed scope. The release/tag hold remains in force.
