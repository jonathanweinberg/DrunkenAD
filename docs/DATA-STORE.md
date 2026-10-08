# Drink Data Store Model

The `drink` attribute is a multivalued string attribute. DrunkenAD treats it as a lightweight prefixed data store attached to an Active Directory user.

That assumes `drink` is actually writable on the `user` class, not just present in schema. Check `Test-ADDrinkAttributeReadyForUserWrite` before using the write paths, and use [SCHEMA-ENABLEMENT.md](SCHEMA-ENABLEMENT.md) if the attribute exists but is not yet legal on `user`.

## Core Idea

Each value in `drink` is one stored record.

Each record is made of:

- a literal prefix that acts like a namespace
- a payload value that belongs to that namespace

Examples:

- `Profile-Tier=Gold`
- `Profile-Department=Security`
- `Flags-Audited`
- `Flags-RemoteEligible`
- `Routing-MailEnabled`

## How The Module Thinks About It

The preferred API is:

- [Get-ADUserDrinkData](../DrunkenAD/Public/Get-ADUserDrinkData.ps1)
- [Set-ADUserDrinkData](../DrunkenAD/Public/Set-ADUserDrinkData.ps1)
- [Remove-ADUserDrinkData](../DrunkenAD/Public/Remove-ADUserDrinkData.ps1)
- [Set-ADUserDrinkProjection](../DrunkenAD/Public/Set-ADUserDrinkProjection.ps1)
- [Import-ADUserDrinkCsvData](../DrunkenAD/Public/Import-ADUserDrinkCsvData.ps1)
- [Split-DrunkenADCsvField](../DrunkenAD/Public/Split-DrunkenADCsvField.ps1)

That API treats `drink` as a namespace store:

- `Get-ADUserDrinkData` reads either everything or one namespace
- `Set-ADUserDrinkData` replaces one or more namespaces
- `Remove-ADUserDrinkData` deletes one or more namespaces
- `Set-ADUserDrinkProjection` builds namespace records from actual user attributes
- `Import-ADUserDrinkCsvData` turns CSV rows into namespace maps and writes them through the same API
- `Split-DrunkenADCsvField` previews how a delimited CSV field becomes multiple values for a `SplitOn` mapping

## Multivalue CSV Fields

`drink` is already multivalued, so one CSV cell can intentionally produce more
than one stored value. DrunkenAD keeps that explicit: only mappings with
`SplitOn` are split.

For example, a CSV field of `"Enabled;Audited"` with this mapping:

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

produces `Flags-Enabled` and `Flags-Audited`. Other mapped columns remain
single-value fields unless they also opt into `SplitOn`.

## Namespace Rules

Prefixes are treated literally, not as regexes.

That matters because prefixes like these are allowed and safe:

- `App[01]-`
- `Flags+`
- `Meta.(v2)-`

The module compares prefixes with `OrdinalIgnoreCase`. Overlapping prefixes in
one operation are rejected. Across separate calls, a broad prefix such as
`Meta-` owns every value starting with it, including `Meta-Extra-...`. Stored
strings do not contain a namespace registry, so the module cannot infer that
these belong to different applications. Choose mutually exclusive prefixes
across all producers; adding another delimiter does not establish ownership.

## Replacement Semantics

`Set-ADUserDrinkData` is namespace-replacement based.

That means:

- values under the prefixes you provide are replaced
- values under prefixes you do not provide are preserved

If you write:

```powershell
Set-ADUserDrinkData `
    -SamAccountName 'TesterAccount' `
    -DataMap @{
        'Profile-' = @('Tier=Gold')
        'Flags-'   = @('Audited')
    } `
    -Confirm:$false
```

then:

- all existing `Profile-` values are replaced
- all existing `Flags-` values are replaced
- everything else remains untouched

Writes send only the selected namespace's removed and added values through
`Set-ADUser -Remove/-Add`. They never replace or clear the entire attribute.
Unrelated values added after the initial read on the same DC are preserved.
Case-only payload changes remove the old spelling and add the requested one.

One DC is selected per operation and reused for schema checks, lookup, and
write. Even a domain alias is resolved to the RootDSE controller for that
operation. For multiple writers, configure the same actual DC hostname in
`-DomainController`, not a domain-wide alias:
independent automatic selections can reach different DCs, and normal AD
replication of a nonlinked multivalued attribute can still lose updates.
Concurrent writes to the same prefix are not serialized or transactional; a
conflicting delta can fail or leave a combined set. Serialize those producers.

The prefix and payload together must fit the target schema's `rangeUpper`.
Readiness reports expose that limit; it is not hard-coded into the writer.
`-PassThru` returns values computed from the initial read, including with
`-WhatIf`. It is a preview/result calculation, not a fresh directory read or
a concurrency guarantee.

CSV and projection summary objects additionally expose `Status`: `Written`,
`NoChange`, `Declined`, or `WhatIf`. The generic write commands retain their
string-array `-PassThru` contract. CSV refreshes each approved row's values after
whole-input preflight; it still needs external same-prefix coordination.

## Removal Semantics

`Remove-ADUserDrinkData` works by replacing a namespace with an empty set.

If you remove `Flags-`, all `Flags-...` values disappear, but `Profile-...` and any unrelated values remain.

## Why This Works Well

Repurposing `drink` this way is useful when you want a small amount of application data to travel with the user object itself:

- feature flags
- routing hints
- application profile fields
- environment or tenant markers
- compact synchronization metadata

The model is intentionally narrow. It is designed for concise strings, not large payloads or document storage.

## Common Namespace Patterns

Teams usually get the most value from a few well-defined namespaces with clear overwrite semantics:

- `Profile-` for compact user-facing metadata such as tier, region, or role
- `Flags-` for discrete state markers such as `Enabled` or `Audited`
- `Routing-` for downstream processing hints such as mailbox or workflow targets
- `Tenant-` for tenant, environment, or business-unit identifiers
- `Sync-` for integration state such as import status or checkpoint markers

## Compatibility Layer

The older prefixed-data commands still exist:

- `Get-AdUserDrinkPrefixedData`
- `Set-ADUserDrinkPrefixedData`
- `Update-ADUserDrinkAttribute`

They are still supported, but the generic `DrinkData` names are the preferred public surface.
No removal is scheduled in the 0.13 series. A future deprecation requires a
published migration table, a supported warning period, and a breaking-version
decision; this maintenance release does not remove aliases or `-AutoConfirm`.

## Attribute Projection

`Set-ADUserDrinkProjection` is meant to project selected AD user attributes into `drink`.

By default it uses a built-in attribute map:

- `Profile-` from `samAccountName`
- `Identity-` from `userPrincipalName`
- `Meta-` from `employeeID`
- `Routing-` from `mail`
- `Notify-` from `pager`

That yields records like:

- `Profile-samAccountName=TesterAccount`
- `Identity-userPrincipalName=tester@contoso.com`

You can also provide your own `AttributeMap`:

```powershell
Set-ADUserDrinkProjection `
    -SamAccountName 'TesterAccount' `
    -AttributeMap @{
        'Org-' = @('department', 'title')
        'Meta-' = @('description')
    } `
    -Confirm:$false
```

If you want your custom namespaces plus the default projection payload, add `-IncludeDefaultAttributeMap`.

The sample CSV config uses `CsvProfile-` and `CsvRouting-`, not the projection's
`Profile-` and `Routing-`. Both workflows clear old values for owned prefixes
whose source fields are blank. Existing custom maps still require an ownership
review before combining workflows.
