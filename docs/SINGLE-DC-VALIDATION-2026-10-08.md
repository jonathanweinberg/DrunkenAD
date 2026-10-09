# Single-DC Validation Attempt And Cleanup

Historical receipt, 2026-10-08. Tracks [issue #16](https://github.com/jonathanweinberg/DrunkenAD/issues/16),
[issue #18](https://github.com/jonathanweinberg/DrunkenAD/issues/18), and
[PR #17](https://github.com/jonathanweinberg/DrunkenAD/pull/17).
Detailed launcher review, hashes, diagnostics and raw receipts are retained
privately. This summary does not authorize another run or accept the
[restricted proposal](SINGLE-DC-ACCEPTANCE-PROPOSAL.md).

## Candidate And Safeguards

Candidate `07d26b914000012cb4b505cdd5c1c0bc89a3f0a2` and all 22 bundled files
were hash-verified. Production module source matched `038013b`. Fresh native
Windows PowerShell command provenance, rollback prerequisites and discovery of
27 integration cases were checked before the owner-authorized attempt.

Only one owned disabled user was created in the existing test parent. No
group/OU creation, ACL, schema, DNS, infrastructure, existing-user or campaign
change occurred. The run-specific approval marker remains consumed.

## Offline And CI Evidence

The local gate passed 393 tests, zero failed/skipped, with 27 live cases
excluded. All five exact-candidate CI checks passed:
[PowerShell](https://github.com/jonathanweinberg/DrunkenAD/actions/runs/37855061207)
and [documentation](https://github.com/jonathanweinberg/DrunkenAD/actions/runs/37855061230).
Hosted macOS had 393 passes; Windows/Linux Core and Windows PowerShell 5.1
reported 392 passes and one platform skip, with zero failures. These are
offline/CI receipts, not hosted native-AD evidence.

## Native AD Receipt

**Interrupted - Evidence Gap.** No completed Pester aggregate exists for this
attempt. Eight new native projection-boundary combinations never executed.
Earlier results must not supply invented pass/skip counts for this run.

The process stalled while Pester recorded a recognized capacity-prerequisite
skip. A private caller-scope variable collision reproduced the stall in a
synthetic test on both tested PowerShell runtimes. Removing that collision
allowed the deliberate skip to finish. This is a demonstrated launcher/Pester
interaction, not a demonstrated production module defect or evidence that
skips are inherently broken.

The verified owned process was stopped. The disabled fixture was captured and
removed by GUID. A separate fresh read-only check confirmed current/prior
fixture absence, parent preservation, process absence and retained approval
marker. Cleanup is verified; completion of the interrupted suite is not.

## Synthetic Retry Preparation

The corrected private launcher completed its synthetic-only preflight: one
pass, one intentional skip, zero failures, no AD load and unchanged consumed
marker. Eight watchdog controls also passed on local PowerShell 7 and native
Windows PowerShell 5.1, covering exit outcomes, both output streams, timeout,
near-deadline exit, script-hash and argument rejection.

These controls prepare a possible retry; they are not native directory proof.
The watchdog bounds its main wait, not all startup/termination/drain time; it
stops only the retained direct child. Termination does not prove Pester teardown
or directory cleanup. A future run needs fresh authority, renewed prerequisites,
exact reviewed source/launcher and an independent cleanup plan.

## Acceptance Boundaries

The historical capacity setup skip did not validate range retrieval. Review 5
replaces that scenario with a separately opted-in [bounded capacity test](TESTING.md#bounded-capacity-characterization),
which has no fresh live receipt. The eight native projection-boundary cases
still require execution; synthetic controls and source identity cannot replace
them. The interrupted attempt cannot be waived as a completed acceptance run.

The [matrix](POST-MERGE-VALIDATION.md) retains exporter, topology, schema, actor,
runtime, profile and scale gaps. Restricted acceptance remains proposed;
merge, issue closure and release/tagging remain separate owner decisions.
