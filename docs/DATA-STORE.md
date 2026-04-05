# Drink Data Store Model

The `drink` attribute is a multivalued string attribute. This module now treats it as a lightweight prefixed data store attached to an Active Directory user.

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

- [Get-ADUserDrinkData](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/DrunkenAD/DrunkenAD.psm1)
- [Set-ADUserDrinkData](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/DrunkenAD/DrunkenAD.psm1)
- [Remove-ADUserDrinkData](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/DrunkenAD/DrunkenAD.psm1)
- [Invoke-ADUserDrinkDataDemo](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/DrunkenAD/DrunkenAD.psm1)

That API treats `drink` as a namespace store:

- `Get-ADUserDrinkData` reads either everything or one namespace
- `Set-ADUserDrinkData` replaces one or more namespaces
- `Remove-ADUserDrinkData` deletes one or more namespaces
- `Invoke-ADUserDrinkDataDemo` builds namespace records from actual user attributes

## Namespace Rules

Prefixes are treated literally, not as regexes.

That matters because prefixes like these are allowed and safe:

- `Demo[01]-`
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

## Compatibility Layer

The older prefixed-data commands still exist:

- `Get-AdUserDrinkPrefixedData`
- `Set-ADUserDrinkPrefixedData`
- `Update-ADUserDrinkAttribute`

They are still supported, but the generic `DrinkData` names are now the preferred public surface.

## Demo Mode

`Invoke-ADUserDrinkDataDemo` is meant to seed realistic example data into `drink`.

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
Invoke-ADUserDrinkDataDemo `
    -SamAccountName 'TesterAccount' `
    -AttributeMap @{
        'Org-' = @('department', 'title')
        'Meta-' = @('description')
    } `
    -Confirm:$false
```

And if you want your custom namespaces plus the default demo payload, add `-IncludeDefaultAttributeMap`.
