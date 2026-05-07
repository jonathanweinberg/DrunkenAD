# Schema Enablement

DrunkenAD depends on two separate schema conditions:

- `drink` exists and is not defunct
- `drink` is allowed on the Active Directory `user` class

The first condition is schema presence. The second condition is actual readiness for DrunkenAD writes on user objects.

## Readiness Checks

Import the module and verify both states explicitly:

```powershell
Import-Module /temp/DrunkenAD/DrunkenAD/DrunkenAD.psd1 -Force

Test-ADDrinkAttributeEnabled -Server 'dc01.contoso.com'
Test-ADDrinkAttributeReadyForUserWrite -Server 'dc01.contoso.com' -PassThru | Format-List
```

Expected outcomes:

- `Test-ADDrinkAttributeEnabled` returns `True` when `drink` exists and is not defunct
- `Test-ADDrinkAttributeReadyForUserWrite` returns `True` only when `drink` is also allowed on `user`

If the first command is `True` and the second is `False`, the schema is only partially ready. DrunkenAD reads may still work, but writes will fail.

## Manual Enablement Path

Use this when you want to inspect each step yourself.

1. Take a VM snapshot or follow your normal forest backup process before any schema change.
2. Identify the schema master and confirm the expected forest and domain.
3. Verify the current readiness state.
4. Add `drink` to the `user` class `mayContain` list on the schema master.
5. Verify readiness again and allow time for replication if other DCs are involved.
6. Rerun the integration suite or live campaign harness.

Example:

```powershell
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module /temp/DrunkenAD/DrunkenAD/DrunkenAD.psd1 -Force

$forest = Get-ADForest -Server 'dc01.contoso.com'
$domain = Get-ADDomain -Server $forest.SchemaMaster
$status = Test-ADDrinkAttributeReadyForUserWrite -Server $forest.SchemaMaster -PassThru

$forest | Select-Object RootDomain, SchemaMaster
$domain | Select-Object DNSRoot
$status | Format-List Enabled, AllowedOnUserClass, ReadyForUserWrite, BlockingReason, SchemaNamingContext, UserClassDistinguishedName

Set-ADObject `
    -Identity $status.UserClassDistinguishedName `
    -Server $forest.SchemaMaster `
    -Add @{ mayContain = 'drink' } `
    -ErrorAction Stop

Test-ADDrinkAttributeReadyForUserWrite -Server $forest.SchemaMaster -PassThru | Format-List
```

If you have more than one domain controller, verify readiness against each target DC after replication:

```powershell
Test-ADDrinkAttributeReadyForUserWrite -Server 'dc01.contoso.com'
Test-ADDrinkAttributeReadyForUserWrite -Server 'dc02.contoso.com'
```

## Automated Enablement Path

Use [scripts/Enable-ADDrinkAttributeOnUserClass.ps1](../scripts/Enable-ADDrinkAttributeOnUserClass.ps1) when you want the repo to handle the guard rails for you.

Default behavior is preview only. No schema change happens unless you pass `-Apply`.

Preview mode:

```powershell
pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/scripts/Enable-ADDrinkAttributeOnUserClass.ps1 `
    -Server 'dc01.contoso.com' `
    -ReportPath /tmp/drunkenad-schema-preview.json
```

That preview:

- imports the module and ActiveDirectory
- resolves the effective target server
- checks current readiness through `Test-ADDrinkAttributeReadyForUserWrite -PassThru`
- reports the forest root, domain DNS root, schema master, and blocking reason
- writes a machine-readable JSON report if `-ReportPath` is provided

Apply mode requires explicit expectations for the forest, domain, and schema master:

```powershell
Import-Module ActiveDirectory -ErrorAction Stop

$forest = Get-ADForest -Server 'dc01.contoso.com'
$domain = Get-ADDomain -Server $forest.SchemaMaster

pwsh -NoLogo -NoProfile -File /temp/DrunkenAD/scripts/Enable-ADDrinkAttributeOnUserClass.ps1 `
    -Server $forest.SchemaMaster `
    -Apply `
    -ExpectedForestRoot $forest.RootDomain `
    -ExpectedDomainDnsRoot $domain.DNSRoot `
    -ExpectedSchemaMaster $forest.SchemaMaster `
    -ReportPath /tmp/drunkenad-schema-apply.json `
    -Confirm:$false
```

The script refuses to mutate schema unless all of the following are true:

- `drink` exists and is not defunct
- the blocking reason is specifically `NotAllowedOnUserClass`
- the target server is the schema master
- the live forest root matches `-ExpectedForestRoot`
- the live domain DNS root matches `-ExpectedDomainDnsRoot`
- the live schema master matches `-ExpectedSchemaMaster`

After a successful apply, the script rechecks readiness and returns a before/after report.

## Safe Operator Path

For production-like environments, the safest path is:

1. Run the preview command first.
2. Review the JSON report and confirm the schema master.
3. Confirm you have a rollback point.
4. Run apply mode against the schema master only.
5. Recheck readiness.
6. Rerun [tests/DrunkenAD.Integration.Tests.ps1](../tests/DrunkenAD.Integration.Tests.ps1) or [tests/Live/Invoke-DrunkenADLiveCampaign.ps1](../tests/Live/Invoke-DrunkenADLiveCampaign.ps1).

## Canonical Failure Mode

The live lab result from April 9, 2026 is the reference example for an incomplete schema state:

- `Test-ADDrinkAttributeEnabled` returned `True`
- `Test-ADDrinkAttributeReadyForUserWrite` returned `False`
- the live validation harness stopped in preflight
- direct writes failed with `An attempt was made to modify an object to include an attribute that is not legal for its class`

That is the expected symptom when `drink` exists in schema but has not been added to `user.mayContain`.

## Rollback Notes

This repo documents rollback but does not automate it.

For the lab VM, the primary rollback path is restoring the pre-mutation snapshot created before schema changes. In a broader AD environment, follow your normal schema-change backup, approval, and recovery procedures.
