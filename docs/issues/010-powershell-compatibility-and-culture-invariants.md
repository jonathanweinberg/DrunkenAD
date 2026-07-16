# Issue 010: PowerShell Compatibility And Culture Invariants

Status: Implemented on `codex-bug-hunt-2026-07-16`; remote CI and live-lab verification pending

GitHub issue: [#10](https://github.com/jonathanweinberg/DrunkenAD/issues/10)

## Summary

A separate compatibility review reproduced four defects across locale-sensitive
prefix ownership, script-level common parameters, JSON null conversion, and the
inline live-smoke fallback. It also found one PowerShell 5.1 coverage gap. No AD
commands or live campaign were run while reproducing these defects.

## Confirmed Finding 1: Prefix Ownership Changes With Process Culture

Prefix-overlap validation uses ordinal, case-insensitive comparison, but public
read and write filtering uses culture-sensitive regular-expression matching.
Under the Turkish culture, `file-` does not match an existing `FILE-` namespace,
so reads can omit owned values and replacements can leave stale values behind.

Acceptance criteria:

- prefix ownership uses `OrdinalIgnoreCase` consistently for validation, reads,
  writes, and the live-campaign oracle
- a Turkish-culture regression proves reads and replacement remain invariant
- literal prefixes containing regular-expression metacharacters still work

## Confirmed Finding 2: Schema Script Cannot Bind Documented Common Parameters

The nested schema function supports `ShouldProcess`, but the executable script
entrypoint does not. As a result, the documented script invocation cannot bind
`-Confirm` or `-WhatIf` before it can forward those parameters to the function.

Acceptance criteria:

- executable-script metadata exposes `Confirm` and `WhatIf`
- script and nested function both retain high-impact confirmation semantics
- the existing preview-only default remains unchanged

## Confirmed Finding 3: JSON Null Values Fail Before Conversion

`ConvertTo-DrunkenADHashtable` explicitly handles null, but its mandatory input
parameter rejects null during binding. A nested JSON null therefore fails during
recursive conversion before the intended branch runs. The red test also exposed
that a single-item JSON array is unrolled into a scalar during conversion.

Acceptance criteria:

- the converter explicitly accepts null input
- nested null values survive conversion without a binding error
- single-item arrays retain their array shape
- downstream mapping validation remains responsible for rejecting invalid
  required fields

## Confirmed Finding 4: Empty Smoke Result Cannot Reach Its Assertion

The inline smoke fallback checks successful namespace removal by passing an
empty expected array. Its assertion function marks that array mandatory without
allowing an empty collection, so parameter binding rejects the successful state.

Acceptance criteria:

- an empty expected array is a valid assertion input
- the live-campaign source test protects this contract
- nonempty comparison behavior remains unchanged

## Compatibility Coverage Gap

The module manifest declares Windows PowerShell 5.1 compatibility, while CI uses
PowerShell Core even on Windows. Two uses of `Path.GetRelativePath`, which is not
available on the Windows PowerShell 5.1 runtime, were removed during the live
campaign safety slice. A dedicated Windows PowerShell 5.1 lane is required to
prevent similar drift.

## Planned Validation

- red/green Pester regressions for each confirmed defect
- Turkish-culture execution in `try`/`finally` with culture restoration
- syntax, documentation, and architecture checks
- full release-readiness gate with trusted Pester 5.7.1
- source audit for remaining culture-sensitive prefix filters
- no live AD execution

## Implementation

- replaced culture-sensitive prefix regex filters with `OrdinalIgnoreCase`
  `StartsWith` comparisons in public reads, public writes, and the live oracle
- added Turkish-culture read and replacement regressions with culture restoration
- enabled high-impact `ShouldProcess` common parameters on the executable schema script
- allowed null converter input and preserved single-item enumerable shape
- allowed the inline smoke assertion to accept an empty expected collection
- removed all tracked uses of `Path.GetRelativePath`
- added a Windows PowerShell 5.1 Desktop CI job using pinned Pester 5.7.1

## Validation Evidence

The first trusted Pester 5.7.1 run discovered 97 tests and failed five tests:
JSON null binding, Turkish-culture read ownership, Turkish-culture replacement,
empty smoke expectation, and schema script common-parameter metadata. After the
bounded fixes:

- 91 tests pass, 0 fail, and 6 integration tests remain intentionally not run
- no culture-sensitive prefix regex or `Path.GetRelativePath` call remains in tracked PowerShell
- the workflow YAML parses successfully
- no live AD command or campaign was executed

The new Windows PowerShell 5.1 job still needs its first remote CI run after the
branch can be pushed. Keep this issue open until that evidence is attached.

## GitHub Handoff

When authentication is restored:

1. Create a GitHub issue using this note as the body.
2. Add commit-linked red/green evidence.
3. Keep the issue open until the Windows PowerShell 5.1 lane passes remotely and
   a controlled live-lab validation window is available.
