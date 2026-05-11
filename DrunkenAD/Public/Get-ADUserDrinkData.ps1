<#
.SYNOPSIS
Gets data entries stored in the Active Directory `drink` attribute.

.DESCRIPTION
Treats the multivalued `drink` attribute like a small prefixed data store. The
function resolves a single Active Directory user by an exact identifier,
validates that the `drink` schema attribute is enabled, and returns either all
stored values or only those values that match a supplied literal prefix.

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

.PARAMETER Prefix
Optional literal prefix used to filter the returned `drink` values.

.PARAMETER DomainController
Optional domain controller to use for both schema validation and user lookup.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.String[]. Returns the matching `drink` values for the resolved user.

.EXAMPLE
Get-ADUserDrinkData -SamAccountName 'TesterAccount' -DomainController 'dc01.contoso.com'

Returns all values currently stored in the user's `drink` attribute.

.EXAMPLE
Get-ADUserDrinkData -SamAccountName 'TesterAccount' -Prefix 'Profile-' -DomainController 'dc01.contoso.com'

Returns only the `drink` values that start with the literal prefix `Profile-`.

.LINK
about_DrunkenAD

.LINK
Set-ADUserDrinkData

.COMPONENT
DrunkenAD

.ROLE
User

.ROLE
Operator

.FUNCTIONALITY
Read namespaced Active Directory drink data
#>
function Get-ADUserDrinkData {
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

        [string]$Prefix,

        [Alias('Server')]
        [string]$DomainController
    )

    Assert-ADDrinkAttributeEnabled -Server $DomainController

    $resolveUserParams = @{
        Server     = $DomainController
        Properties = @('drink')
    }

    switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName'    { $resolveUserParams['SamAccountName'] = $SamAccountName }
        'UserPrincipalName' { $resolveUserParams['UserPrincipalName'] = $UserPrincipalName }
        'EmployeeID'        { $resolveUserParams['EmployeeID'] = $EmployeeID }
        'Mail'              { $resolveUserParams['Mail'] = $Mail }
        'Pager'             { $resolveUserParams['Pager'] = $Pager }
    }

    $values = ConvertTo-DrunkenADStringArray -Values (Resolve-DrunkenADUser @resolveUserParams).drink -SkipBlank

    if ($PSBoundParameters.ContainsKey('Prefix')) {
        $escapedPrefix = [regex]::Escape($Prefix)
        $values = @($values | Where-Object { $_ -match ('^{0}' -f $escapedPrefix) })
    }

    @($values)
}
