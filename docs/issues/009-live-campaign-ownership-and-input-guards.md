# Issue 009: Live Campaign Ownership And Input Guards

Status: Implemented on `codex-bug-hunt-2026-07-16`; live-lab verification pending

GitHub issue: [#9](https://github.com/jonathanweinberg/DrunkenAD/issues/9)

## Summary

A read-only safety audit found that the tracked host/guest live-campaign harness
can mutate or delete users without first proving campaign ownership and exact
input identity. No live campaign or AD mutation was run during this audit.

## Confirmed Finding 1: Unowned Users Are Pruned

The guest campaign builds an expected set from the current seed manifest, then
deletes every other user below the campaign root OU with confirmation disabled.
A smaller profile run after a larger profile can therefore delete otherwise
valid campaign users, and an unrelated user placed below that root can also be
deleted without a durable ownership marker.

Acceptance criteria:

- the default campaign never deletes an unexpected user
- unexpected root-OU users cause a fail-closed error before seed reconciliation
- any future prune mode requires explicit consent, `ShouldProcess`, and durable
  campaign ownership evidence

## Confirmed Finding 2: Domain-Wide User Adoption

Seed reconciliation searches the whole domain with an unescaped LDAP filter. A
same-named account outside the campaign OU can be moved, renamed, and overwritten
as if it were campaign-owned.

Acceptance criteria:

- seed lookup is restricted to the verified campaign root OU
- LDAP filter values are escaped literally
- lookup failures are terminating and ambiguous matches are rejected
- the campaign never moves an account from elsewhere in the domain

## Confirmed Finding 3: Manifest And CSV Identity Drift

Preflight compares only row counts. A same-length CSV with different identities
can pass and direct namespace writes at users that are absent from the manifest.

Acceptance criteria:

- both sources require nonblank, case-insensitively unique SamAccountName values
- manifest and CSV identity sets must match exactly before any AD mutation
- set differences are reported without dumping source rows

## Confirmed Finding 4: Root OU DN Injection

`RootOuName` is interpolated directly into a distinguished name. DN separators
in a custom value can relocate the campaign's search and mutation scope.

Acceptance criteria:

- the root name accepts only one bounded, human-readable OU label
- DN metacharacters and path injection are rejected by parameter binding
- the computed root's immediate parent remains the verified domain DN

## Confirmed Finding 5: Mutation Reported As Unchanged

`Set-ManagedSeedUser` can move or rename a user and then return `Unchanged` when
its attributes already match. Campaign counts and reports understate mutation.

Acceptance criteria:

- move, rename, and attribute changes all produce `Updated`
- only a truly untouched object produces `Unchanged`

## Confirmed Finding 6: Unsupported Seed Count Override

The host accepts an arbitrary `SeedCount`, while the guest validates the fixed
profile count. The host also writes generated inputs to shared fixture paths
before the guest rejects the count.

Acceptance criteria:

- profile selection is the sole seed-count authority
- generated manifest and CSV files are immutable per-run inputs under the ignored
  run directory, not shared tracked fixture paths
- the guest receives those exact run-specific paths
- operator notes record input paths and hashes

## Additional Design Risks

- host and guest scripts lack campaign-level `ShouldProcess` controls
- direct guest execution does not require rollback-point evidence
- generated launcher string arguments are not safely escaped
- created OUs disable accidental-deletion protection
- retries and partial-failure recovery are weak

## Planned Validation

- source-level Pester regressions for each fail-closed invariant
- parser and documentation hygiene checks
- default unit suite and full release-readiness gate using trusted Pester 5.7.1
- no live AD execution as part of this issue

## Implementation

- removed implicit pruning and made unexpected root users a fail-closed condition
- constrained seed lookup to the verified campaign root with literal LDAP escaping
- required exact, nonblank, case-insensitively unique manifest/CSV identity sets
- constrained the root OU name and preserved accidental-deletion protection
- counted move and rename operations as updates
- removed the independent seed-count override and generated unique per-run inputs
- recorded SHA-256 input hashes in operator notes
- added host and guest `ShouldProcess` gates with required rollback evidence
- required the seed password only after confirmation through the guest environment
- built the guest launcher from single-quoted literal-safe arguments
- removed use of a runtime API unavailable in Windows PowerShell 5.1

## Validation Evidence

The new source-level regressions first failed in four groups against the prior
implementation. After the bounded changes:

- every tracked PowerShell file parses successfully
- the trusted Pester 5.7.1 default run discovers 92 tests
- 86 tests pass, 0 fail, and 6 integration tests remain intentionally not run
- no live AD command or campaign was executed

The final trusted branch gate later reached 100 discovered tests: 94 passed, 0
failed, and 6 environment-gated integration tests were not run. The issue
remains open for review and a controlled live-lab `Quick` campaign after a green
remote matrix and an explicitly approved mutation window are available.

## Current GitHub State

- GitHub Issue [#9](https://github.com/jonathanweinberg/DrunkenAD/issues/9)
  is open with `bug` and `maintenance` labels.
- Its evidence comment links implementation commit `50cd9a9`, delivery commit
  `43fccb3`, and draft PR
  [#12](https://github.com/jonathanweinberg/DrunkenAD/pull/12).
- Keep the issue open for review and future live-lab verification.
