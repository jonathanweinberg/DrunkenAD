<#
.SYNOPSIS
Writes one or more namespaces of generic data into the Active Directory `drink` attribute.

.DESCRIPTION
Treats the multivalued `drink` attribute like a small prefixed data store. Each
key in `DataMap` is a literal namespace prefix, and each associated value array
contains the payload values to store under that namespace. Existing values for
those prefixes are replaced while unrelated values are preserved.

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

.PARAMETER DataMap
Hashtable whose keys are literal prefixes and whose values are arrays of suffix
values to store beneath each prefix.

.PARAMETER DomainController
Optional domain controller to use consistently for validation, lookup, and write.

.PARAMETER LogPath
Optional log file path for appended activity records.

.PARAMETER PassThru
Returns the computed `drink` values, including previews. This is based on the
initial read and is not a fresh directory read after the write.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.String[]. Returned when `PassThru` is specified.

.EXAMPLE
Set-ADUserDrinkData -SamAccountName 'TesterAccount' -DataMap @{ 'AppProfile-' = @('Tier=Gold') } -DomainController 'dc01.contoso.com' -Confirm:$false

Stores a generic `AppProfile-` record, separate from the built-in projection's
`Profile-` namespace, in the user's `drink` attribute.

.EXAMPLE
Set-ADUserDrinkData -SamAccountName 'TesterAccount' -DataMap @{ 'Flags-' = @('Enabled', 'Audited') } -WhatIf

Previews a namespace replacement without writing changes.

.LINK
about_DrunkenAD

.LINK
Get-ADUserDrinkData

.LINK
Remove-ADUserDrinkData

.COMPONENT
DrunkenAD

.ROLE
User

.ROLE
Operator

.FUNCTIONALITY
Write namespaced Active Directory drink data
#>
function Set-ADUserDrinkData {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'SamAccountName')]
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

        [Parameter(Mandatory = $true)]
        [hashtable]$DataMap,

        [Alias('Server')]
        [string]$DomainController,

        [string]$LogPath,

        [switch]$PassThru
    )

    $parameters = @{} + $PSBoundParameters
    $parameters.Remove('DataMap')
    $parameters['PrefixMap'] = $DataMap
    Set-ADUserDrinkPrefixedData @parameters
}
