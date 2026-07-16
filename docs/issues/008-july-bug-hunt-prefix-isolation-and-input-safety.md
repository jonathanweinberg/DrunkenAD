# Issue 008: July Bug Hunt - Prefix Isolation And Input Safety

Status: In progress

GitHub issue: pending; local `gh` authentication was invalid on 2026-07-16.

## Summary

A focused July 2026 bug hunt is reviewing the module's write, CSV, live-campaign,
and validation boundaries. Confirmed fixes will be developed test-first on
`codex-bug-hunt-2026-07-16`, with GitHub issue/comment updates staged for the
next authenticated session.

## Confirmed Finding 1: Overlapping Prefixes

`Set-ADUserDrinkPrefixedData` processes each prefix by removing every current
value that starts with that prefix and then adding replacements. A single map
containing overlapping keys such as `Profile-` and `Profile-Tier-` is ambiguous:
processing the broader prefix after the narrower prefix removes the narrower
replacement, while the reverse order retains it.

Impact:

- one request can produce order-dependent final values
- a caller can silently erase a sibling namespace
- the current tests prove literal matching but do not reject prefix overlap

Acceptance criteria:

- overlapping prefixes are rejected before AD readiness checks or user lookup
- matching is case-insensitive, consistent with current PowerShell/regex behavior
- non-overlapping literal prefixes continue to work
- focused and release-readiness tests pass

## Confirmed Finding 2: CSV Preflight Order And Empty Input

`Import-ADUserDrinkCsvData` checks live AD schema readiness before parsing and
validating the local CSV and namespace configuration. This prevents an operator
from diagnosing malformed input offline, including during `-WhatIf`. In
addition, a CSV that imports zero data rows currently returns without output or
an error, which can be mistaken for a successful no-op.

Impact:

- invalid local input can be masked by an unrelated AD connectivity or schema error
- local preflight unnecessarily depends on live infrastructure
- an empty or header-only source can report success without importing anything

Acceptance criteria:

- path, configuration, mappings, and CSV columns are validated before AD readiness
- a zero-row CSV fails with a deterministic error
- invalid local input performs no AD readiness check and no user write
- valid imports retain the existing readiness and `ShouldProcess` protections

## Evidence

- `DrunkenAD/Public/Set-ADUserDrinkPrefixedData.ps1` removes matching values in a
  loop over `PrefixMap.Keys`.
- `tests/DrunkenAD.Unit.Tests.ps1` covers regex metacharacters and unrelated
  values, but not nested prefix ownership.
- Baseline `scripts/Test-DrunkenADRelease.ps1` passed with 66 tests and 0
  failures before changes.
- The overlapping-prefix regression test failed before implementation because
  the command reached AD readiness instead of rejecting the ambiguous map.
- The CSV preflight regressions failed before implementation because the AD
  readiness mock preempted both malformed-column and zero-row validation.
- After implementation, `tests/Invoke-DrunkenADTests.ps1` passed 71 tests with
  0 failures and 6 integration tests not run.
- After implementation, `scripts/Test-DrunkenADRelease.ps1` passed PowerShell
  syntax, architecture-map, documentation-hygiene, and the 71-test default suite.

## Implementation

- Reject case-insensitive nested prefix namespaces before AD readiness or lookup.
- Parse and validate CSV/config input before the AD readiness gate.
- Accept an empty array at the CSV validator boundary and fail it with the
  deterministic `does not contain any data rows` message.
- Preserve readiness and `ShouldProcess` behavior for valid imports.

## GitHub Handoff

When authentication is restored:

1. Create a GitHub issue using this note as the body.
2. Add commit-linked comments for each confirmed fix.
3. Leave the issue open for review unless explicitly authorized to close it.
