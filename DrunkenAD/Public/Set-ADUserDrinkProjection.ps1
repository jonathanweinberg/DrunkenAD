<#
.SYNOPSIS
Projects selected user attributes into the Active Directory `drink` attribute.

.DESCRIPTION
Builds a `DataMap` from selected user attributes and writes that data into the
multivalued `drink` attribute using the generic data-store API. By default, the
projection uses a built-in identity-oriented attribute map. You can replace that
default set with your own `AttributeMap`, or merge your custom map into the
default projection set.

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
more user attribute names to read and store beneath that prefix.

.PARAMETER IncludeDefaultAttributeMap
Merges the supplied `AttributeMap` into the built-in default projection map instead of
replacing it.

.PARAMETER DomainController
Optional domain controller to use consistently for lookup and write operations.

.PARAMETER LogPath
Optional log file path for appended activity records.

.PARAMETER PassThru
Returns a summary object containing the effective attribute map, the generated
data map, and the final `drink` values after the projection write.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.Management.Automation.PSCustomObject. Returned when `PassThru` is specified.

.EXAMPLE
Set-ADUserDrinkProjection -SamAccountName 'TesterAccount' -DomainController 'dc01.contoso.com' -Confirm:$false

Projects the built-in attribute map into the target user's `drink` values.

.EXAMPLE
$projectionParams = @{
    SamAccountName = 'TesterAccount'
    DomainController = 'dc01.contoso.com'
    AttributeMap = @{
        'Profile-' = @('department', 'title')
        'Flags-'   = @('company')
    }
}
Set-ADUserDrinkProjection @projectionParams -Confirm:$false

Runs the projection with a custom attribute map provided via splatting.

.EXAMPLE
Set-ADUserDrinkProjection -SamAccountName 'TesterAccount' -AttributeMap @{ 'Custom-' = @('description') } -IncludeDefaultAttributeMap -Confirm:$false

Adds a custom namespace on top of the built-in projection map.

.LINK
about_DrunkenAD

.LINK
Set-ADUserDrinkData

.LINK
Invoke-ADUserDrinkDataDemo

.COMPONENT
DrunkenAD

.ROLE
User

.ROLE
Operator

.FUNCTIONALITY
Project Active Directory user attributes into drink namespaces
#>
function Set-ADUserDrinkProjection {
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

    Assert-ADDrinkAttributeReadyForUserWrite -Server $DomainController

    $defaultAttributeMap = Get-DrunkenADDefaultProjectionAttributeMap
    $effectiveAttributeMap = if ($PSBoundParameters.ContainsKey('AttributeMap')) {
        if ($IncludeDefaultAttributeMap) {
            Merge-DrunkenADAttributeMap -BaseMap $defaultAttributeMap -OverlayMap $AttributeMap
        }
        else {
            Merge-DrunkenADAttributeMap -OverlayMap $AttributeMap
        }
    }
    else {
        $defaultAttributeMap
    }

    $attributeNames = @(
        foreach ($prefix in $effectiveAttributeMap.Keys) {
            foreach ($attributeName in @($effectiveAttributeMap[$prefix])) {
                $attributeName
            }
        }
    ) | Select-Object -Unique

    $resolveUserParams = @{
        Server     = $DomainController
        Properties = $attributeNames
    }

    $identityParams = @{}
    switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName' {
            $resolveUserParams['SamAccountName'] = $SamAccountName
            $identityParams['SamAccountName'] = $SamAccountName
        }
        'UserPrincipalName' {
            $resolveUserParams['UserPrincipalName'] = $UserPrincipalName
            $identityParams['UserPrincipalName'] = $UserPrincipalName
        }
        'EmployeeID' {
            $resolveUserParams['EmployeeID'] = $EmployeeID
            $identityParams['EmployeeID'] = $EmployeeID
        }
        'Mail' {
            $resolveUserParams['Mail'] = $Mail
            $identityParams['Mail'] = $Mail
        }
        'Pager' {
            $resolveUserParams['Pager'] = $Pager
            $identityParams['Pager'] = $Pager
        }
    }

    $user = Resolve-DrunkenADUser @resolveUserParams
    $dataMap = ConvertTo-DrunkenADProjectionDataMap -User $user -AttributeMap $effectiveAttributeMap

    if ($dataMap.Count -eq 0) {
        Write-Verbose "No populated projection data was found for $($user.SamAccountName)."
        if ($PassThru) {
            return [pscustomobject]@{
                SamAccountName      = $user.SamAccountName
                EffectiveAttributeMap = $effectiveAttributeMap
                DataMap             = $dataMap
                FinalDrinkValues    = @()
            }
        }

        return
    }

    if ($PSCmdlet.ShouldProcess($user.SamAccountName, 'Project drink data')) {
        $finalDrinkValues = Set-ADUserDrinkData -SamAccountName $user.SamAccountName -DataMap $dataMap -DomainController $DomainController -LogPath $LogPath -Confirm:$false -PassThru

        if ($PassThru) {
            return [pscustomobject]@{
                SamAccountName        = $user.SamAccountName
                EffectiveAttributeMap = $effectiveAttributeMap
                DataMap               = $dataMap
                FinalDrinkValues      = @($finalDrinkValues)
            }
        }
    }
}
