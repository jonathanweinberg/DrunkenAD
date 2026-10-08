# Drink Data Store Model

The `drink` attribute is a multivalued string attribute. DrunkenAD treats it as a lightweight prefixed data store attached to an Active Directory user.

That assumes `drink` is actually writable on the `user` class, not just present in schema. Check `Test-ADDrinkAttributeReadyForUserWrite` before using the write paths, and use [SCHEMA-ENABLEMENT.md](SCHEMA-ENABLEMENT.md) if the attribute exists but is not yet legal on `user`.

## Core Idea

Each value in `drink` is one stored record.

Each record is made of:

- a literal prefix that acts like a namespace
- a payload value that belongs to that namespace

Examples:

- `AppProfile-Tier=Gold`
- `AppProfile-Department=Security`
- `Flags-Audited`
- `Flags-RemoteEligible`
- `AppRouting-MailEnabled`

Application-owned examples use prefixes separate from the built-in projection's
`Profile-`, `Identity-`, `Meta-`, `Routing-`, and `Notify-` namespaces. Custom
projection maps also require an ownership review before combining workflows.

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
`AppMeta-` owns every value starting with it, including `AppMeta-Extra-...`. Stored
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
        'AppProfile-' = @('Tier=Gold')
        'Flags-'      = @('Audited')
    } `
    -Confirm:$false
```

then:

- all existing `AppProfile-` values are replaced
- all existing `Flags-` values are replaced
- everything else remains untouched

Writes send only the selected namespace's removed and added values through
`Set-ADUser -Remove/-Add`. They never replace or clear the entire attribute.
Unrelated values added after the initial read on the same DC are preserved.
Case-only payload changes remove the old spelling and add the requested one.

The selected endpoint is reused for schema checks, lookup, and write. An absent
server or the domain DNS name is pinned to the RootDSE controller, preserving
an explicit port. Explicit hosts, IPs, DNS aliases, and NetBIOS names are passed
through unchanged. A short name cannot safely be guessed to mean a domain
rather than a specific DC. NetBIOS names and aliases can select different DCs
between calls. For multiple writers, configure the same actual DC hostname in
`-DomainController`, not a NetBIOS name or domain-wide alias:
independent automatic selections can reach different DCs, and normal AD
replication of a nonlinked multivalued attribute can still lose updates.
Concurrent writes to the same prefix are not serialized or transactional; a
conflicting delta can fail or leave a combined set. Serialize those producers.

Do not use a missing-value Remove as a concurrency guard. The controlled
Windows Server 2025 run accepted an already-missing removal and applied the
remaining delta; duplicate and case-equivalent additions were ignored without
a partial update. These observations are consistent with Microsoft's
[permissive-modify control](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ldap/ldap-server-permissive-modify-oid).
This is not proof of the exact control used by every runtime, nor a lock.
CSV revalidation narrows the race window but does not eliminate it.

The number of values has a separate server storage limit from each value's
`rangeUpper`. The 1,602-value fixture was rejected before range retrieval could
be exercised; that case is an evidence gap, not a successful large-set test.
Microsoft documents [nonlinked attribute storage limits](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/active-directory-domain-services-maximum-limits#maximum-number-of-nonlinked-attribute-values)
that depend on the directory configuration. Keep payloads compact and do not
assume that a Windows Server 2025 OS alone enables a higher-capacity forest.

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

If you remove `Flags-`, all `Flags-...` values disappear, but `AppProfile-...` and any unrelated values remain.

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

- `AppProfile-` for compact user-facing metadata such as tier, region, or role
- `Flags-` for discrete state markers such as `Enabled` or `Audited`
- `AppRouting-` for downstream processing hints such as mailbox or workflow targets
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
`Profile-` and `Routing-`. Projection clears a mapped namespace whose source
attributes are blank. CSV retains all-blank mapped namespaces by default and
clears them only with `-ClearBlankNamespaces`. Existing custom maps still require
an ownership review before combining workflows.
