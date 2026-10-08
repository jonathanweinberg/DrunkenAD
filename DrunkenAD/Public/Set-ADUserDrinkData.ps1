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
Returns the final stored `drink` values after the write logic is computed.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.String[]. Returned when `PassThru` is specified.

.EXAMPLE
Set-ADUserDrinkData -SamAccountName 'TesterAccount' -DataMap @{ 'Profile-' = @('Tier=Gold') } -DomainController 'dc01.contoso.com' -Confirm:$false

Stores a generic `Profile-` record in the user's `drink` attribute.

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

    Assert-DrunkenADNonOverlappingPrefixes -Prefixes @($DataMap.Keys | ForEach-Object { [string]$_ })
    Assert-ADDrinkAttributeReadyForUserWrite -Server $DomainController

    $setParams = @{
        PrefixMap        = $DataMap
        DomainController = $DomainController
        LogPath          = $LogPath
        PassThru         = $PassThru
        Confirm          = $false
    }

    $identityParams = @{}
    switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName' {
            $setParams['SamAccountName'] = $SamAccountName
            $identityParams['SamAccountName'] = $SamAccountName
        }
        'UserPrincipalName' {
            $setParams['UserPrincipalName'] = $UserPrincipalName
            $identityParams['UserPrincipalName'] = $UserPrincipalName
        }
        'EmployeeID' {
            $setParams['EmployeeID'] = $EmployeeID
            $identityParams['EmployeeID'] = $EmployeeID
        }
        'Mail' {
            $setParams['Mail'] = $Mail
            $identityParams['Mail'] = $Mail
        }
        'Pager' {
            $setParams['Pager'] = $Pager
            $identityParams['Pager'] = $Pager
        }
    }

    $identityDescription = Get-DrunkenADIdentityDescription @identityParams

    if ($PSCmdlet.ShouldProcess($identityDescription, 'Write generic drink data')) {
        Set-ADUserDrinkPrefixedData @setParams
    }
}
