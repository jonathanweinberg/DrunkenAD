# Schema Enablement

DrunkenAD depends on two separate schema conditions:

- `drink` exists and is not defunct
- `drink` is allowed on the Active Directory `user` class

The first condition is schema presence. The second condition is actual readiness for DrunkenAD writes on user objects.

## Schema Design and Script Scope

`drink` need not appear directly in `user.mayContain` to be valid on users. Attributes can also be inherited from superclasses and associated auxiliary classes, through the applicable `mayContain`, `systemMayContain`, `mustContain`, and `systemMustContain` lists. An existing inherited or auxiliary-class allowance is acceptable; it does not require a duplicate direct addition. See Microsoft's [Class Inheritance in the Active Directory Schema](https://learn.microsoft.com/en-us/windows/win32/ad/class-inheritance-in-the-active-directory-schema).

This admin script has a narrower provisioning scope: when readiness reports `NotAllowedOnUserClass`, it adds the existing `drink` attribute directly to `user.mayContain`. It returns `AlreadyReady` without mutation when the readiness check succeeds, regardless of the source of that allowance. It does not create attributes, create or attach auxiliary classes, assign OIDs, or change inheritance. The module's readiness check owns resolution of effective class membership; the script does not implement a separate class traversal.

Microsoft documents adding optional `mayContain` attributes to existing classes as supported. An auxiliary class can group related attributes for reuse across classes, but adds another schema definition and association to manage; it is not a mandatory prerequisite for this single-attribute change. Direct modification is simpler here, but still changes the shared `user` class definition and affects classes that inherit from it, rather than only selected users or an OU. Choosing a new auxiliary-class design would be a separate, reviewed provisioning decision. See [Characteristics of Object Classes](https://learn.microsoft.com/en-us/windows/win32/ad/characteristics-of-object-classes).

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
5. Refresh the schema cache on that same schema master through RootDSE `schemaUpdateNow`.
6. Verify readiness again and allow time for replication if other DCs are involved.
7. Rerun the integration suite or live campaign harness.

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

if (-not $status.ReadyForUserWrite) {
    if ($status.BlockingReason -ne 'NotAllowedOnUserClass') {
        throw $status.BlockingMessage
    }

    Set-ADObject `
        -Identity $status.UserClassDistinguishedName `
        -Server $forest.SchemaMaster `
        -Add @{ mayContain = 'drink' } `
        -ErrorAction Stop

    $rootDse = $null
    try {
        $rootDse = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList "LDAP://$($forest.SchemaMaster)/RootDSE" -ErrorAction Stop
        $rootDse.AuthenticationType = [System.DirectoryServices.AuthenticationTypes]::Secure
        $rootDse.Put('schemaUpdateNow', 1)
        $rootDse.SetInfo()
    }
    catch {
        throw "Schema was changed, but cache refresh failed; no rollback was performed. Recheck readiness before user writes. Details: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $rootDse) {
            $rootDse.Dispose()
        }
    }
}

Test-ADDrinkAttributeReadyForUserWrite -Server $forest.SchemaMaster -PassThru | Format-List
```

If you have more than one domain controller, verify readiness against each target DC after replication:

```powershell
Test-ADDrinkAttributeReadyForUserWrite -Server 'dc01.contoso.com'
Test-ADDrinkAttributeReadyForUserWrite -Server 'dc02.contoso.com'
```

## Automated Enablement Path

Use [scripts/Enable-ADDrinkAttributeOnUserClass.ps1](../scripts/Enable-ADDrinkAttributeOnUserClass.ps1) when you want the repo to handle the guard rails for you.

Default behavior is preview only. No schema change or cache refresh happens unless you pass `-Apply` and approve the operation. `-Apply -WhatIf` performs neither the schema write nor the refresh. An already-ready result also skips both operations. Preview can still write the explicitly requested local JSON report; `-WhatIf` suppresses that file write as well.

Apply requires Windows with the ActiveDirectory module and ADSI (`System.DirectoryServices`), using the current operator's Windows identity. The refresh binds directly over LDAP to the selected schema master's RootDSE, so that LDAP endpoint must be reachable in addition to the connectivity needed by the AD cmdlets. No separate credential parameter is introduced; Windows PowerShell 5.1 remains supported.

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

After the schema write succeeds, the script writes `schemaUpdateNow = 1` to `LDAP://<selected-schema-master>/RootDSE` using ADSI `Put` followed by `SetInfo`. This is a server cache refresh, not a write to the schema naming-context object or a client-side property-cache reload. The blocking operation must succeed before the script rechecks readiness on the same server and returns the unchanged before/after report shape. `-Verbose` identifies the refresh step. See Microsoft's [Updating the Schema Cache](https://learn.microsoft.com/en-us/windows/win32/ad/updating-the-schema-cache) and [schema-master-bound example](https://learn.microsoft.com/en-us/windows/win32/ad/example-code-for-updating-the-schema-cache).

If the refresh fails, the script terminates with the target server and underlying error, explicitly noting that the schema change already completed and was not rolled back. It does not run the post-refresh readiness check or emit an `Applied` report. Any report file from an earlier run remains unchanged and is not evidence of this attempt's success. Resolve the refresh failure, complete or independently verify the target server's cache update, and recheck readiness before user writes. A later `AlreadyReady` result reflects schema metadata and does not itself retry the refresh or prove an actual user write.

Refreshing the schema master's cache does not force schema replication or refresh other DCs. Verify each intended write target after replication; schema readiness alone also does not establish the operator's permission to write user attributes.

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

That is the expected symptom when `drink` exists in schema but is not allowed on the effective user class, directly or through inheritance/auxiliary classes. A DC whose schema cache has not yet incorporated a change can also reject writes; checking stored schema metadata alone does not prove that the server cache is current.

## Rollback Notes

This repo documents rollback but does not automate it.

For the lab VM, the primary rollback path is restoring the pre-mutation snapshot created before schema changes. In a broader AD environment, follow your normal schema-change backup, approval, and recovery procedures.
