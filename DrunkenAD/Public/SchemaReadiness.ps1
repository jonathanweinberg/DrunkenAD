<#
.SYNOPSIS
Tests whether the Active Directory `drink` attribute exists and is not defunct.

.DESCRIPTION
Queries the schema naming context on the target domain controller and verifies
that an attribute with the LDAP display name `drink` exists and is not defunct.
The Boolean result preserves the original meaning of schema presence. Use
`Test-ADDrinkAttributeReadyForUserWrite` when you need to know whether the
attribute is also allowed on the Active Directory `user` class.

.PARAMETER Server
Optional domain controller to query. When omitted, the default AD connection
behavior is used.

.PARAMETER PassThru
Returns a richer object describing the lookup instead of a simple Boolean.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.Boolean. Returns `$true` when the schema attribute exists and is active.
System.Management.Automation.PSCustomObject. Returned when `PassThru` is specified.

.EXAMPLE
Test-ADDrinkAttributeEnabled -Server 'dc01.contoso.com'

Returns `$true` when the `drink` attribute is enabled on the target schema.

.EXAMPLE
Test-ADDrinkAttributeEnabled -Server 'dc01.contoso.com' -PassThru

Returns detailed schema lookup information, including whether `drink` is allowed
on the Active Directory `user` class.

.LINK
about_DrunkenAD

.LINK
Test-ADDrinkAttributeReadyForUserWrite

.COMPONENT
DrunkenAD

.ROLE
Operator

.FUNCTIONALITY
Check Active Directory drink schema presence
#>
function Test-ADDrinkAttributeEnabled {
    [CmdletBinding()]
    param(
        [string]$Server,

        [switch]$PassThru
    )

    $status = Get-DrunkenADDrinkAttributeStatus -Server $Server

    if ($PassThru) {
        $status
        return
    }

    $status.Enabled
}

<#
.SYNOPSIS
Tests whether the Active Directory `drink` attribute is ready for user writes.

.DESCRIPTION
Queries the schema naming context on the target domain controller and verifies
that the `drink` attribute exists, is not defunct, and is allowed on the
Active Directory `user` class.

.PARAMETER Server
Optional domain controller to query. When omitted, the default AD connection
behavior is used.

.PARAMETER PassThru
Returns a richer object describing both schema presence and write readiness.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.Boolean. Returns `$true` when user write readiness is confirmed.
System.Management.Automation.PSCustomObject. Returned when `PassThru` is specified.

.EXAMPLE
Test-ADDrinkAttributeReadyForUserWrite -Server 'dc01.contoso.com'

Returns `$true` only when DrunkenAD can safely write `drink` values to user
objects on the target environment.

.EXAMPLE
Test-ADDrinkAttributeReadyForUserWrite -Server 'dc01.contoso.com' -PassThru

Returns detailed readiness information, including the blocking reason when user
writes are not currently supported.

.LINK
about_DrunkenAD

.LINK
Test-ADDrinkAttributeEnabled

.COMPONENT
DrunkenAD

.ROLE
Operator

.FUNCTIONALITY
Check Active Directory drink user-write readiness
#>
function Test-ADDrinkAttributeReadyForUserWrite {
    [CmdletBinding()]
    param(
        [string]$Server,

        [switch]$PassThru
    )

    $status = Get-DrunkenADDrinkAttributeStatus -Server $Server

    if ($PassThru) {
        $status
        return
    }

    $status.ReadyForUserWrite
}
