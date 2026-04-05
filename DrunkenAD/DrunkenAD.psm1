Set-StrictMode -Version 3.0

function Initialize-DrunkenADModule {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -Name ActiveDirectory)) {
        Import-Module ActiveDirectory -ErrorAction Stop
    }
}

function ConvertTo-DrunkenADLdapFilterValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $builder = New-Object System.Text.StringBuilder

    foreach ($character in $Value.ToCharArray()) {
        switch ([int][char]$character) {
            0   { [void]$builder.Append('\00') }
            40  { [void]$builder.Append('\28') }
            41  { [void]$builder.Append('\29') }
            42  { [void]$builder.Append('\2a') }
            92  { [void]$builder.Append('\5c') }
            default { [void]$builder.Append($character) }
        }
    }

    $builder.ToString()
}

function Resolve-DrunkenADLogPath {
    [CmdletBinding()]
    param(
        [string]$LogPath,

        [switch]$EnableLogging
    )

    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        return $LogPath
    }

    if (-not $EnableLogging) {
        return $null
    }

    $tempPath = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempPath)) {
        $tempPath = [System.IO.Path]::GetTempPath()
    }

    Join-Path -Path $tempPath -ChildPath 'DrunkenAD.log'
}

function Write-DrunkenADLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$LogPath
    )

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        return
    }

    $directoryPath = Split-Path -Path $LogPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($directoryPath) -and -not (Test-Path -LiteralPath $directoryPath)) {
        New-Item -Path $directoryPath -ItemType Directory -Force | Out-Null
    }

    Add-Content -LiteralPath $LogPath -Value ('{0:u} {1}' -f (Get-Date), $Message)
}

function Get-DrunkenADIdentityDescription {
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
        [string]$Pager
    )

    switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName'   { return "SamAccountName '$SamAccountName'" }
        'UserPrincipalName' { return "UserPrincipalName '$UserPrincipalName'" }
        'EmployeeID'       { return "EmployeeID '$EmployeeID'" }
        'Mail'             { return "mail '$Mail'" }
        'Pager'            { return "pager '$Pager'" }
        default            { throw "Unsupported parameter set '$($PSCmdlet.ParameterSetName)'." }
    }
}

function Resolve-DrunkenADUser {
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

        [string[]]$Properties = @('drink'),

        [string]$Server
    )

    Initialize-DrunkenADModule

    $identityParams = @{}
    switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName'   { $identityParams['SamAccountName'] = $SamAccountName }
        'UserPrincipalName' { $identityParams['UserPrincipalName'] = $UserPrincipalName }
        'EmployeeID'       { $identityParams['EmployeeID'] = $EmployeeID }
        'Mail'             { $identityParams['Mail'] = $Mail }
        'Pager'            { $identityParams['Pager'] = $Pager }
    }

    $identityDescription = Get-DrunkenADIdentityDescription @identityParams
    $ldapFilter = switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName' {
            '(sAMAccountName={0})' -f (ConvertTo-DrunkenADLdapFilterValue -Value $SamAccountName)
        }
        'UserPrincipalName' {
            '(userPrincipalName={0})' -f (ConvertTo-DrunkenADLdapFilterValue -Value $UserPrincipalName)
        }
        'EmployeeID' {
            '(employeeID={0})' -f (ConvertTo-DrunkenADLdapFilterValue -Value $EmployeeID)
        }
        'Mail' {
            '(mail={0})' -f (ConvertTo-DrunkenADLdapFilterValue -Value $Mail)
        }
        'Pager' {
            '(pager={0})' -f (ConvertTo-DrunkenADLdapFilterValue -Value $Pager)
        }
        default {
            throw "Unsupported parameter set '$($PSCmdlet.ParameterSetName)'."
        }
    }

    $userParams = @{
        LDAPFilter = $ldapFilter
        Properties = @($Properties + 'distinguishedName', 'samAccountName', 'drink')
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $userParams['Server'] = $Server
    }

    $users = @(Get-ADUser @userParams)

    if ($users.Count -eq 0) {
        throw "No Active Directory user matched $identityDescription."
    }

    if ($users.Count -gt 1) {
        throw "The lookup for $identityDescription matched $($users.Count) users. Use a unique identifier."
    }

    $users[0]
}

<#
.SYNOPSIS
Tests whether the Active Directory `drink` attribute is available for use.

.DESCRIPTION
Queries the schema naming context on the target domain controller and verifies
that an attribute with the LDAP display name `drink` exists and is not defunct.

.PARAMETER Server
Optional domain controller to query. When omitted, the default AD connection
behavior is used.

.PARAMETER PassThru
Returns a richer object describing the lookup instead of a simple Boolean.

.OUTPUTS
System.Boolean
System.Management.Automation.PSCustomObject

