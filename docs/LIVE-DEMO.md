# Live Demo AD Plan

This project is already structured for a live Active Directory demo environment. The current intended demo story is a generic prefixed data store living inside the `drink` attribute.

## Readiness Checklist

Before the demo, make sure the environment has:

- RSAT / ActiveDirectory module available to the PowerShell host running the tests
- a reachable writable domain controller
- the `drink` attribute enabled in the schema
- permission to create and remove temporary test users
- permission to update the `drink` attribute on those users

## Suggested Environment Variables

Set these when the environment is ready:

```powershell
$env:DRUNKENAD_RUN_INTEGRATION = '1'
$env:DRUNKENAD_TEST_DC = 'dc01.contoso.com'
$env:DRUNKENAD_TEST_DNS_SUFFIX = 'contoso.com'
```

Optional:

```powershell
$env:DRUNKENAD_TEST_USER_OU = 'OU=Demo Users,DC=contoso,DC=com'
```

## First-Day Smoke Test

When the live environment appears, this is the order I would use:

1. Import the module from [DrunkenAD.psd1](/Users/jonathanweinberg/Documents/Codex_DrunkenAD/DrunkenAD/DrunkenAD.psd1).
2. Run `Test-ADDrinkAttributeEnabled`.
3. Run one `-WhatIf` write with `Invoke-ADUserDrinkDataDemo`.
4. Run the unit suite.
5. Run the integration suite.
6. Run the demo script.

## Demo Narrative

For a clean live walkthrough:

1. Show schema readiness with `Test-ADDrinkAttributeEnabled`.
2. Create a temporary user through the demo script.
3. Run `Invoke-ADUserDrinkDataDemo` with the built-in attribute map.
4. Run it again with a custom splatted `AttributeMap`.
5. Show that unrelated namespaces stay untouched.
6. Read the values back with `Get-ADUserDrinkData`.
7. Clean up the temporary objects.

## What To Watch Closely

The first live run should pay extra attention to:

- replication lag if multiple DCs exist
- delegated write permissions on `drink`
- default user creation container or required OU path
- any environment-specific restrictions on `pager`, `mail`, or `userPrincipalName`

## Next Documentation Pass

Once the demo AD environment is available, the next useful documentation upgrade will be:

- a transcript of a successful demo run
- exact screenshots or terminal captures
- a short troubleshooting section based on real errors from that environment
