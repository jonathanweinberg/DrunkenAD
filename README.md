# DrunkenAD

[![PowerShell CI](https://github.com/jonathanweinberg/DrunkenAD/actions/workflows/powershell-ci.yml/badge.svg)](https://github.com/jonathanweinberg/DrunkenAD/actions/workflows/powershell-ci.yml)
[![Documentation CI](https://github.com/jonathanweinberg/DrunkenAD/actions/workflows/documentation-ci.yml/badge.svg)](https://github.com/jonathanweinberg/DrunkenAD/actions/workflows/documentation-ci.yml)

DrunkenAD is a PowerShell module for repurposing the multivalued Active Directory `drink` attribute as a compact directory-backed data store.

It provides a structured way to store namespaced records on user objects, making `drink` useful as a lightweight mini-database for flags, routing hints, profile metadata, and other compact application data.

<p align="center">
  <img src="docs/images/documentation-suite-2026-05-07/drunkenad-overview.png" alt="DrunkenAD overview">
</p>

## At A Glance

DrunkenAD treats each `drink` value as a namespaced record attached to the AD
user object. Workflows can write their own prefixes, preserve unrelated values,
validate schema readiness before touching live users, and export the stored data
for review.

| Area | Infographic | Start Here |
| --- | --- | --- |
| Use cases | <img src="docs/images/documentation-suite-2026-05-07/use-case-map.png" alt="DrunkenAD use cases" width="260"> | [docs/USE-CASES.md](docs/USE-CASES.md) |
| Module layout | <img src="docs/images/documentation-suite-2026-05-11/module-layout.png" alt="DrunkenAD module layout" width="260"> | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Write model | <img src="docs/images/documentation-suite-2026-05-07/namespace-write-model.png" alt="Namespace write model" width="260"> | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| CSV ingestion | <img src="docs/images/documentation-suite-2026-05-07/csv-ingestion-flow.png" alt="CSV ingestion flow" width="260"> | [docs/HOW-TO-INGEST-CSV.md](docs/HOW-TO-INGEST-CSV.md) |
| Schema readiness | <img src="docs/images/documentation-suite-2026-05-07/schema-readiness-flow.png" alt="Schema readiness flow" width="260"> | [docs/SCHEMA-ENABLEMENT.md](docs/SCHEMA-ENABLEMENT.md) |
| Live validation | <img src="docs/images/documentation-suite-2026-05-07/live-validation-ladder.png" alt="Live validation ladder" width="260"> | [docs/LIVE-VALIDATION.md](docs/LIVE-VALIDATION.md) |
| Release readiness | <img src="docs/images/documentation-suite-2026-05-11/release-readiness.png" alt="Release readiness" width="260"> | [docs/TESTING.md](docs/TESTING.md) |

## Design Goals

The module is built around a few practical goals:

- Treat `drink` as a multivalue record store instead of an incidental free-form field.
- Keep namespaces predictable so multiple consumers can share the same attribute safely.
- Preserve unrelated values during updates so one namespace can evolve without disturbing another.
- Make reads, writes, and removals safe enough to use in repeatable operational workflows.

## Operational Use Cases

DrunkenAD is a good fit when you want a small amount of application state to live directly on the user object:

- feature flags that need to follow the user through directory lookups
- routing hints for mail, provisioning, or downstream sync services
- tenant or environment markers used by internal tooling
- compact profile metadata that should be easy to query and overwrite by namespace
- synchronization checkpoints or workflow states that benefit from AD-backed locality

## Operational Safety

DrunkenAD is opinionated about the edges that matter when writing application data into Active Directory:

- User resolution uses exact LDAP filters and throws if the search is ambiguous.
- Prefix matching is literal, not regex-driven, so special characters like `[` or `+` cannot accidentally match the wrong value.
- The module distinguishes between schema presence and actual user-write readiness, so `drink` must both exist and be allowed on the Active Directory `user` class.
- Updates use PowerShell `ShouldProcess`, so `-WhatIf` and `-Confirm` work naturally.
- The integration validation workflow creates unique test objects and only removes the ones it created.

## Data Store Model

The storage model is simple:

- each `drink` value is one stored record
- each record belongs to a namespace identified by a literal prefix
- the suffix after that prefix is your payload

Examples:

- `Profile-Tier=Gold`
- `Flags-Audited`
- `Routing-MailEnabled`

In practice, the `drink` attribute functions as a tiny multivalued namespace store attached to a user object.

Command examples below assume the repository has been checked out at
`/temp/DrunkenAD`. Adjust that root for your own workstation or automation
workspace.

## Module Layout

The root module is now a small deterministic loader. It dot-sources the focused
files under `DrunkenAD/Private` and `DrunkenAD/Public`, then exports one command
list that must stay aligned with the module manifest.

- [DrunkenAD/DrunkenAD.psm1](DrunkenAD/DrunkenAD.psm1)
- [DrunkenAD/DrunkenAD.psd1](DrunkenAD/DrunkenAD.psd1)
- [DrunkenAD/Private](DrunkenAD/Private)
- [DrunkenAD/Public](DrunkenAD/Public)
- [examples/Import-DrunkenADCsv.ps1](examples/Import-DrunkenADCsv.ps1)
- [examples/Split-DrunkenADCsvField.ps1](examples/Split-DrunkenADCsvField.ps1)
- [examples/data/drink-ingestion-config.json](examples/data/drink-ingestion-config.json)
- [examples/data/drink-ingestion-sample.csv](examples/data/drink-ingestion-sample.csv)
- [scripts/Enable-ADDrinkAttributeOnUserClass.ps1](scripts/Enable-ADDrinkAttributeOnUserClass.ps1)
- [tests/DrunkenAD.Unit.Tests.ps1](tests/DrunkenAD.Unit.Tests.ps1)
- [tests/DrunkenAD.Integration.Tests.ps1](tests/DrunkenAD.Integration.Tests.ps1)
- [tests/Invoke-DrunkenADTests.ps1](tests/Invoke-DrunkenADTests.ps1)

## Exported Commands

| Command | Purpose |
| --- | --- |
| `Get-ADUserDrinkData` | Returns all stored values, or only those under one literal prefix namespace. |
| `Set-ADUserDrinkData` | Writes one or more namespaces of generic data into the `drink` attribute. |
| `Remove-ADUserDrinkData` | Removes one or more namespaces while preserving unrelated stored values. |
| `Set-ADUserDrinkProjection` | Projects selected user attributes into namespaced `drink` records. |
| `Import-ADUserDrinkCsvData` | Imports namespaced `drink` records from a CSV source using a JSON config or hashtable map. |
| `Split-DrunkenADCsvField` | Splits a delimited CSV field into clean multivalue items for `SplitOn` mappings. |
| `Get-AdUserDrinkPrefixedData` | Compatibility getter for the older prefixed-data naming. |
| `Set-ADUserDrinkPrefixedData` | Compatibility writer for the older prefixed-data naming. |
| `Update-ADUserDrinkAttribute` | Backward-compatible wrapper around the safer set function. |
| `Invoke-ADUserDrinkDataDemo` | Compatibility wrapper for the older projection command name. |
| `Test-ADDrinkAttributeEnabled` | Checks whether the schema attribute exists and is not defunct. |
| `Test-ADDrinkAttributeReadyForUserWrite` | Checks whether `drink` is actually writable on Active Directory user objects. |

The exported commands include first-class comment-based help, so the module is
self-documenting in PowerShell. Start with the module topic, then drill into
commands, examples, and individual parameters:

```powershell
Get-Help about_DrunkenAD
Get-Help Set-ADUserDrinkData -Full
Get-Help Import-ADUserDrinkCsvData -Examples
Get-Help Remove-ADUserDrinkData -Parameter Prefixes
Get-Help Set-ADUserDrinkProjection -Detailed
```

## Quick Start

Import the module:

```powershell
Import-Module /temp/DrunkenAD/DrunkenAD/DrunkenAD.psd1 -Force
```

Check schema presence:

```powershell
Test-ADDrinkAttributeEnabled -Server 'dc01.contoso.com'
```

Check whether user writes are actually supported:

```powershell
Test-ADDrinkAttributeReadyForUserWrite -Server 'dc01.contoso.com'
```

If the first command is true and the second is false, the attribute exists but is not yet allowed on the Active Directory `user` class. Follow [docs/SCHEMA-ENABLEMENT.md](docs/SCHEMA-ENABLEMENT.md) before attempting writes.

Write one generic namespace:

```powershell
Set-ADUserDrinkData `
    -SamAccountName 'TesterAccount' `
    -DataMap @{ 'Profile-' = @('Tier=Gold') } `
    -DomainController 'dc01.contoso.com' `
    -Confirm:$false
```

Write multiple namespaces at once:

```powershell
Set-ADUserDrinkData `
    -SamAccountName 'TesterAccount' `
    -DataMap @{
        'Profile-' = @('Tier=Gold')
        'Flags-'   = @('Audited', 'Enabled')
    } `
    -DomainController 'dc01.contoso.com' `
    -Confirm:$false
```

Read everything stored:

```powershell
Get-ADUserDrinkData `
    -SamAccountName 'TesterAccount' `
    -DomainController 'dc01.contoso.com'
```

Read one namespace back:

```powershell
Get-ADUserDrinkData `
    -SamAccountName 'TesterAccount' `
    -Prefix 'Profile-' `
    -DomainController 'dc01.contoso.com'
```

Preview a namespace update without writing:

```powershell
Set-ADUserDrinkData `
    -SamAccountName 'TesterAccount' `
    -DataMap @{ 'Profile-' = @('Tier=Platinum') } `
    -DomainController 'dc01.contoso.com' `
    -WhatIf
```

Remove one namespace:

```powershell
Remove-ADUserDrinkData `
    -SamAccountName 'TesterAccount' `
    -Prefixes 'Flags-' `
    -DomainController 'dc01.contoso.com' `
    -Confirm:$false
```

Project selected AD attributes into the store with the built-in projection map:

```powershell
Set-ADUserDrinkProjection `
    -SamAccountName 'TesterAccount' `
    -DomainController 'dc01.contoso.com' `
    -Confirm:$false
```

Project a custom attribute map with splatting:

```powershell
$projectionParams = @{
    SamAccountName = 'TesterAccount'
    DomainController = 'dc01.contoso.com'
    AttributeMap = @{
        'Org-' = @('department', 'title')
        'Meta-' = @('description')
    }
}
Set-ADUserDrinkProjection @projectionParams -Confirm:$false
```

Merge a custom attribute map into the built-in projection defaults:

```powershell
Set-ADUserDrinkProjection `
    -SamAccountName 'TesterAccount' `
    -AttributeMap @{ 'Org-' = @('company') } `
    -IncludeDefaultAttributeMap `
    -DomainController 'dc01.contoso.com' `
    -Confirm:$false
```

## Testing

Run the unit suite:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Invoke-DrunkenADTests.ps1
```

Run the parser gate by itself:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/scripts/Test-DrunkenADSyntax.ps1
```

Run the release-readiness gate:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/scripts/Test-DrunkenADRelease.ps1
```

The default unit suite includes a `Get-Help` contract check. It verifies that
every exported command has comment-based help with descriptions, parameter
guidance, examples, related links, and discoverability metadata.

Run integration tests against a live AD environment:

```powershell
$env:DRUNKENAD_RUN_INTEGRATION = '1'
$env:DRUNKENAD_TEST_DC = 'dc01.contoso.com'
$env:DRUNKENAD_TEST_DNS_SUFFIX = 'contoso.com'
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Invoke-DrunkenADTests.ps1 -IncludeIntegration
```

If the integration suite reports a blocking reason instead of running write-path assertions, inspect the full readiness object:

```powershell
Test-ADDrinkAttributeReadyForUserWrite `
    -Server 'dc01.contoso.com' `
    -PassThru | Format-List
```

That usually means `drink` exists but is not yet writable on the Active Directory `user` class. Use [docs/SCHEMA-ENABLEMENT.md](docs/SCHEMA-ENABLEMENT.md) before retrying live writes.

Run a quick seeded live validation harness when your host wrapper is configured:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Live/Invoke-DrunkenADLiveCampaign.ps1 `
    -CampaignProfile Quick
```

Use `-CampaignProfile Standard` for a 300-user pass and the default `Full`
profile for the 3,000-user campaign:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/tests/Live/Invoke-DrunkenADLiveCampaign.ps1
```

That optional workflow is host-wrapper driven. It creates or verifies a rollback
point, makes the repository available to the live lab, verifies schema state,
reconciles the synthetic seed population, and writes timestamped reports under
`tests/Live/results/`. Those live results are intentionally ignored by Git. The
host-method contract is documented in
[docs/LIVE-CAMPAIGN-HOSTS.md](docs/LIVE-CAMPAIGN-HOSTS.md).

More detail lives in [docs/README.md](docs/README.md), [docs/USE-CASES.md](docs/USE-CASES.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/OPERATIONS.md](docs/OPERATIONS.md), [docs/DATA-STORE.md](docs/DATA-STORE.md), [docs/TESTING.md](docs/TESTING.md), [docs/LIVE-VALIDATION.md](docs/LIVE-VALIDATION.md), [docs/LIVE-CAMPAIGN-HOSTS.md](docs/LIVE-CAMPAIGN-HOSTS.md), [docs/HOW-TO-INGEST-CSV.md](docs/HOW-TO-INGEST-CSV.md), and [docs/SCHEMA-ENABLEMENT.md](docs/SCHEMA-ENABLEMENT.md).

## CI

GitHub Actions runs two fast default gates:

- [.github/workflows/powershell-ci.yml](.github/workflows/powershell-ci.yml) installs a pinned Pester version, validates the module manifest, parses tracked PowerShell files, runs the unit suite, and runs release-readiness checks on Ubuntu, macOS, Windows PowerShell Core, and Windows PowerShell 5.1 Desktop.
- [.github/workflows/documentation-ci.yml](.github/workflows/documentation-ci.yml) checks documentation hygiene, rejects machine-specific checkout paths, verifies Markdown image/link targets, and ensures live result artifacts stay untracked.

The PowerShell workflow uploads per-OS Pester XML results as short-lived artifacts. Integration tests and the full live campaign stay opt-in because they require a prepared Active Directory lab.

## License And Contributions

DrunkenAD is licensed under the [BSD 3-Clause License](LICENSE).

Contributions are accepted under the
[DrunkenAD Contributor License Agreement](CONTRIBUTOR-LICENSE-AGREEMENT.md).
Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

Unless otherwise noted, generated documentation images and other documentation
assets in this repository are covered by the same BSD 3-Clause License as the
project source.

## CSV Ingestion Workflow

The sample CSV workflow is meant to show a realistic ingestion path from a flat file into namespaced `drink` data:

- It expects target users to already exist in Active Directory.
- It expects `Test-ADDrinkAttributeReadyForUserWrite` to succeed before any import is attempted.
- It turns fixed CSV columns into namespace records such as `Profile-`, `Flags-`, `Routing-`, `Tenant-`, and `Sync-`.
- It can turn one CSV column into multiple `drink` values by using `SplitOn` on that mapping only.
- It can load those mappings from [drink-ingestion-config.json](examples/data/drink-ingestion-config.json) or accept a hashtable at invocation time.
- It uses the same domain controller for validation, lookup, and write operations.
- It can be previewed safely with `-WhatIf`.

Run the module command directly with the sample CSV and config:

```powershell
Import-ADUserDrinkCsvData `
    -CsvPath /temp/DrunkenAD/examples/data/drink-ingestion-sample.csv `
    -ConfigPath /temp/DrunkenAD/examples/data/drink-ingestion-config.json `
    -DomainController 'dc01.contoso.com'
```

Preview the sample CSV with `-WhatIf`:

```powershell
Import-ADUserDrinkCsvData `
    -CsvPath /temp/DrunkenAD/examples/data/drink-ingestion-sample.csv `
    -ConfigPath /temp/DrunkenAD/examples/data/drink-ingestion-config.json `
    -DomainController 'dc01.contoso.com' `
    -WhatIf
```

Use an in-memory namespace map instead of a config file:

```powershell
$namespaceMap = @{
    'Profile-' = @(
        @{ Column = 'ProfileTier'; Label = 'Tier' }
        @{ Column = 'ProfileRegion'; Label = 'Region' }
    )
    'Flags-' = @(
        @{ Column = 'Flags'; SplitOn = ';' }
    )
}
Import-ADUserDrinkCsvData `
    -CsvPath /temp/DrunkenAD/examples/data/drink-ingestion-sample.csv `
    -NamespaceMap $namespaceMap `
    -DomainController 'dc01.contoso.com'
```

Preview a multivalue CSV field before adding it to an import mapping:

```powershell
Split-DrunkenADCsvField -Value 'Enabled; Audited ; Keep-Stable' -Delimiter ';'
```

That returns three values: `Enabled`, `Audited`, and `Keep-Stable`. In the
sample config, `Flags` uses `"SplitOn": ";"`, so a CSV value such as
`"Enabled;Audited"` becomes `Flags-Enabled` and `Flags-Audited` during import.

The example wrapper script remains available when you want a ready-made entry point:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/examples/Import-DrunkenADCsv.ps1 `
    -DomainController 'dc01.contoso.com' `
    -CsvPath /temp/DrunkenAD/examples/data/drink-ingestion-sample.csv
```

## Design Notes

There are two layers on purpose:

- `Get-/Set-/Remove-ADUserDrinkData` is the preferred generic data-store API.
- `Set-ADUserDrinkProjection` is the preferred way to project existing AD user attributes into namespaced records.
- `Get-AdUserDrinkPrefixedData`, `Set-ADUserDrinkPrefixedData`, and `Update-ADUserDrinkAttribute` remain as compatibility surfaces for older call sites.
- `Invoke-ADUserDrinkDataDemo` remains available as a compatibility wrapper, but new usage should prefer the projection command and the CSV ingestion workflow.