.EXAMPLE
Test-ADDrinkAttributeEnabled -Server 'dc01.contoso.com'

Returns `$true` when the `drink` attribute is enabled on the target schema.

.EXAMPLE
Test-ADDrinkAttributeEnabled -Server 'dc01.contoso.com' -PassThru

Returns detailed schema lookup information for troubleshooting.
#>
function Test-ADDrinkAttributeEnabled {
    [CmdletBinding()]
    param(
        [string]$Server,

        [switch]$PassThru
    )

    Initialize-DrunkenADModule

    $rootDseParams = @{
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $rootDseParams['Server'] = $Server
    }

    $rootDse = Get-ADRootDSE @rootDseParams
    $attributeParams = @{
        SearchBase = $rootDse.SchemaNamingContext
        LDAPFilter = '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))'
        Properties = @('isDefunct', 'lDAPDisplayName')
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $attributeParams['Server'] = $Server
    }

    $attributeMatches = @(Get-ADObject @attributeParams)
    $isEnabled = $false
    $attributeObject = $null

    if ($attributeMatches.Count -gt 1) {
        throw "Multiple schema entries named 'drink' were returned. Aborting because the schema lookup is ambiguous."
    }

    if ($attributeMatches.Count -eq 1) {
        $attributeObject = $attributeMatches[0]
        $isEnabled = -not [bool]$attributeObject.isDefunct
    }

    if ($PassThru) {
        [pscustomobject]@{
            Server            = $Server
            Enabled           = $isEnabled
            IsDefunct         = if ($attributeObject) { [bool]$attributeObject.isDefunct } else { $null }
            DistinguishedName = if ($attributeObject) { $attributeObject.DistinguishedName } else { $null }
        }
        return
    }

    $isEnabled
}

function Assert-ADDrinkAttributeEnabled {
    [CmdletBinding()]
    param(
        [string]$Server
    )

    if (-not (Test-ADDrinkAttributeEnabled -Server $Server)) {
        throw "The 'drink' attribute is not enabled in the target Active Directory schema."
    }
}

function ConvertTo-DrunkenADPrefixMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Prefixes,

        [Parameter(Mandatory = $true)]
        [string[]]$DrinkValues
    )

    if ($Prefixes.Count -gt 1 -and $DrinkValues.Count -gt 1 -and $Prefixes.Count -ne $DrinkValues.Count) {
        throw "When both -Prefixes and -DrinkValues contain multiple values, their counts must match or one side must contain a single item."
    }

    foreach ($prefix in $Prefixes) {
        if ([string]::IsNullOrWhiteSpace($prefix)) {
            throw "Prefix values cannot be null, empty, or whitespace."
        }
    }

    $prefixMap = [ordered]@{}

    if ($Prefixes.Count -eq 1) {
        $prefixMap[$Prefixes[0]] = @($DrinkValues)
        return $prefixMap
    }

    if ($DrinkValues.Count -eq 1) {
        foreach ($prefix in $Prefixes) {
            if ($prefixMap.Contains($prefix)) {
                $prefixMap[$prefix] += @($DrinkValues[0])
            }
            else {
                $prefixMap[$prefix] = @($DrinkValues[0])
            }
        }

        return $prefixMap
    }

    for ($index = 0; $index -lt $Prefixes.Count; $index++) {
        $prefix = $Prefixes[$index]
        if ($prefixMap.Contains($prefix)) {
            $prefixMap[$prefix] += @($DrinkValues[$index])
        }
        else {
            $prefixMap[$prefix] = @($DrinkValues[$index])
        }
    }

    $prefixMap
}

function Merge-DrunkenADAttributeMap {
    [CmdletBinding()]
    param(
        [hashtable]$BaseMap,

        [hashtable]$OverlayMap
    )

    $mergedMap = [ordered]@{}

    foreach ($map in @($BaseMap, $OverlayMap)) {
        if ($null -eq $map) {
            continue
        }

        foreach ($prefixKey in $map.Keys) {
            $prefix = [string]$prefixKey
            if ([string]::IsNullOrWhiteSpace($prefix)) {
                throw "Attribute map prefixes cannot be null, empty, or whitespace."
            }

            $attributeNames = @($map[$prefixKey] | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($attributeNames.Count -eq 0) {
                throw "Attribute map prefix '$prefix' must include at least one attribute name."
            }

            if (-not $mergedMap.Contains($prefix)) {
                $mergedMap[$prefix] = @()
            }

            foreach ($attributeName in $attributeNames) {
                if ($mergedMap[$prefix] -notcontains $attributeName) {
                    $mergedMap[$prefix] += $attributeName
                }
            }
        }
    }

    $mergedMap
}

function Get-DrunkenADDefaultDemoAttributeMap {
    [CmdletBinding()]
    param()

    [ordered]@{
        'Profile-'  = @('samAccountName')
        'Identity-' = @('userPrincipalName')
        'Meta-'     = @('employeeID')
        'Routing-'  = @('mail')
        'Notify-'   = @('pager')
    }
}

function ConvertTo-DrunkenADDemoDataMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$User,

        [Parameter(Mandatory = $true)]
        [hashtable]$AttributeMap
    )

    $dataMap = [ordered]@{}

    foreach ($prefixKey in $AttributeMap.Keys) {
        $prefix = [string]$prefixKey
        $records = @()

        foreach ($attributeName in @($AttributeMap[$prefixKey])) {
            $attributeValues = @($User.$attributeName)

            foreach ($attributeValue in $attributeValues) {
                $stringValue = [string]$attributeValue
                if ([string]::IsNullOrWhiteSpace($stringValue)) {
                    continue
                }

                $record = '{0}={1}' -f $attributeName, $stringValue
                if ($records -notcontains $record) {
                    $records += $record
                }
            }
        }

        if ($records.Count -gt 0) {
            $dataMap[$prefix] = $records
        }
    }

    $dataMap
}

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

