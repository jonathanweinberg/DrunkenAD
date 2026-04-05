# DrunkenAD

DrunkenAD is a PowerShell module for treating the multivalued Active Directory `drink` attribute like a small prefixed data store.

The project started as a single script and has now been reshaped into a safer module with tests, documentation, and a future-friendly path toward a live demo environment.

## Why This Version Is Safer

The original script had a few sharp edges that are common in quick AD utilities: loose user searches, regex-sensitive prefix matching, mixed-controller reads and writes, and a test harness that could delete pre-existing objects.

This module hardens those behaviors:

- User resolution uses exact LDAP filters and throws if the search is ambiguous.
- Prefix matching is literal, not regex-driven, so special characters like `[` or `+` cannot accidentally match the wrong value.
- The module validates that the `drink` schema attribute is actually enabled before it writes anything.
- Updates use PowerShell `ShouldProcess`, so `-WhatIf` and `-Confirm` work naturally.
- The demo script creates unique test objects and only removes the ones it created.

## Data Store Model

The intended mental model is now:

- each `drink` value is one stored record
- each record belongs to a namespace identified by a literal prefix
- the suffix after that prefix is your payload

Examples:

- `Profile-Tier=Gold`
- `Flags-Audited`
- `Routing-MailEnabled`

In other words, the `drink` attribute is being used like a tiny multivalued namespace store attached to a user object.

## Module Layout

- [DrunkenAD/DrunkenAD.psm1](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/DrunkenAD/DrunkenAD.psm1)
- [DrunkenAD/DrunkenAD.psd1](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/DrunkenAD/DrunkenAD.psd1)
- [examples/Invoke-DrunkenADDemo.ps1](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/examples/Invoke-DrunkenADDemo.ps1)
- [tests/DrunkenAD.Unit.Tests.ps1](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/tests/DrunkenAD.Unit.Tests.ps1)
- [tests/DrunkenAD.Integration.Tests.ps1](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/tests/DrunkenAD.Integration.Tests.ps1)
- [tests/Invoke-DrunkenADTests.ps1](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/tests/Invoke-DrunkenADTests.ps1)

## Exported Commands

| Command | Purpose |
| --- | --- |
| `Get-ADUserDrinkData` | Returns all stored values, or only those under one literal prefix namespace. |
| `Set-ADUserDrinkData` | Writes one or more namespaces of generic data into the `drink` attribute. |
| `Remove-ADUserDrinkData` | Removes one or more namespaces while preserving unrelated stored values. |
| `Invoke-ADUserDrinkDataDemo` | Builds demo namespace data from user attributes and writes it into `drink`. |
| `Get-AdUserDrinkPrefixedData` | Compatibility getter for the older prefixed-data naming. |
| `Set-ADUserDrinkPrefixedData` | Compatibility writer for the older prefixed-data naming. |
| `Update-ADUserDrinkAttribute` | Backward-compatible wrapper around the safer set function. |
| `Test-ADDrinkAttributeEnabled` | Checks whether the schema attribute exists and is not defunct. |

The exported commands include comment-based help, so the module is self-documenting in PowerShell:

```powershell
Get-Help Invoke-ADUserDrinkDataDemo -Detailed
Get-Help Set-ADUserDrinkData -Examples
```

## Quick Start

Import the module:

```powershell
Import-Module /Users/jonathanweinberg/Documents/Codex_DrunkenAD/DrunkenAD/DrunkenAD.psd1 -Force
```

Check schema readiness:

```powershell
Test-ADDrinkAttributeEnabled -Server 'dc01.contoso.com'
```

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

Run the built-in demo mode against an existing user:

```powershell
Invoke-ADUserDrinkDataDemo `
    -SamAccountName 'TesterAccount' `
    -DomainController 'dc01.contoso.com' `
    -Confirm:$false
```

Run the demo with a splatted custom attribute map:

```powershell
$demoParams = @{
    SamAccountName = 'TesterAccount'
    DomainController = 'dc01.contoso.com'
    AttributeMap = @{
        'Org-' = @('department', 'title')
        'Meta-' = @('description')
    }
}
Invoke-ADUserDrinkDataDemo @demoParams -Confirm:$false
```

Merge your custom map into the built-in demo defaults:

```powershell
Invoke-ADUserDrinkDataDemo `
    -SamAccountName 'TesterAccount' `
    -AttributeMap @{ 'Org-' = @('company') } `
    -IncludeDefaultAttributeMap `
    -DomainController 'dc01.contoso.com' `
    -Confirm:$false
```

## Testing

Run the unit suite:

```powershell
pwsh -NoLogo -NoProfile -File /Users/jonathanweinberg/Documents/Codex_DrunkenAD/tests/Invoke-DrunkenADTests.ps1
```

Run the parser gate by itself:

```powershell
pwsh -NoLogo -NoProfile -File /Users/jonathanweinberg/Documents/Codex_DrunkenAD/scripts/Test-DrunkenADSyntax.ps1
```

Run integration tests later, when the demo AD environment exists:

```powershell
$env:DRUNKENAD_RUN_INTEGRATION = '1'
$env:DRUNKENAD_TEST_DC = 'dc01.contoso.com'
$env:DRUNKENAD_TEST_DNS_SUFFIX = 'contoso.com'
pwsh -NoLogo -NoProfile -File /Users/jonathanweinberg/Documents/Codex_DrunkenAD/tests/Invoke-DrunkenADTests.ps1 -IncludeIntegration
```

More detail lives in [docs/DATA-STORE.md](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/docs/DATA-STORE.md), [docs/TESTING.md](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/docs/TESTING.md), and [docs/LIVE-DEMO.md](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/docs/LIVE-DEMO.md).

## CI

A starter GitHub Actions workflow lives at [.github/workflows/powershell-ci.yml](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/.github/workflows/powershell-ci.yml). It currently:

- installs Pester
- runs the parser gate
- runs the unit suite

That keeps CI fast and safe today while the integration tests remain intentionally opt-in for the future demo AD environment.

## Demo Script

The demo script is intentionally conservative:

- It generates unique user and group names.
- It uses the same domain controller for reads and writes.
- It checks schema readiness up front.
- It only deletes objects that the current run created.

Run it like this:

```powershell
pwsh -NoLogo -NoProfile -File /Users/jonathanweinberg/Documents/Codex_DrunkenAD/examples/Invoke-DrunkenADDemo.ps1 `
    -DomainController 'dc01.contoso.com' `
    -DnsSuffix 'contoso.com'
```

Or pass a custom demo map into the script:

```powershell
$attributeMap = @{
    'Org-'  = @('department', 'title')
    'Flags-' = @('company')
}
pwsh -NoLogo -NoProfile -File /Users/jonathanweinberg/Documents/Codex_DrunkenAD/examples/Invoke-DrunkenADDemo.ps1 `
    -DomainController 'dc01.contoso.com' `
    -DnsSuffix 'contoso.com' `
    -AttributeMap $attributeMap `
    -IncludeDefaultAttributeMap
```

## Design Notes

There are now two layers on purpose:

- `Get-/Set-/Remove-ADUserDrinkData` is the preferred generic data-store API.
- `Invoke-ADUserDrinkDataDemo` is the preferred way to demonstrate or seed example namespaces from real user attributes.
- `Get-AdUserDrinkPrefixedData`, `Set-ADUserDrinkPrefixedData`, and `Update-ADUserDrinkAttribute` remain as compatibility surfaces for older call sites.

The long-term direction should be:

1. Keep the module.
2. Expand the integration coverage against the live demo AD environment.
3. Add Pester tests for any future namespace conventions before enabling them by default.
