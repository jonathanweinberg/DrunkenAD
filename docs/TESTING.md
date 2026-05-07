# Testing DrunkenAD

DrunkenAD now has three validation layers:

- local parser and unit tests
- an opt-in integration suite against a live AD environment
- a larger live campaign harness for the Parallels lab VM

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

Run both parser and unit tests with:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Invoke-DrunkenADTests.ps1
```

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

## Live Campaign Harness

The higher-fidelity lab workflow lives under [tests/Live/Invoke-DrunkenADLiveCampaign.ps1](../tests/Live/Invoke-DrunkenADLiveCampaign.ps1) and [tests/Live/Invoke-DrunkenADGuestCampaign.ps1](../tests/Live/Invoke-DrunkenADGuestCampaign.ps1).

That harness is designed for the `WindowsServer2025_ADDNS` Parallels VM. It:

- creates a distinct pre-mutation snapshot
- ensures the `DrunkenAD_CODEX` shared folder is available in the guest
- verifies domain and schema readiness before any write
- reconciles the deterministic 3,000-user seed population
- runs CSV ingestion, projection, and CRUD validation phases
- writes timestamped reports under `tests/Live/results/<timestamp>/`

Run it with:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Live/Invoke-DrunkenADLiveCampaign.ps1
```

Use `-VmWrapperPath` or `DRUNKENAD_VM_WRAPPER_PATH` if the Parallels guest
PowerShell wrapper is not in one of the repo-relative default locations:
`VM/Invoke-WindowsAddnsGuestPowerShell.ps1`,
`../VM/Invoke-WindowsAddnsGuestPowerShell.ps1`, or
`../Codex/VM/Invoke-WindowsAddnsGuestPowerShell.ps1`.

The `tests/Live/results/` directory is intentionally ignored by Git. Treat it as run output, not source content.

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

The repository includes a GitHub Actions workflow at [.github/workflows/powershell-ci.yml](../.github/workflows/powershell-ci.yml).

It runs:

- syntax parsing through [scripts/Test-DrunkenADSyntax.ps1](../scripts/Test-DrunkenADSyntax.ps1)
- the unit test suite through [tests/Invoke-DrunkenADTests.ps1](../tests/Invoke-DrunkenADTests.ps1)

That keeps default CI fast while the environment-dependent integration suite and live campaign remain opt-in operator workflows.