.OUTPUTS
System.String[]

.EXAMPLE
Get-ADUserDrinkData -SamAccountName 'TesterAccount' -DomainController 'dc01.contoso.com'

Returns all values currently stored in the user's `drink` attribute.

.EXAMPLE
Get-ADUserDrinkData -SamAccountName 'TesterAccount' -Prefix 'Profile-' -DomainController 'dc01.contoso.com'

Returns only the `drink` values that start with the literal prefix `Profile-`.
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

    $values = @((Resolve-DrunkenADUser @resolveUserParams).drink | Where-Object { $null -ne $_ })

    if ($PSBoundParameters.ContainsKey('Prefix')) {
        $escapedPrefix = [regex]::Escape($Prefix)
        $values = @($values | Where-Object { $_ -match ('^{0}' -f $escapedPrefix) })
    }

    @($values)
}

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

.OUTPUTS
System.String[]

.EXAMPLE
Get-AdUserDrinkPrefixedData -SamAccountName 'TesterAccount' -DrinkValuePrefix 'Demo-' -DomainController 'dc01.contoso.com'

Returns all `drink` values on the user that start with `Demo-`.

.EXAMPLE
Get-AdUserDrinkPrefixedData -UserPrincipalName 'tester@contoso.com' -DrinkValuePrefix 'Profile-'

Returns all `drink` values for that exact UPN whose prefix is `Profile-`.

.NOTES
Compatibility wrapper around `Get-ADUserDrinkData`.
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

    $getParams = @{
        Prefix           = $DrinkValuePrefix
        DomainController = $DomainController
    }

    switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName'    { $getParams['SamAccountName'] = $SamAccountName }
        'UserPrincipalName' { $getParams['UserPrincipalName'] = $UserPrincipalName }
        'EmployeeID'        { $getParams['EmployeeID'] = $EmployeeID }
        'Mail'              { $getParams['Mail'] = $Mail }
        'Pager'             { $getParams['Pager'] = $Pager }
    }

    Get-ADUserDrinkData @getParams
}

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

.EXAMPLE
Set-ADUserDrinkData -SamAccountName 'TesterAccount' -DataMap @{ 'Profile-' = @('Tier=Gold') } -DomainController 'dc01.contoso.com' -Confirm:$false

Stores a generic `Profile-` record in the user's `drink` attribute.

.EXAMPLE
Set-ADUserDrinkData -SamAccountName 'TesterAccount' -DataMap @{ 'Flags-' = @('Enabled', 'Audited') } -WhatIf

Previews a namespace replacement without writing changes.
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

.EXAMPLE
Remove-ADUserDrinkData -SamAccountName 'TesterAccount' -Prefixes 'Profile-', 'Flags-' -DomainController 'dc01.contoso.com' -Confirm:$false

Removes all `Profile-` and `Flags-` records from the user's `drink` attribute.
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

<#
.SYNOPSIS
Runs a demo workload that stores generic namespaced data in the `drink` attribute.

.DESCRIPTION
Builds a `DataMap` from selected user attributes and writes that data into the
multivalued `drink` attribute using the generic data-store API. By default, the
demo uses the same core identity-related attributes that the example script
already exercises. You can replace that default set with your own `AttributeMap`,
or merge your custom map into the default demo set.

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
Merges the supplied `AttributeMap` into the built-in default demo map instead of
replacing it.

.PARAMETER DomainController
Optional domain controller to use consistently for lookup and write operations.

.PARAMETER LogPath
Optional log file path for appended activity records.

.PARAMETER PassThru
Returns a summary object containing the effective attribute map, the generated
data map, and the final `drink` values after the demo write.

