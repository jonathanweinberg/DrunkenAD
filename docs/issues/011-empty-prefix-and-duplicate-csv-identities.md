# Issue 011: Empty Prefix And Duplicate CSV Identities

Status: Implemented on `codex-bug-hunt-2026-07-16`; review pending

GitHub issue: [#11](https://github.com/jonathanweinberg/DrunkenAD/issues/11)

## Summary

A public-command input-boundary sweep found two deterministic local-input bugs.
An explicitly empty read prefix broadens into an unfiltered read, while duplicate
CSV identities perform order-dependent repeated writes to the same user.

## Confirmed Finding 1: Empty Prefix Broadens The Read

`Get-ADUserDrinkData -Prefix ''` currently evaluates `StartsWith('')`, which is
true for every string. An operator asking for an empty namespace therefore gets
all stored values instead of a local validation error.

Acceptance criteria:

- a supplied prefix cannot be null, empty, or whitespace
- invalid prefix input fails before schema or AD lookup
- omitting `-Prefix` continues to return the full data set

## Confirmed Finding 2: Duplicate CSV Identities Are Order Dependent

CSV import validates columns but not row identity uniqueness. Two rows for the
same `SamAccountName`, including case or surrounding-whitespace variants, invoke
two namespace replacements and make the final value depend on row order.

Acceptance criteria:

- nonblank CSV identities are trimmed and compared case-insensitively
- duplicates fail before schema readiness or any user write
- the error reports the duplicate identity without dumping row content
- the existing warning-and-skip behavior for blank identities remains unchanged

## Planned Validation

- red/green Pester tests for both local-input failures
- full trusted Pester 5.7.1 release-readiness gate
- no live AD execution

## Implementation

- rejects a supplied null, empty, or whitespace prefix before schema readiness
- validates trimmed CSV identities with ordinal case-insensitive uniqueness
- trims each accepted identity once for confirmation, write, and result output
- preserves warning-and-skip behavior for blank CSV identities
- documents the uniqueness contract in the ingestion guide and command help

## Validation Evidence

The trusted Pester 5.7.1 red run discovered 99 tests and reproduced both bugs.
After the bounded changes, 93 tests passed, 0 failed, and 6 integration tests
remained intentionally not run. A separate normal-path regression verifies that
` alice ` is written and reported as `alice`. No live AD command was executed.

## Current GitHub State

- GitHub Issue [#11](https://github.com/jonathanweinberg/DrunkenAD/issues/11)
  is open with `bug` and `maintenance` labels.
- Its evidence comments link implementation commit `4dc6a13`, delivery commit
  `43fccb3`, Windows portability commit `c259a1c`, and draft PR
  [#12](https://github.com/jonathanweinberg/DrunkenAD/pull/12).
- Keep the issue open for review.
