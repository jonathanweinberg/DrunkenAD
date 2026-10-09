# Testing DrunkenAD

DrunkenAD now has four validation layers:

- local parser and unit tests
- an opt-in integration suite against a live AD environment
- a larger host-wrapper live campaign harness for the seeded lab
- a release-readiness gate that composes syntax, docs, manifest, export, and
  unit-test checks

## Parser And Unit Tests

The parser gate lives at [scripts/Test-DrunkenADSyntax.ps1](../scripts/Test-DrunkenADSyntax.ps1). The unit suite lives at [tests/DrunkenAD.Unit.Tests.ps1](../tests/DrunkenAD.Unit.Tests.ps1), with additional schema-enable coverage in [tests/SchemaEnablement.Unit.Tests.ps1](../tests/SchemaEnablement.Unit.Tests.ps1).

Those tests focus on the safety-critical behavior:

- exact LDAP user resolution
- literal prefix matching
- prefix map construction
- no-op detection when nothing changed
- prefix-scoped additions/removals, including a concurrent unrelated addition
- one pinned DC and schema context per write or CSV operation
- inherited and auxiliary schema classes and schema value limits
- `-WhatIf` handling
- the difference between schema presence and actual user-write readiness
- the admin-only schema enablement script guards
- first-class `Get-Help` coverage for every exported command and the
  `about_DrunkenAD` topic

The test runner requires exactly Pester 5.7.1. Run the unit tests with:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Invoke-DrunkenADTests.ps1
```

For an offline or isolated environment, pass a trusted, fully qualified Pester
5.7.1 manifest path outside the repository's live-result storage:

```powershell
pwsh -NoLogo -NoProfile `
    -File /temp/DrunkenAD/tests/Invoke-DrunkenADTests.ps1 `
    -PesterManifestPath /opt/powershell/modules/Pester/5.7.1/Pester.psd1
```

The runner prints the resolved Pester version and manifest path, and discovers
only its explicit top-level test allowlist. Discovery or container failures fail
the process even when Pester reports zero individual failing tests.

Default unit selection excludes integration execution even when live environment
flags are present. Integration discovery performs no module initialization or AD
readiness calls; those occur only in the selected integration `BeforeAll`.
Unit fixtures restore preexisting AD-named functions and test handler variables,
or remove the replacements they own. Process-isolated regression tests exercise
both absent and preexisting state across repeated runs. Continue to use a fresh
process for live work and verify native command provenance before mutation.

If you only want the parser gate:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/scripts/Test-DrunkenADSyntax.ps1
```

## Integration Tests

The integration suite lives in [tests/DrunkenAD.Integration.Tests.ps1](../tests/DrunkenAD.Integration.Tests.ps1).

It is skipped unless all of the following are present:

- `DRUNKENAD_RUN_INTEGRATION=1`
- `DRUNKENAD_TEST_DC`
- `DRUNKENAD_TEST_DNS_SUFFIX`

Before a writable-directory fixture can be created, also provide:

- `DRUNKENAD_TEST_USER_OU`, naming an existing test OU
- `DRUNKENAD_TEST_JOURNAL_DIRECTORY`, an absolute path to a new, empty,
  pre-existing private directory outside the checkout

Prepare that directory with owner-only access on the test host. The journal
helper rejects checkout paths, reparse points and reused/nonempty directories;
it does not configure or certify filesystem permissions. Discovery and a
readiness-blocked run create no journal or fixture.

Example:

```powershell
$env:DRUNKENAD_RUN_INTEGRATION = '1'
$env:DRUNKENAD_TEST_DC = 'dc01.contoso.com'
$env:DRUNKENAD_TEST_DNS_SUFFIX = 'contoso.com'
$env:DRUNKENAD_TEST_USER_OU = 'OU=Drink Ops,DC=contoso,DC=com'
$env:DRUNKENAD_TEST_JOURNAL_DIRECTORY = 'C:\PrivateTestEvidence\unique-run'
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Invoke-DrunkenADTests.ps1 -IncludeIntegration
```

The integration suite now checks `Test-ADDrinkAttributeReadyForUserWrite`, not just `Test-ADDrinkAttributeEnabled`.

That means it validates one of two outcomes:

- `drink` is ready for user writes, so the suite creates a temporary user and exercises write/remove behavior end to end
- `drink` exists but is not writable on the `user` class, so the suite surfaces the blocking reason and skips the write-path assertions instead of failing with a less precise AD error later

When the environment is ready, the live integration tests validate:

- readiness for user writes
- prefixed writes end to end
- literal prefixes with regex metacharacters
- replacement of one namespace without disturbing another
- cleanup of the temporary test user
- CSV ingestion against a temporary CSV source
- projection of AD attributes into default namespaces

### Fixture Ownership And Interruption

