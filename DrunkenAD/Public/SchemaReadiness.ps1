<#
.SYNOPSIS
Tests whether the Active Directory `drink` attribute exists and is not defunct.

.DESCRIPTION
Queries the schema naming context on the target domain controller and verifies
that an attribute with the LDAP display name `drink` exists and is not defunct.
Both the Boolean and PassThru results check only schema presence, without walking
user class inheritance. In a PassThru report, ReadinessEvaluated is false and
AllowedOnUserClass, ReadyForUserWrite, RangeUpper, and UserClassDistinguishedName
are null because write readiness was not assessed. Use
`Test-ADDrinkAttributeReadyForUserWrite` when you need to know whether the
attribute is also allowed on the Active Directory `user` class.

.PARAMETER Server
Optional host, IP address, alias, or tunnel endpoint, used exactly as supplied.
When omitted or when the supplied DNS name matches RootDSE's default domain,
schema queries use RootDSE's domain controller hostname. Explicit ports are retained.

.PARAMETER PassThru
Returns a richer object describing schema presence instead of a simple Boolean.
Write readiness fields are unassessed; use Test-ADDrinkAttributeReadyForUserWrite
for a full readiness report.

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

Returns detailed schema presence information without evaluating user write readiness.

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

    $status = Get-DrunkenADDrinkAttributeStatus -Server $Server -PresenceOnly

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
Optional host, IP address, alias, or tunnel endpoint, used exactly as supplied.
When omitted or when the supplied DNS name matches RootDSE's default domain,
schema queries use RootDSE's domain controller hostname. Explicit ports are retained.

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