.EXAMPLE
Invoke-ADUserDrinkDataDemo -SamAccountName 'TesterAccount' -DomainController 'dc01.contoso.com' -Confirm:$false

Runs the built-in demo against the target user.

.EXAMPLE
$demoParams = @{
    SamAccountName = 'TesterAccount'
    DomainController = 'dc01.contoso.com'
    AttributeMap = @{
        'Profile-' = @('department', 'title')
        'Flags-'   = @('company')
    }
}
Invoke-ADUserDrinkDataDemo @demoParams -Confirm:$false

Runs the demo with a custom attribute map provided via splatting.

.EXAMPLE
Invoke-ADUserDrinkDataDemo -SamAccountName 'TesterAccount' -AttributeMap @{ 'Custom-' = @('description') } -IncludeDefaultAttributeMap -Confirm:$false

Adds a custom namespace on top of the built-in demo map.
#>
function Invoke-ADUserDrinkDataDemo {
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

    $defaultAttributeMap = Get-DrunkenADDefaultDemoAttributeMap
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
    $dataMap = ConvertTo-DrunkenADDemoDataMap -User $user -AttributeMap $effectiveAttributeMap

    if ($dataMap.Count -eq 0) {
        Write-Verbose "No populated demo data was found for $($user.SamAccountName)."
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

    if ($PSCmdlet.ShouldProcess($user.SamAccountName, 'Run drink data demo')) {
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

.OUTPUTS
System.String[]

.EXAMPLE
Set-ADUserDrinkPrefixedData -SamAccountName 'TesterAccount' -PrefixMap @{ 'Demo-' = @('One') } -DomainController 'dc01.contoso.com' -Confirm:$false

Replaces the user's `Demo-` values with `Demo-One`.

.EXAMPLE
Set-ADUserDrinkPrefixedData -UserPrincipalName 'tester@contoso.com' -PrefixMap @{ 'Demo[01]-' = @('Second') } -WhatIf

Shows what would change for a literal prefix containing regex metacharacters.

.NOTES
Lower-level prefixed API retained for compatibility. `Set-ADUserDrinkData` is the
preferred higher-level name when treating the attribute as a generic data store.
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

    Assert-ADDrinkAttributeEnabled -Server $DomainController

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
    $currentDrinks = @($user.drink | Where-Object { $null -ne $_ })
    $updatedDrinks = @($currentDrinks)

    foreach ($prefixKey in $PrefixMap.Keys) {
        $prefix = [string]$prefixKey
        if ([string]::IsNullOrWhiteSpace($prefix)) {
            throw "Prefix values cannot be null, empty, or whitespace."
        }

        $escapedPrefix = [regex]::Escape($prefix)
        $updatedDrinks = @($updatedDrinks | Where-Object { $_ -notmatch ('^{0}' -f $escapedPrefix) })

        $rawValues = @($PrefixMap[$prefixKey] | Where-Object { $null -ne $_ })
        $prefixedValues = @()

        foreach ($rawValue in $rawValues) {
            $stringValue = [string]$rawValue
            if ([string]::IsNullOrWhiteSpace($stringValue)) {
                continue
            }

            $prefixedValue = '{0}{1}' -f $prefix, $stringValue
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

    $currentFingerprint = @($currentDrinks | Sort-Object) -join "`n"
    $updatedFingerprint = @($updatedDrinks | Sort-Object) -join "`n"

    if ($currentFingerprint -eq $updatedFingerprint) {
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
            $setUserParams['Replace'] = @{ drink = @($updatedDrinks) }
        }

        Set-ADUser @setUserParams
        Write-Verbose "Updated drink attribute for $($user.SamAccountName)."
        Write-DrunkenADLog -LogPath $effectiveLogPath -Message "Updated drink attribute for $($user.SamAccountName) to: $($updatedDrinks -join ', ')"
    }

    if ($PassThru) {
        @($updatedDrinks)
    }
}

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
Update-ADUserDrinkAttribute -SamAccountName 'TesterAccount' -Prefixes 'Demo-' -DrinkValues 'One' -AutoConfirm

Replaces the `Demo-` slice of the `drink` attribute with a single value.

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

    if ($PSCmdlet.ShouldProcess($identityDescription, 'Update drink attribute')) {
        Set-ADUserDrinkPrefixedData @setParams
    }
}

Export-ModuleMember -Function @(
    'Get-ADUserDrinkData',
    'Set-ADUserDrinkData',
    'Remove-ADUserDrinkData',
    'Invoke-ADUserDrinkDataDemo',
    'Get-AdUserDrinkPrefixedData',
    'Set-ADUserDrinkPrefixedData',
    'Test-ADDrinkAttributeEnabled',
    'Update-ADUserDrinkAttribute'
)
