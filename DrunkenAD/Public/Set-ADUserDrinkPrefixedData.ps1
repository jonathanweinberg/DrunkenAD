<#
.SYNOPSIS
Safely replaces one or more prefixed slices of a user's `drink` attribute.

.DESCRIPTION
Resolves a single user by an exact identifier, validates the `drink` schema
attribute, removes any existing `drink` values for the prefixes supplied in
`PrefixMap`, and writes the replacement values back with `ShouldProcess`
support. Prefix matching is literal rather than regex-based.

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

.PARAMETER PrefixMap
Hashtable whose keys are literal prefixes and whose values are arrays of suffix
values to store under each prefix.

.PARAMETER DomainController
Optional domain controller to use consistently for validation, lookup, and write.

.PARAMETER LogPath
Optional log file path for appended activity records.

.PARAMETER PassThru
Returns the final `drink` value set after the update logic is computed.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.String[]. Returned when `PassThru` is specified.

.EXAMPLE
Set-ADUserDrinkPrefixedData -SamAccountName 'TesterAccount' -PrefixMap @{ 'Profile-' = @('Tier=Gold') } -DomainController 'dc01.contoso.com' -Confirm:$false

Replaces the user's `Profile-` values with `Profile-Tier=Gold`.

.EXAMPLE
Set-ADUserDrinkPrefixedData -UserPrincipalName 'tester@contoso.com' -PrefixMap @{ 'App[01]-' = @('Second') } -WhatIf

Shows what would change for a literal prefix containing regex metacharacters.

.NOTES
Lower-level prefixed API retained for compatibility. `Set-ADUserDrinkData` is the
preferred higher-level name when treating the attribute as a generic data store.

.LINK
about_DrunkenAD

.LINK
Set-ADUserDrinkData

.LINK
Get-AdUserDrinkPrefixedData

.COMPONENT
DrunkenAD

.ROLE
User

.ROLE
Operator

.FUNCTIONALITY
Write legacy prefixed Active Directory drink data
#>
function Set-ADUserDrinkPrefixedData {
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
        [hashtable]$PrefixMap,

        [Alias('Server')]
        [string]$DomainController,

        [string]$LogPath,

        [switch]$PassThru
    )

    Assert-DrunkenADNonOverlappingPrefixes -Prefixes @($PrefixMap.Keys | ForEach-Object { [string]$_ })
    Assert-ADDrinkAttributeReadyForUserWrite -Server $DomainController

    $identityParams = @{}
    switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName'   { $identityParams['SamAccountName'] = $SamAccountName }
        'UserPrincipalName' { $identityParams['UserPrincipalName'] = $UserPrincipalName }
        'EmployeeID'       { $identityParams['EmployeeID'] = $EmployeeID }
        'Mail'             { $identityParams['Mail'] = $Mail }
        'Pager'            { $identityParams['Pager'] = $Pager }
    }

    $identityDescription = Get-DrunkenADIdentityDescription @identityParams
    $effectiveLogPath = Resolve-DrunkenADLogPath -LogPath $LogPath
    Write-Verbose "Resolving user by $identityDescription."
    Write-DrunkenADLog -LogPath $effectiveLogPath -Message "Resolving user by $identityDescription."

    $resolveUserParams = @{
        Server     = $DomainController
        Properties = @('drink')
    }

    switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName'   { $resolveUserParams['SamAccountName'] = $SamAccountName }
        'UserPrincipalName' { $resolveUserParams['UserPrincipalName'] = $UserPrincipalName }
        'EmployeeID'       { $resolveUserParams['EmployeeID'] = $EmployeeID }
        'Mail'             { $resolveUserParams['Mail'] = $Mail }
        'Pager'            { $resolveUserParams['Pager'] = $Pager }
    }

    $user = Resolve-DrunkenADUser @resolveUserParams
    $currentDrinks = ConvertTo-DrunkenADStringArray -Values $user.drink -SkipBlank
    $updatedDrinks = @($currentDrinks)

    foreach ($prefixKey in $PrefixMap.Keys) {
        $prefix = [string]$prefixKey
        if ([string]::IsNullOrWhiteSpace($prefix)) {
            throw "Prefix values cannot be null, empty, or whitespace."
        }

        $updatedDrinks = @($updatedDrinks | Where-Object {
            -not $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
        })

        $rawValues = ConvertTo-DrunkenADStringArray -Values $PrefixMap[$prefixKey] -SkipBlank
        $prefixedValues = @()

        foreach ($rawValue in $rawValues) {
            $prefixedValue = '{0}{1}' -f $prefix, $rawValue
            if ($prefixedValues -notcontains $prefixedValue) {
                $prefixedValues += $prefixedValue
            }
        }

        Write-Verbose "Prepared $($prefixedValues.Count) replacement value(s) for prefix '$prefix'."
        Write-DrunkenADLog -LogPath $effectiveLogPath -Message "Prepared $($prefixedValues.Count) replacement value(s) for prefix '$prefix'."

        foreach ($prefixedValue in $prefixedValues) {
            if ($updatedDrinks -notcontains $prefixedValue) {
                $updatedDrinks += $prefixedValue
            }
        }
    }

    $updatedDrinks = ConvertTo-DrunkenADStringArray -Values $updatedDrinks -SkipBlank

    if (Test-DrunkenADStringSetEqual -ReferenceValues $currentDrinks -DifferenceValues $updatedDrinks) {
        Write-Verbose "No drink attribute changes are required for $($user.SamAccountName)."
        Write-DrunkenADLog -LogPath $effectiveLogPath -Message "No drink attribute changes were required for $($user.SamAccountName)."

        if ($PassThru) {
            return $updatedDrinks
        }

        return
    }

    $setUserParams = @{
        Identity    = $user.DistinguishedName
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($DomainController)) {
        $setUserParams['Server'] = $DomainController
    }

    $operation = if ($updatedDrinks.Count -eq 0) {
        'Clear drink attribute'
    }
    else {
        'Replace drink attribute values'
    }

    if ($PSCmdlet.ShouldProcess($user.SamAccountName, $operation)) {
        if ($updatedDrinks.Count -eq 0) {
            $setUserParams['Clear'] = 'drink'
        }
        else {
            $setUserParams['Replace'] = @{ drink = [string[]]$updatedDrinks }
        }

        Set-ADUser @setUserParams
        Write-Verbose "Updated drink attribute for $($user.SamAccountName)."
        Write-DrunkenADLog -LogPath $effectiveLogPath -Message "Updated drink attribute for $($user.SamAccountName) to: $($updatedDrinks -join ', ')"
    }

    if ($PassThru) {
        @($updatedDrinks)
    }
}
