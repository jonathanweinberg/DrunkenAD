<#
.SYNOPSIS
Compatibility wrapper for the older projection command name.

.DESCRIPTION
Calls `Set-ADUserDrinkProjection` with the same identity, projection,
controller, logging, and passthrough parameters. This command is retained for
backward compatibility with earlier scripts and examples, but it is documented
as a complete command so older operators can rely on `Get-Help` directly.

.PARAMETER SamAccountName
Finds the user by exact `sAMAccountName`.

.PARAMETER UserPrincipalName
Finds the user by exact `userPrincipalName`.

.PARAMETER EmployeeID
Finds the user by exact `employeeID`.

.PARAMETER Mail
Finds the user by exact `mail`.

.PARAMETER Pager
Finds the user by exact `pager`.

.PARAMETER AttributeMap
Hashtable whose keys are literal namespace prefixes and whose values are one or
more user attribute names to project.

.PARAMETER IncludeDefaultAttributeMap
Merges the supplied `AttributeMap` into the built-in default projection map.

.PARAMETER DomainController
Optional domain controller to use consistently for lookup and write operations.

.PARAMETER LogPath
Optional log file path for appended activity records.

.PARAMETER PassThru
Returns the projection summary produced by `Set-ADUserDrinkProjection`.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.Management.Automation.PSCustomObject. Returned only when `PassThru` is
specified and the projection command produces a summary.

.EXAMPLE
Invoke-ADUserDrinkDataDemo -SamAccountName 'TesterAccount' -DomainController 'dc01.contoso.com' -Confirm:$false

Runs the default projection workflow through the compatibility command name.

.EXAMPLE
Invoke-ADUserDrinkDataDemo -Mail 'tester@contoso.com' -AttributeMap @{ 'Profile-' = @('department') } -WhatIf

Previews a custom projection for a user resolved by exact mail address.

.NOTES
Prefer `Set-ADUserDrinkProjection` for new usage.

.LINK
about_DrunkenAD

.LINK
Set-ADUserDrinkProjection

.COMPONENT
DrunkenAD

.ROLE
User

.ROLE
Operator

.FUNCTIONALITY
Compatibility projection wrapper for Active Directory drink data
#>
function Invoke-ADUserDrinkDataDemo {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'SamAccountName')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'SamAccountName')]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true, ParameterSetName = 'UserPrincipalName')]
        [string]$UserPrincipalName,

        [Parameter(Mandatory = $true, ParameterSetName = 'EmployeeID')]
        [string]$EmployeeID,

        [Parameter(Mandatory = $true, ParameterSetName = 'Mail')]
        [string]$Mail,

        [Parameter(Mandatory = $true, ParameterSetName = 'Pager')]
        [string]$Pager,

        [hashtable]$AttributeMap,

        [switch]$IncludeDefaultAttributeMap,

        [Alias('Server')]
        [string]$DomainController,

        [string]$LogPath,

        [switch]$PassThru
    )

    Set-ADUserDrinkProjection @PSBoundParameters
}
