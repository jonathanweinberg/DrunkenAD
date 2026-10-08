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
Enables bounded count-only logging under the current user's local application
data when no `LogPath` is supplied. Reuses one 1 MiB log and one archive, with a
session identifier. Logging failures warn without changing the write outcome.

.PARAMETER LogPath
Optional explicit append-only log path. Caller manages access and retention.

.PARAMETER PassThru
Returns the final `drink` value set after the update logic is computed.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.String[]. Returned when `PassThru` is specified.

.EXAMPLE
Update-ADUserDrinkAttribute -SamAccountName 'TesterAccount' -Prefixes 'Profile-' -DrinkValues 'Tier=Gold' -AutoConfirm

Replaces the `Profile-` slice of the `drink` attribute with a single value.

.EXAMPLE
Update-ADUserDrinkAttribute -EmployeeID '123456' -Prefixes 'One-', 'Two-' -DrinkValues 'A', 'B' -WhatIf

Previews an aligned multi-prefix update without writing any changes.

.LINK
about_DrunkenAD

.LINK
Set-ADUserDrinkPrefixedData

.LINK
Set-ADUserDrinkData

.COMPONENT
DrunkenAD

.ROLE
User

.ROLE
Operator

.FUNCTIONALITY
Update legacy Active Directory drink values
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

    $prefixMap = ConvertTo-DrunkenADPrefixMap -Prefixes $Prefixes -DrinkValues $DrinkValues
    Assert-DrunkenADNonOverlappingPrefixes -Prefixes @($prefixMap.Keys | ForEach-Object { [string]$_ })
    $parameters = @{} + $PSBoundParameters
    foreach ($name in @('Prefixes', 'DrinkValues', 'AutoConfirm', 'EnableLogging')) {
        $parameters.Remove($name)
    }
    $parameters['PrefixMap'] = $prefixMap
    $parameters['LogPath'] = Resolve-DrunkenADLogPath -LogPath $LogPath -EnableLogging:$EnableLogging
    if ($AutoConfirm -and -not $PSBoundParameters.ContainsKey('Confirm')) {
        $parameters['Confirm'] = $false
    }
    Set-ADUserDrinkPrefixedData @parameters
}
