# Live Validation Guide

DrunkenAD is built to support live Active Directory validation around the `drink` attribute as a compact namespaced data store. The key operational distinction is that schema presence is not enough by itself: `drink` must also be writable on the Active Directory `user` class.

## Environment Checklist

For a live run, make sure the environment has:

- RSAT / ActiveDirectory available to the PowerShell host running the tests
- a reachable writable domain controller
- the `drink` attribute present and not defunct in schema
- the `drink` attribute allowed on the Active Directory `user` class
- permission to create and remove temporary test users
- permission to update the `drink` attribute on those users

Use both checks before any write:

```powershell
Test-ADDrinkAttributeEnabled -Server 'dc01.contoso.com'
Test-ADDrinkAttributeReadyForUserWrite -Server 'dc01.contoso.com' -PassThru | Format-List
```

If the first command returns `True` but the second does not, stop there and use [SCHEMA-ENABLEMENT.md](SCHEMA-ENABLEMENT.md).

## Integration Suite

Set these before running the smaller live integration suite:

```powershell
$env:DRUNKENAD_RUN_INTEGRATION = '1'
$env:DRUNKENAD_TEST_DC = 'dc01.contoso.com'
$env:DRUNKENAD_TEST_DNS_SUFFIX = 'contoso.com'
```

Optional:

```powershell
$env:DRUNKENAD_TEST_USER_OU = 'OU=Drink Ops,DC=contoso,DC=com'
```

Then run:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Invoke-DrunkenADTests.ps1 -IncludeIntegration
```

That suite now fails fast on schema-readiness issues by surfacing the blocking reason first, then only running the write tests when `drink` is actually writable on `user`.

## Live Campaign Harness

The larger seeded validation workflow lives at [tests/Live/Invoke-DrunkenADLiveCampaign.ps1](../tests/Live/Invoke-DrunkenADLiveCampaign.ps1). It drives the guest-side orchestration script at [tests/Live/Invoke-DrunkenADGuestCampaign.ps1](../tests/Live/Invoke-DrunkenADGuestCampaign.ps1).

Run it with:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Live/Invoke-DrunkenADLiveCampaign.ps1
```

The harness resolves `Invoke-WindowsAddnsGuestPowerShell.ps1` in this order:
the explicit `-VmWrapperPath` argument, the `DRUNKENAD_VM_WRAPPER_PATH`
environment variable, then repo-relative candidates at
`VM/Invoke-WindowsAddnsGuestPowerShell.ps1`,
`../VM/Invoke-WindowsAddnsGuestPowerShell.ps1`, and
`../Codex/VM/Invoke-WindowsAddnsGuestPowerShell.ps1`.

That workflow:

1. creates a pre-mutation VM snapshot
2. ensures the `DrunkenAD_CODEX` share is mounted into the guest
3. verifies the domain DN, module import path, and `drink` readiness
4. reconciles the deterministic 3,000-user seed population
5. runs CSV ingestion, projection, and CRUD validation phases
6. writes timestamped reports under `tests/Live/results/<timestamp>/`

The results directory is intentionally ignored by Git.

## Smoke Sequence

Use this sequence for a first-pass live validation:

1. Import the module from [DrunkenAD.psd1](../DrunkenAD/DrunkenAD.psd1).
2. Run `Test-ADDrinkAttributeEnabled`.
3. Run `Test-ADDrinkAttributeReadyForUserWrite -PassThru`.
4. If readiness is blocked, stop and resolve schema enablement.
5. Run one `-WhatIf` write with `Set-ADUserDrinkData` or `Set-ADUserDrinkProjection`.
6. Run the local parser and unit suite.
7. Run the integration suite.
8. Run the sample CSV ingestion flow in `-WhatIf` mode or the full live harness if you need seeded-scale validation.

## Validation Narrative

For a clean live walkthrough:

1. Show both schema presence and user-write readiness.
2. Read the sample source file at [drink-ingestion-sample.csv](../examples/data/drink-ingestion-sample.csv) and its mapping file at [drink-ingestion-config.json](../examples/data/drink-ingestion-config.json).
3. Preview the import through `Import-ADUserDrinkCsvData` or [Import-DrunkenADCsv.ps1](../examples/Import-DrunkenADCsv.ps1) with `-WhatIf`.
4. Execute the import for a controlled set of users or use the seeded live campaign.
5. Read the values back with `Get-ADUserDrinkData`.
6. Confirm unrelated namespaces remain untouched.

## Report Outputs

The live harness writes operator-oriented output such as:

- `operator-notes.md`
- `cross-project-excerpt.txt`
- `guest-output.txt`
- `campaign-summary.json`

Use `campaign-summary.json` as the canonical machine-readable report. It captures snapshot metadata, phase durations, success/failure counts, seed counts, sampled validation output, and any blocking reason that stopped the run.

## Recorded Lab Runs

- [WinServer live validation - 2026-05-07](WINSERVER-LIVE-VALIDATION-2026-05-07.md) records the Windows Server 2025 AD lab campaign, schema-readiness fix, final 3,000-user validation results, and populated `drink` screenshots.

## Troubleshooting

The canonical schema-readiness failure from April 9, 2026 looked like this:

- `Test-ADDrinkAttributeEnabled` returned `True`
- `Test-ADDrinkAttributeReadyForUserWrite` returned `False`
- live writes failed with `An attempt was made to modify an object to include an attribute that is not legal for its class`

In that state, the environment is not ready for DrunkenAD user writes even though the schema attribute exists. The fix is to allow `drink` on the `user` class, either manually or through [scripts/Enable-ADDrinkAttributeOnUserClass.ps1](../scripts/Enable-ADDrinkAttributeOnUserClass.ps1) as documented in [SCHEMA-ENABLEMENT.md](SCHEMA-ENABLEMENT.md).

Also pay attention to:

- replication lag if multiple DCs exist
- delegated write permissions on `drink`
- the existence and uniqueness of target users referenced in the ingestion source
- namespace ownership when more than one workflow writes to the same attribute
- environment-specific restrictions on `pager`, `mail`, or `userPrincipalName`
