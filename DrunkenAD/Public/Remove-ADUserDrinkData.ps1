<#
.SYNOPSIS
Removes one or more prefixed namespaces from the Active Directory `drink` attribute.

.DESCRIPTION
Treats the multivalued `drink` attribute like a small prefixed data store and
removes all values that begin with the specified literal prefixes while leaving
other values untouched.

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

.PARAMETER Prefixes
One or more literal prefixes to remove from the user's stored `drink` data.

.PARAMETER DomainController
Optional domain controller to use consistently for validation, lookup, and write.

.PARAMETER LogPath
Optional log file path for appended activity records.

.PARAMETER PassThru
Returns the final stored `drink` values after the removal logic is computed.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.String[]. Returned when `PassThru` is specified.

.EXAMPLE
Remove-ADUserDrinkData -SamAccountName 'TesterAccount' -Prefixes 'Profile-', 'Flags-' -DomainController 'dc01.contoso.com' -Confirm:$false

Removes all `Profile-` and `Flags-` records from the user's `drink` attribute.

.EXAMPLE
Remove-ADUserDrinkData -Mail 'tester@contoso.com' -Prefixes 'Temp-' -WhatIf

Previews removal of the `Temp-` namespace for a user resolved by exact mail.

.LINK
about_DrunkenAD

.LINK
Set-ADUserDrinkData

.LINK
Get-ADUserDrinkData

.COMPONENT
DrunkenAD

.ROLE
Operator

.FUNCTIONALITY
Remove namespaced Active Directory drink data
#>
function Remove-ADUserDrinkData {
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
        [string[]]$Prefixes,

        [Alias('Server')]
        [string]$DomainController,

        [string]$LogPath,

        [switch]$PassThru
    )

    Assert-DrunkenADNonOverlappingPrefixes -Prefixes $Prefixes
    Assert-ADDrinkAttributeReadyForUserWrite -Server $DomainController

    $dataMap = [ordered]@{}
    foreach ($prefix in $Prefixes) {
        $dataMap[$prefix] = @()
    }

    $removeParams = @{
        DataMap          = $dataMap
        DomainController = $DomainController
        LogPath          = $LogPath
        PassThru         = $PassThru
        Confirm          = $false
    }

    $identityParams = @{}
    switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName' {
            $removeParams['SamAccountName'] = $SamAccountName
            $identityParams['SamAccountName'] = $SamAccountName
        }
        'UserPrincipalName' {
            $removeParams['UserPrincipalName'] = $UserPrincipalName
            $identityParams['UserPrincipalName'] = $UserPrincipalName
        }
        'EmployeeID' {
            $removeParams['EmployeeID'] = $EmployeeID
            $identityParams['EmployeeID'] = $EmployeeID
        }
        'Mail' {
            $removeParams['Mail'] = $Mail
            $identityParams['Mail'] = $Mail
        }
        'Pager' {
            $removeParams['Pager'] = $Pager
            $identityParams['Pager'] = $Pager
        }
    }

    $identityDescription = Get-DrunkenADIdentityDescription @identityParams

    if ($PSCmdlet.ShouldProcess($identityDescription, 'Remove generic drink data')) {
        Set-ADUserDrinkData @removeParams
    }
}
