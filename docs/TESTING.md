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
- correct use of `Clear` vs `Replace`
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
only its explicit top-level test allowlist.

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

Optional:

- `DRUNKENAD_TEST_USER_OU`

Example:

```powershell
$env:DRUNKENAD_RUN_INTEGRATION = '1'
$env:DRUNKENAD_TEST_DC = 'dc01.contoso.com'
$env:DRUNKENAD_TEST_DNS_SUFFIX = 'contoso.com'
$env:DRUNKENAD_TEST_USER_OU = 'OU=Drink Ops,DC=contoso,DC=com'
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

![Release readiness](images/documentation-suite-2026-05-11/release-readiness.png)

The source diagram for the release gate lives at
[diagrams/release-readiness-flow.mmd](diagrams/release-readiness-flow.mmd).

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
- runs the unit suite through [tests/Invoke-DrunkenADTests.ps1](../tests/Invoke-DrunkenADTests.ps1)
- runs release-readiness checks through [scripts/Test-DrunkenADRelease.ps1](../scripts/Test-DrunkenADRelease.ps1)
- executes on Ubuntu, macOS, and Windows
- uploads per-OS Pester XML results as short-lived artifacts

The documentation workflow:

- rejects machine-specific checkout paths
- verifies Markdown link and image targets
- fails if live campaign output under `tests/Live/results/` is tracked

That keeps default CI fast while the environment-dependent integration suite and live campaign remain opt-in operator workflows.
