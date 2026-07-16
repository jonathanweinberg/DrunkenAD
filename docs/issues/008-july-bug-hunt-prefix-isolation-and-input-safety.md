# Issue 008: July Bug Hunt - Prefix Isolation And Input Safety

Status: Implemented locally; review pending

GitHub issue: pending; local `gh` authentication was invalid on 2026-07-16.

## Summary

A focused July 2026 bug hunt reviewed the module's write, CSV, live-campaign,
and validation boundaries. Confirmed fixes were developed test-first on
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

## Confirmed Finding 3: Projection Leaves Stale Namespace Data

`Set-ADUserDrinkProjection` is documented to replace every prefix in its
effective attribute map. The projection converter currently omits a prefix when
all of its mapped source attributes are null, empty, or whitespace. If that
prefix already has projected `drink` records, the write command never receives
an empty replacement and those stale records remain indefinitely.

Impact:

- clearing an AD source attribute does not clear its projected representation
- consumers can observe data that no longer matches the source user object
- a projection run can report success while skipping its owned namespace

Acceptance criteria:

- every prefix in the effective projection map appears in the generated data map
- prefixes with no populated source values are represented by an empty array
- the empty replacement flows through `Set-ADUserDrinkData` and normal
  `ShouldProcess` behavior so stale namespace values are removed
- populated and mixed projection maps retain their existing behavior

## Confirmed Finding 4: Public Wrappers Mask Local Input Errors

The preferred generic writer, remover, projection command, legacy updater, and
CSV mapping path do not consistently validate local prefix/map inputs before
querying AD readiness. An invalid request can therefore fail with connectivity
or schema errors before the command reports the actual caller error.

Impact:

- offline preflight behavior differs depending on which public command is used
- malformed maps and legacy arrays can trigger unnecessary AD queries
- overlapping namespace ownership can be diagnosed too late in CSV workflows

Acceptance criteria:

- all public write entry points validate local map shape and prefix ownership first
- empty, blank, overlapping, and mismatched inputs fail deterministically
- invalid input performs no AD readiness query, user lookup, or write
- valid requests preserve the existing readiness and `ShouldProcess` gates

## Confirmed Finding 5: Multivalue Fingerprint Collision

`Set-ADUserDrinkPrefixedData` decides whether a write is needed by sorting each
value array and joining it with newline separators. A single stored value that
contains a newline can produce the same fingerprint as two requested values.
The command then reports no change and skips a required AD update.

Impact:

- one multivalue shape can be mistaken for a different shape
- a legitimate namespace replacement can silently remain unapplied
- quoted multiline CSV fields can make the collision reachable through ingestion

Acceptance criteria:

- equality compares value elements without delimiter-based flattening
- value count and membership both contribute to equality
- existing case-insensitive no-op behavior is preserved unless separately changed
- a one-value-to-two-value newline collision performs the expected write

## Confirmed Finding 6: Blank Labeled CSV Cells Become Records

The CSV converter adds a mapping label before its common record helper checks
for blank values. A blank or whitespace-only source cell mapped with
`Label = 'Tier'` therefore becomes the nonblank stored payload `Tier=` instead
of being omitted like an unlabeled blank cell.

Impact:

- imports can create syntactically present but semantically empty directory data
- labeled and unlabeled mappings handle the same blank source inconsistently
- downstream consumers may treat `Label=` as an intentional value

Acceptance criteria:

- blank source field values are skipped before label formatting
- a blank labeled mapping never emits a label-only record
- other populated mappings on the same row still import normally
- `SplitOn` and non-split mappings keep their existing populated-value behavior

## Confirmed Finding 7: Release Validation Executes Ignored Artifacts

Both default and release test harnesses search `tests/Live/results/*/Modules` when
Pester 5 is not installed, prepend the selected ignored directory to
`PSModulePath`, and import `Pester` by name with only a minimum version. The
runner also gives Pester the entire `tests` directory, allowing recursively
discovered `*.Tests.ps1` files under ignored live results to execute.

Impact:

- untracked run output can execute code inside a trusted release gate
- a fake Pester module can forge a zero-failure result without running real tests
- ignored test files can execute top-level discovery code even when Integration
  tags are excluded
- local release results vary with workstation residue and module inventory

Acceptance criteria:

- no test or release script searches or imports from `tests/Live/results`
- no harness mutates `PSModulePath`
- Pester is imported at exactly version 5.7.1 from an installed module or an
  explicit fully qualified manifest path outside live-result storage
- resolved Pester path and version are printed for provenance
- default discovery runs only an explicit allowlist of tracked top-level tests
- release tests enforce these source-level trust-boundary invariants

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
- The stale-projection regression failed before implementation because an empty
  projected namespace never reached `Set-ADUserDrinkData`.
- Six wrapper-preflight regressions failed before implementation: the empty-set
  helper case was rejected by parameter binding, while malformed generic,
  removal, projection, CSV, and legacy-update input reached AD readiness first.
- After the second implementation checkpoint, `tests/Invoke-DrunkenADTests.ps1`
  passed 78 tests with 0 failures and 6 integration tests not run.
- The second `scripts/Test-DrunkenADRelease.ps1` run passed syntax, architecture,
  documentation hygiene, and all 78 default tests.
- The newline-collision regression failed before implementation because one
  embedded-newline value and two separate values produced the same fingerprint;
  the element-wise comparison passed all 79 tests afterward.
- The blank labeled-cell regression failed before implementation because the
  actual data map contained `Tier=`; source normalization passed all 80 tests.
- The release-provenance invariant failed before implementation on the ignored
  cache function and recursive test root. After removal, the runner failed
  closed when no trusted Pester was installed instead of loading ignored output.
- A fresh official Pester 5.7.1 package supplied by fully qualified manifest
  path passed 81 default tests and the complete release-readiness gate. The
  output identified the exact resolved manifest path and six discovered files.
- Subsequent independent safety, compatibility, and public-input slices grew the
  final branch gate to 100 discovered tests: 94 passed, 0 failed, and 6
  integration tests remained intentionally not run.

## Implementation

- Reject case-insensitive nested prefix namespaces before AD readiness or lookup.
- Parse and validate CSV/config input before the AD readiness gate.
- Accept an empty array at the CSV validator boundary and fail it with the
  deterministic `does not contain any data rows` message.
- Preserve readiness and `ShouldProcess` behavior for valid imports.
- Retain empty projection namespaces so clearing source attributes removes stale
  projected values.
- Apply one case-insensitive, non-overlapping prefix-set contract to the generic
  writer, remover, projection, CSV mapper, and legacy updater before AD readiness.
- Compare multivalue sets element by element without separator flattening.
- Normalize CSV source fields before label formatting and skip blank values.
- Pin Pester to 5.7.1, remove ignored-cache loading and module-path mutation, and
  constrain discovery to six named top-level test files.

## GitHub Handoff

When authentication is restored:

1. Create a GitHub issue using this note as the body.
2. Add commit-linked comments for each confirmed fix.
3. Leave the issue open for review unless explicitly authorized to close it.
