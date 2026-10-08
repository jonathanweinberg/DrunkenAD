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
Returns the computed `drink` value set, including with `WhatIf`. This is based
on the initial read and is not a fresh read after concurrent directory changes.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
System.String[]. Returned when `PassThru` is specified.

.EXAMPLE
Set-ADUserDrinkPrefixedData -SamAccountName 'TesterAccount' -PrefixMap @{ 'AppProfile-' = @('Tier=Gold') } -DomainController 'dc01.contoso.com' -Confirm:$false

Replaces the user's `AppProfile-` values with `AppProfile-Tier=Gold`, leaving the
built-in projection's `Profile-` namespace untouched.

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
    $context = New-DrunkenADWriteContext -Server $DomainController
    $identity = Get-DrunkenADIdentityParameters -BoundParameters $PSBoundParameters
    $user = Resolve-DrunkenADUser @identity -Server $context.Server -Properties @('drink')
    $writeParams = @{
        User = $user
        PrefixMap = $PrefixMap
        Context = $context
        LogPath = $LogPath
        PassThru = $PassThru
    }
    foreach ($name in @('WhatIf', 'Confirm')) {
        if ($PSBoundParameters.ContainsKey($name)) { $writeParams[$name] = $PSBoundParameters[$name] }
    }
    Invoke-DrunkenADPrefixWrite @writeParams
}
