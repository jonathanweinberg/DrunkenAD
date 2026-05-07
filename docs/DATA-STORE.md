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

- [Get-ADUserDrinkData](../DrunkenAD/DrunkenAD.psm1)
- [Set-ADUserDrinkData](../DrunkenAD/DrunkenAD.psm1)
- [Remove-ADUserDrinkData](../DrunkenAD/DrunkenAD.psm1)
- [Set-ADUserDrinkProjection](../DrunkenAD/DrunkenAD.psm1)
- [Import-ADUserDrinkCsvData](../DrunkenAD/DrunkenAD.psm1)

That API treats `drink` as a namespace store:

- `Get-ADUserDrinkData` reads either everything or one namespace
- `Set-ADUserDrinkData` replaces one or more namespaces
- `Remove-ADUserDrinkData` deletes one or more namespaces
- `Set-ADUserDrinkProjection` builds namespace records from actual user attributes
- `Import-ADUserDrinkCsvData` turns CSV rows into namespace maps and writes them through the same API

## Namespace Rules

Prefixes are treated literally, not as regexes.

That matters because prefixes like these are allowed and safe:

- `App[01]-`
- `Flags+`
- `Meta.(v2)-`

The module escapes those prefixes before matching or removing values.

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
