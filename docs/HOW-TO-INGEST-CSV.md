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

Every record must contain the same number of fields as the header. Missing
trailing fields, extra fields, or malformed quoting fail before directory
access. Empty cells may be quoted or unquoted; embedded commas and newlines
must be quoted. Record numbers count CSV records, not physical text lines.

Each import checks schema readiness once and pins one domain controller. It
resolves every usable row and validates all prefixed value lengths before any
write. A missing or ambiguous user therefore prevents the whole import from
starting. The CSV identity contract remains `SamAccountName`.

The importer reads the resolved object again before showing the row's
confirmation counts. After approval it rereads the same GUID (or resolved DN)
and verifies that the exact Remove/Add delta still matches. Changed owned
values stop that row without a write; unrelated namespace changes do not.
This is not a lock or transaction. A concurrent write after the final read can
still conflict.

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

Blank or whitespace-only cells contribute no records. By default, a namespace
whose mapped fields are all blank is left unchanged, preserving existing import
behavior. Rows with no nonblank mapped data are skipped with a warning and do
not produce a result. If any mapped field in a namespace has data, that whole
namespace is replaced with the resulting nonblank records.

Use `-ClearBlankNamespaces` to opt into clearing namespaces whose mapped fields
are all blank. With this switch, an all-blank data row clears every mapped
namespace. Unmapped prefixes remain untouched in both modes. Preview with
`-ClearBlankNamespaces -WhatIf` before applying a clearing import. The example
wrapper accepts the same switch. No minor-version or default-deletion migration
is required; the unmerged candidate's earlier default-clearing change is withdrawn.

The sample config now
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
