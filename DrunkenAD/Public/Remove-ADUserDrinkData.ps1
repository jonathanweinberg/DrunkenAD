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

.PARAMETER InputObject
ADUser from Get-ADUser. Requires an explicit DomainController (or Server).
Only ObjectGUID is used from the input; directory values are read on that controller.

.PARAMETER Prefixes
One or more literal prefixes to remove from the user's stored `drink` data.

.PARAMETER DomainController
Controller for schema validation and reads and writes. Required for ADUser input;
optional when using an explicit identifier.

.PARAMETER LogPath
Optional log file path for appended activity records.

.PARAMETER PassThru
Returns the computed `drink` values, including previews. This is based on the
initial read and is not a fresh directory read after the removal.

.INPUTS
Microsoft.ActiveDirectory.Management.ADUser

.OUTPUTS
Explicit identifiers: computed strings with PassThru, otherwise no output.
ADUser input: with PassThru, one object per user with ObjectGUID, SamAccountName,
Status (Written, WhatIf, Declined or NoChange), and planned FinalDrinkValues.

.EXAMPLE
Get-ADUser -Filter "Department -eq 'Example'" -Server 'dc01.contoso.com' | Remove-ADUserDrinkData -Prefixes 'App-' -WhatIf -PassThru -DomainController 'dc01.contoso.com'

Previews each user separately and returns the planned values with the user identity.

.EXAMPLE
Remove-ADUserDrinkData -SamAccountName 'TesterAccount' -Prefixes 'AppProfile-', 'Flags-' -DomainController 'dc01.contoso.com' -Confirm:$false

Removes all `AppProfile-` and `Flags-` records from the user's `drink` attribute,
leaving the built-in projection's namespaces untouched.

.EXAMPLE
Remove-ADUserDrinkData -Mail 'tester@contoso.com' -Prefixes 'Temp-' -DomainController 'dc01.contoso.com' -WhatIf

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

        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'ADUser')]
        [PSTypeName('Microsoft.ActiveDirectory.Management.ADUser')]
        [psobject]$InputObject,

        [Parameter(Mandatory = $true)]
        [string[]]$Prefixes,

        [Alias('Server')]
        [string]$DomainController,

        [string]$LogPath,

        [switch]$PassThru
    )

    begin {
        $context = $null
        Assert-DrunkenADNonOverlappingPrefixes -Prefixes $Prefixes
        $dataMap = @{}
        foreach ($prefix in $Prefixes) { $dataMap[$prefix] = @() }
    }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'ADUser') {
            $guid = Get-DrunkenADPipelineUserGuid $InputObject $DomainController
            if ($null -eq $context) {
                $context = New-DrunkenADWriteContext -Server $DomainController
            }
            $user = Read-DrunkenADPipelineUser $guid $context.Server
            Invoke-DrunkenADPrefixWrite -User $user -Context $context -PrefixMap $DataMap -LogPath $LogPath -PassThru:$PassThru -PipelineCmdlet $PSCmdlet
        }
        else {
            $parameters = @{} + $PSBoundParameters
            $parameters.Remove('Prefixes')
            $parameters['PrefixMap'] = $DataMap
            Set-ADUserDrinkPrefixedData @parameters
        }
    }
}