Setup writes an exclusive, flushed creation-intent record before its single
create attempt. The disabled fixture carries a run-specific description
marker. Its returned GUID is recorded and checked before test-data writes.
Every fixture-producing mode binds the readiness result to a positively
verified canonical writable DC. Setup also rechecks the original parent GUID
and the new user's immediate-parent membership before admitting test writes.
No password is written to the journal. These private records contain directory
identities and must never be committed or attached to public issues.

Marker, handle and journal-protocol strings require exact ordinal equality.
Case changes or added invisible Unicode characters are mismatches, not aliases;
the helper rejects them before admitting a write or ownership assertion.

Normal cleanup verifies the recorded parent, GUID, description marker and
disabled state, then removes only that GUID. It never falls back to a name or
prefix deletion. A delete error is not proof that the delete failed: successful
same-target absence and parent checks may establish cleanup afterward. Failed
reads, mismatched ownership, partial journal writes and uncertain creation stay
explicitly incomplete. Retained journal files are not reusable approval markers.

Forced termination can bypass Pester cleanup. A surviving controller must
retain process identity and reconcile the journal independently; an absent GUID
in an interrupted creation record does not mean no account was created. Do not
retry creation, clear the journal, or delete a same-named object to recover.
This journal is evidence for narrowly authorized reconciliation, not authority
to perform it or a guarantee that a timed-out directory call was rolled back.
The private controller and fresh native recovery evidence remain separate gates.

### Expanded Single-DC Checks

After separately authorizing the bounded Tier 1 scope, set
`DRUNKENAD_RUN_TIER1=1` as well as the existing integration variables. Tier 1
also requires `DRUNKENAD_TEST_USER_OU` to name a pre-existing lab OU. The suite
uses the same one disabled temporary account, journals its GUID, and verifies
cleanup. Fifteen extra cases probe stale Remove, duplicate/case-variant Add,
live length boundaries, Unicode across write paths, bounded capacity, no-op
replication metadata, and eight native projection-boundary combinations.
The latter cover both public projection commands, en-US/de-DE, and typed dates
or distinguished names against the actual schema limit. Each case independently
resets only that account; the complete opt-in suite discovers 27 cases.
The capacity case requires its own additional opt-in below; without it only
26 cases are eligible. Expanded cases remain excluded from default CI and from
an ordinary twelve-case run.

Do not count a skipped boundary test or an unknown AD error as a pass. The
full [post-merge matrix](POST-MERGE-VALIDATION.md) distinguishes these automated
areas from identity, interactive-host, ACL, exporter, multi-DC, and environment
checks that need separate protocols and evidence. Run the final candidate,
retain private raw results, and publish only sanitized receipts.

### Bounded Capacity Characterization

Capacity testing additionally requires `DRUNKENAD_RUN_CAPACITY=1`, alongside
the integration and Tier 1 opt-ins and separately approved fixture scope.
The flag alone or a Pester `Capacity` tag filter does not authorize execution.
Use a fresh native ActiveDirectory process and an independently reviewed
launcher with a hard timeout, interruption reconciliation and cleanup plan.
Never reuse a consumed approval marker or change schema/database settings to
force a result. No live evidence exists for this replacement case yet.

Before fixture creation, capacity setup verifies native command provenance and
compares the explicit canonical DC DNS hostname with RootDSE and writable-DC
identity metadata. It also verifies the exact existing OU in that domain.
Aliases, domain selectors, IPs, ports, trailing dots, ambiguous metadata and
RODCs fail this test's precondition; accepted public API endpoint forms are
unchanged. This adds two outer read calls beyond the prior Tier 1 OU lookup.
Outer setup is outside the cooperative case timer and must be covered by the
launcher's external watchdog.

The case grows fixed, distinct ASCII values on the same owned disabled user
and pinned DC. It calls the production scoped writer with one actual marker
removal plus new values. A stable unrelated value must survive every step.

| Bound | Limit |
| --- | --- |
| Namespace payload | At most 1,600 payload values plus one rotating marker, each complete prefixed value exactly 32 UTF-16 code units |
| Whole attribute | At most 1,602 intended values including the unrelated 13-code-unit sentinel; 102,490 UTF-16 text bytes, not database or protocol size |
| Probe requests | At most 13, growing by up to 128 payloads; each removes one marker and adds at most 129 values |
| Attribute writes | At most 16 including initial reset, seed and the existing per-case cleanup reset; shared fixture setup/deletion are separate |
| Time | 120-second cooperative budget; native calls can block, so an external process watchdog remains required |

A recognized server capacity rejection must leave the complete independently
read `drink` set and all captured attribute replication metadata unchanged,
before cleanup. Unexpected errors or changed state fail. Record the last
accepted and first rejected counts, input size, request shape, elapsed time
and cleanup result privately. This is a bracket for that fixture and history,
not an exact or general per-user ceiling. Reaching the bounds without a
verified rejection is an Evidence Gap, not a successful capacity assertion.

The former 1,602-value seed failed before large-range retrieval ran. Replacing
that prerequisite-dependent case does not validate large-range retrieval or
remove it from the evidence matrix. That separate objective still requires a
suitable authorized environment and independent complete-value verification.

