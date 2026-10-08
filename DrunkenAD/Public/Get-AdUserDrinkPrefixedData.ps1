<#
.SYNOPSIS
Gets `drink` attribute values for a user that begin with a specific literal prefix.

.DESCRIPTION
Resolves a single Active Directory user using an exact identifier, validates that
the `drink` schema attribute is enabled, and returns any `drink` values whose
leading text matches the provided prefix literally.

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

.PARAMETER DrinkValuePrefix
The literal prefix to match at the beginning of each `drink` value.

.PARAMETER DomainController
Optional domain controller to use for both schema validation and user lookup.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.String[]. Returns `drink` values that begin with the requested prefix.

.EXAMPLE
Get-AdUserDrinkPrefixedData -SamAccountName 'TesterAccount' -DrinkValuePrefix 'Profile-' -DomainController 'dc01.contoso.com'

Returns all `drink` values on the user that start with `Profile-`.

.EXAMPLE
Get-AdUserDrinkPrefixedData -UserPrincipalName 'tester@contoso.com' -DrinkValuePrefix 'Profile-'

Returns all `drink` values for that exact UPN whose prefix is `Profile-`.

.NOTES
Compatibility wrapper around `Get-ADUserDrinkData`. It remains fully documented
so older scripts can use `Get-Help Get-AdUserDrinkPrefixedData -Full` directly.

.LINK
about_DrunkenAD

.LINK
Get-ADUserDrinkData

.COMPONENT
DrunkenAD

.ROLE
User

.ROLE
Operator

.FUNCTIONALITY
Read legacy prefixed Active Directory drink data
#>
function Get-AdUserDrinkPrefixedData {
    [CmdletBinding(DefaultParameterSetName = 'SamAccountName')]
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
        [string]$DrinkValuePrefix,

        [Alias('Server')]
        [string]$DomainController
    )

    $getParams = Get-DrunkenADIdentityParameters -BoundParameters $PSBoundParameters
    $getParams.Prefix = $DrinkValuePrefix
    $getParams.DomainController = $DomainController

    Get-ADUserDrinkData @getParams
}
