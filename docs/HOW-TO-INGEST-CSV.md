# How To Ingest CSV Data Into `drink`

This workflow shows how to take a flat CSV file and write compact namespaced records into the Active Directory `drink` attribute.

The preferred entry point is the module command `Import-ADUserDrinkCsvData`. The example script wraps that command with sample defaults.

## Input Shape

The sample file lives at [drink-ingestion-sample.csv](../examples/data/drink-ingestion-sample.csv).
The default mapping file lives at [drink-ingestion-config.json](../examples/data/drink-ingestion-config.json).

It uses these columns:

- `SamAccountName`
- `ProfileTier`
- `ProfileRegion`
- `Flags`
- `RoutingMailbox`
- `TenantId`
- `SyncState`

Every nonblank `SamAccountName` is trimmed and must be unique
case-insensitively within the file. Duplicate identities fail local preflight
before schema checks or user writes, which prevents row order from deciding the
final namespace value. Blank identities retain the documented warning-and-skip
behavior.

Each import checks schema readiness once and pins one domain controller. It
resolves every usable row and validates all prefixed value lengths before any
write. A missing or ambiguous user therefore prevents the whole import from
starting. The CSV identity contract remains `SamAccountName`.

Immediately before applying each approved row, the importer reads `drink` again
from the same resolved object on the pinned controller. This reduces the stale
snapshot window; it is not a lock or a transaction. A concurrent write after
that read can still conflict.

Directory errors during execution still stop the import. Already completed
writes are not rolled back. The terminating error's `TargetObject` exposes
`CompletedRowCount`, `FailedRowNumber` (including the header), `PendingRowCount`,
and `PreparedRowCount`, plus per-status row counts. Completed means processed,
not necessarily written. Each result's `Status` distinguishes `Written`,
`NoChange`, `Declined`, and `WhatIf`. Capture streamed results when an audit of
partial progress is required. `FinalDrinkValues` is the computed desired
snapshot, not proof that a declined or previewed operation changed AD and not
a post-write read-back.

The sample import script maps those columns into namespaces like this:

- `ProfileTier` -> `CsvProfile-Tier=<value>`
- `ProfileRegion` -> `CsvProfile-Region=<value>`
- `Flags` -> one `Flags-<value>` record per semicolon-delimited item
- `RoutingMailbox` -> `CsvRouting-Mailbox=<value>`
- `TenantId` -> `Tenant-Id=<value>`
- `SyncState` -> `Sync-State=<value>`

The JSON mapping format uses namespace prefixes as top-level keys. Each entry points at a CSV column and can optionally add a `Label` or split multivalue fields with `SplitOn`.

## Blank Cells And Existing Imports

Every row replaces all namespaces declared by its mapping. Blank or
whitespace-only cells contribute no records; if all columns for a namespace
are blank, existing values in that namespace are removed. A row with a valid
identity and all mapped cells blank clears all mapped namespaces. Unmapped
prefixes remain untouched. To leave a namespace unchanged, omit it from the
mapping used for that import, rather than supplying blank cells.

This corrects the previous skip-blank behavior and matches projection semantics.
Preview existing import files before adopting the change. The sample config now
uses `CsvProfile-` and `CsvRouting-` to avoid the default projection's `Profile-`
and `Routing-`. Existing stored values are not automatically renamed or removed;
review ownership and migrate old sample data explicitly.

## Multivalue Fields

Use `SplitOn` only on columns that intentionally contain multiple values. The
sample `Flags` column is quoted CSV text such as `"Enabled;Audited"` and the
mapping splits it with a semicolon:

```json
{
  "Flags-": [
    {
      "Column": "Flags",
      "SplitOn": ";"
    }
  ]
}
```

That produces one `drink` value per non-empty item:

- `Flags-Enabled`
- `Flags-Audited`

The splitter is literal, not regex-based. A delimiter such as `||` is treated as
two pipe characters. Empty delimiters are rejected so the import cannot
accidentally split a field into individual characters.

Preview a field locally before running an import:

```powershell
Split-DrunkenADCsvField -Value 'Enabled; Audited ; Keep-Stable' -Delimiter ';'
```

The helper trims each item and drops empty entries, which keeps accidental extra
semicolons from becoming empty `drink` records.

## Prerequisites

Before running the import:

- make sure the target users already exist in AD
- make sure each nonblank `SamAccountName` appears only once in the CSV
- confirm `drink` is writable on user objects with `Test-ADDrinkAttributeReadyForUserWrite`
- decide which namespaces this workflow owns so it does not overwrite data managed elsewhere

If `Test-ADDrinkAttributeEnabled` returns true but `Test-ADDrinkAttributeReadyForUserWrite` returns false, the attribute exists in schema but is not yet allowed on the Active Directory `user` class. Follow [SCHEMA-ENABLEMENT.md](SCHEMA-ENABLEMENT.md) before importing data.

## Preview The Import

Use `-WhatIf` first:

```powershell
Import-ADUserDrinkCsvData `
    -CsvPath /temp/DrunkenAD/examples/data/drink-ingestion-sample.csv `
    -ConfigPath /temp/DrunkenAD/examples/data/drink-ingestion-config.json `
    -DomainController 'dc01.contoso.com' `
    -WhatIf
```

That previews the writes without changing any `drink` values.

## Run The Import

When the preview looks correct:

```powershell
Import-ADUserDrinkCsvData `
    -CsvPath /temp/DrunkenAD/examples/data/drink-ingestion-sample.csv `
    -ConfigPath /temp/DrunkenAD/examples/data/drink-ingestion-config.json `
    -DomainController 'dc01.contoso.com'
```

Each row produces a namespaced `DataMap` and uses the shared prefix-scoped writer.

## Use A Different JSON Mapping

You can point the script at another mapping file:

```powershell
Import-ADUserDrinkCsvData `
    -CsvPath /path/to/users.csv `
    -ConfigPath /path/to/drink-config.json `
    -DomainController 'dc01.contoso.com'
```

## Use An In-Memory Hashtable

For ad hoc runs, you can pass a hashtable directly:

```powershell
$namespaceMap = @{
    'CsvProfile-' = @(
        @{ Column = 'ProfileTier'; Label = 'Tier' }
        @{ Column = 'ProfileRegion'; Label = 'Region' }
    )
    'Flags-' = @(
        @{ Column = 'Flags'; SplitOn = ';' }
    )
    'Tenant-' = @(
        @{ Column = 'TenantId'; Label = 'Id' }
    )
}

Import-ADUserDrinkCsvData `
    -CsvPath /path/to/users.csv `
    -NamespaceMap $namespaceMap `
    -DomainController 'dc01.contoso.com' `
    -WhatIf
```

## Verify Results

Read a user back after the import:

```powershell
Get-ADUserDrinkData `
    -SamAccountName 'alice.bennett' `
    -DomainController 'dc01.contoso.com'
```

Filter to one namespace if needed:

```powershell
Get-ADUserDrinkData `
    -SamAccountName 'alice.bennett' `
    -Prefix 'Flags-' `
    -DomainController 'dc01.contoso.com'
```

## Adapting The Workflow

The sample script at [Import-DrunkenADCsv.ps1](../examples/Import-DrunkenADCsv.ps1) is intentionally straightforward and simply wraps the module command.

To adapt it for your environment:

- add or remove CSV columns
- create a new JSON config file for each ingestion profile
- change the namespace prefixes the script emits
- add `SplitOn` only to columns that deliberately contain multiple values
- use `Split-DrunkenADCsvField` to preview delimiter behavior before live import
- pass `-LogPath` if you want append-only write logging