## Live Campaign Harness

The higher-fidelity lab workflow lives under [tests/Live/Invoke-DrunkenADLiveCampaign.ps1](../tests/Live/Invoke-DrunkenADLiveCampaign.ps1) and [tests/Live/Invoke-DrunkenADGuestCampaign.ps1](../tests/Live/Invoke-DrunkenADGuestCampaign.ps1).

That harness is designed for a prepared live lab with a host wrapper. The host
method is responsible for rollback, workspace access, guest execution, and
result collection as described in [LIVE-CAMPAIGN-HOSTS.md](LIVE-CAMPAIGN-HOSTS.md). It:

- requires operator confirmation and creates a distinct pre-mutation rollback point
- generates profile-sized, run-specific manifest, CSV, and config inputs
- records SHA-256 hashes for every generated or copied input
- ensures the repository workspace is available in the live lab
- verifies domain, schema, and exact manifest/CSV identity readiness before any write
- reconciles a deterministic seed population only inside the bounded campaign root
- fails closed instead of pruning unexpected users or adopting accounts from elsewhere
- runs CSV ingestion, projection, and CRUD validation phases
- writes timestamped reports under `tests/Live/results/<timestamp>/`

Run the quick profile first:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Live/Invoke-DrunkenADLiveCampaign.ps1 `
    -CampaignProfile Quick
```

Run the default full profile with:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Live/Invoke-DrunkenADLiveCampaign.ps1
```

Profiles are:

| Profile | Seed users | CRUD samples |
| --- | ---: | ---: |
| `Quick` | 30 | 9 |
| `Standard` | 300 | 30 |
| `Full` | 3,000 | 300 |

Use `-VmWrapperPath` or `DRUNKENAD_VM_WRAPPER_PATH` if the host wrapper is not in
one of the repo-relative default locations.

Approved guest mutation requires `DRUNKENAD_SEED_PASSWORD` in the guest process
environment. The password is not accepted as a launcher argument and must not be
written to run artifacts. `-WhatIf` remains available without that environment
variable so operators can preview the campaign boundary first.

The `tests/Live/results/` directory is intentionally ignored by Git. Treat it as
run output, not source content, even when it contains generated guest launchers,
copied PowerShell modules, or wrapper logs from a live run.

## Release Readiness Gate

See the current [release-readiness diagram](DIAGRAMS.md#release-readiness) and
its [Mermaid source](diagrams/release-readiness-flow.mmd).

Run the release-readiness gate before tagging or asking CI to prove the branch:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/scripts/Test-DrunkenADRelease.ps1
```

That script validates manifest metadata, clean module import, exported command
parity, PowerShell syntax, documentation hygiene, first-class command help, and
the default unit suite. It does not publish to PSGallery or require publish
credentials.

## Schema Readiness During Testing

April 9, 2026 exposed the important edge case this repo now models explicitly:

- `Test-ADDrinkAttributeEnabled` can be `True`
- `Test-ADDrinkAttributeReadyForUserWrite` can still be `False`
- write attempts then fail with: `An attempt was made to modify an object to include an attribute that is not legal for its class`

If that happens, stop trying live writes and follow [SCHEMA-ENABLEMENT.md](SCHEMA-ENABLEMENT.md).

## Recommended Workflow

For module changes, the clean loop is:

1. Add or update unit tests first.
2. Run the local parser and unit suite.
3. Check `Test-ADDrinkAttributeReadyForUserWrite` in the target environment.
4. Use `-WhatIf` against the live environment before any write.
5. Run the integration suite.
6. Run the live campaign harness when you need seeded-scale validation.

## CI Notes

The repository includes two GitHub Actions workflows:

- [.github/workflows/powershell-ci.yml](../.github/workflows/powershell-ci.yml) runs the core gate on Ubuntu, macOS, Windows PowerShell Core, and Windows PowerShell 5.1 Desktop with pinned Pester 5.7.1.
- [.github/workflows/documentation-ci.yml](../.github/workflows/documentation-ci.yml) runs documentation hygiene checks.

The PowerShell workflow:

- installs the pinned Pester version used by CI
- validates the module manifest
- parses tracked PowerShell files through [scripts/Test-DrunkenADSyntax.ps1](../scripts/Test-DrunkenADSyntax.ps1)
- runs release-readiness checks through [scripts/Test-DrunkenADRelease.ps1](../scripts/Test-DrunkenADRelease.ps1), which invokes the unit suite once through [tests/Invoke-DrunkenADTests.ps1](../tests/Invoke-DrunkenADTests.ps1)
- executes on Ubuntu, macOS, and Windows
- uploads per-OS Pester XML results as short-lived artifacts

The documentation workflow:

- rejects machine-specific checkout paths
- verifies Markdown link and image targets
- fails if live campaign output under `tests/Live/results/` is tracked

That keeps default CI fast while the environment-dependent integration suite and live campaign remain opt-in operator workflows.
