<#
.SYNOPSIS
Compatibility wrapper for updating prefixed `drink` values.

.DESCRIPTION
Converts the legacy `-Prefixes` and `-DrinkValues` parameter shape into the safer
`PrefixMap` model used by `Set-ADUserDrinkPrefixedData`. This function keeps
older call sites working while preserving exact lookup, literal prefix handling,
and `ShouldProcess` support.

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

.PARAMETER DrinkValues
One or more suffix values to apply.

.PARAMETER Prefixes
One or more literal prefixes to apply.

.PARAMETER DomainController
Optional domain controller to use consistently for validation, lookup, and write.

.PARAMETER AutoConfirm
Suppresses confirmation prompts by forwarding `-Confirm:$false`.

.PARAMETER EnableLogging
Enables default logging when no `LogPath` is supplied.

.PARAMETER LogPath
Optional explicit log file path.

.PARAMETER PassThru
Returns the final `drink` value set after the update logic is computed.

.OUTPUTS
System.String[]

.EXAMPLE
Update-ADUserDrinkAttribute -SamAccountName 'TesterAccount' -Prefixes 'Profile-' -DrinkValues 'Tier=Gold' -AutoConfirm

Replaces the `Profile-` slice of the `drink` attribute with a single value.

.EXAMPLE
Update-ADUserDrinkAttribute -EmployeeID '123456' -Prefixes 'One-', 'Two-' -DrinkValues 'A', 'B' -WhatIf

Previews an aligned multi-prefix update without writing any changes.
#>
function Update-ADUserDrinkAttribute {
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
        [string[]]$DrinkValues,

        [Parameter(Mandatory = $true)]
        [string[]]$Prefixes,

        [Alias('Server')]
        [string]$DomainController,

        [switch]$AutoConfirm,

        [switch]$EnableLogging,

        [string]$LogPath,

        [switch]$PassThru
    )

    Assert-ADDrinkAttributeReadyForUserWrite -Server $DomainController

    $prefixMap = ConvertTo-DrunkenADPrefixMap -Prefixes $Prefixes -DrinkValues $DrinkValues
    $effectiveLogPath = Resolve-DrunkenADLogPath -LogPath $LogPath -EnableLogging:$EnableLogging
    $identityParams = @{}

    $setParams = @{
        PrefixMap        = $prefixMap
        DomainController = $DomainController
        LogPath          = $effectiveLogPath
        PassThru         = $PassThru
        Confirm          = $false
    }

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

    $shouldUpdate = if ($AutoConfirm -and -not $WhatIfPreference) {
        $true
    }
    else {
        $PSCmdlet.ShouldProcess($identityDescription, 'Update drink attribute')
    }

    if ($shouldUpdate) {
        Set-ADUserDrinkPrefixedData @setParams
    }
}
