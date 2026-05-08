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

function ConvertTo-DrunkenADStringArray {
    [CmdletBinding()]
    param(
        $Values,

        [switch]$SkipBlank
    )

    $result = New-Object System.Collections.Generic.List[string]

    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }

        $stringValue = [string]$value
        if ($SkipBlank -and [string]::IsNullOrWhiteSpace($stringValue)) {
            continue
        }

        $result.Add($stringValue)
    }

    return ,([string[]]$result.ToArray())
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

function Get-DrunkenADDrinkAttributeStatus {
    [CmdletBinding()]
    param(
        [string]$Server
    )

    Initialize-DrunkenADModule

    $rootDseParams = @{
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $rootDseParams['Server'] = $Server
    }

    $rootDse = Get-ADRootDSE @rootDseParams
    $commonSchemaParams = @{
        SearchBase  = $rootDse.SchemaNamingContext
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $commonSchemaParams['Server'] = $Server
    }

    $attributeMatches = @(Get-ADObject @commonSchemaParams -LDAPFilter '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))' -Properties @('isDefunct', 'lDAPDisplayName', 'distinguishedName'))
    if ($attributeMatches.Count -gt 1) {
        throw "Multiple schema entries named 'drink' were returned. Aborting because the schema lookup is ambiguous."
    }

    $userClassMatches = @(Get-ADObject @commonSchemaParams -LDAPFilter '(&(objectClass=classSchema)(lDAPDisplayName=user))' -Properties @('mayContain', 'systemMayContain', 'lDAPDisplayName', 'distinguishedName'))
    if ($userClassMatches.Count -gt 1) {
        throw "Multiple schema entries for the Active Directory user class were returned. Aborting because the schema lookup is ambiguous."
    }

    if ($userClassMatches.Count -eq 0) {
        throw 'The Active Directory user class could not be resolved from the target schema.'
    }

    $attributeObject = if ($attributeMatches.Count -eq 1) { $attributeMatches[0] } else { $null }
    $userClassObject = $userClassMatches[0]
    $attributePresent = $null -ne $attributeObject
    $isDefunct = if ($attributePresent) { [bool]$attributeObject.isDefunct } else { $null }
    $isEnabled = $attributePresent -and (-not $isDefunct)
    $allowedOnUserClass = $false

    if ($isEnabled) {
        $allowedAttributes = @($userClassObject.mayContain) + @($userClassObject.systemMayContain)
        $allowedOnUserClass = @($allowedAttributes) -contains 'drink'
    }

    $blockingReason = $null
    $blockingMessage = $null

    if (-not $attributePresent) {
        $blockingReason = 'AttributeMissing'
        $blockingMessage = "The 'drink' attribute was not found in the target Active Directory schema."
    }
    elseif ($isDefunct) {
        $blockingReason = 'AttributeDefunct'
        $blockingMessage = "The 'drink' attribute is defunct in the target Active Directory schema."
    }
    elseif (-not $allowedOnUserClass) {
        $blockingReason = 'NotAllowedOnUserClass'
        $blockingMessage = "The 'drink' attribute exists in the target Active Directory schema but is not allowed on the Active Directory user class."
    }

    [pscustomobject]@{
        Server                   = $Server
        Enabled                  = $isEnabled
        IsDefunct                = $isDefunct
        DistinguishedName        = if ($attributePresent) { $attributeObject.DistinguishedName } else { $null }
        AttributeDistinguishedName = if ($attributePresent) { $attributeObject.DistinguishedName } else { $null }
        SchemaNamingContext      = $rootDse.SchemaNamingContext
        UserClassDistinguishedName = $userClassObject.DistinguishedName
        AllowedOnUserClass       = $allowedOnUserClass
        ReadyForUserWrite        = ($isEnabled -and $allowedOnUserClass)
        BlockingReason           = $blockingReason
        BlockingMessage          = $blockingMessage
    }
}

<#
.SYNOPSIS
Tests whether the Active Directory `drink` attribute exists and is not defunct.

.DESCRIPTION
Queries the schema naming context on the target domain controller and verifies
that an attribute with the LDAP display name `drink` exists and is not defunct.
The Boolean result preserves the original meaning of schema presence. Use
`Test-ADDrinkAttributeReadyForUserWrite` when you need to know whether the
attribute is also allowed on the Active Directory `user` class.

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

Returns detailed schema lookup information, including whether `drink` is allowed
on the Active Directory `user` class.
#>
function Test-ADDrinkAttributeEnabled {
    [CmdletBinding()]
    param(
        [string]$Server,

        [switch]$PassThru
    )

    $status = Get-DrunkenADDrinkAttributeStatus -Server $Server

    if ($PassThru) {
        $status
        return
    }

    $status.Enabled
}

<#
.SYNOPSIS
Tests whether the Active Directory `drink` attribute is ready for user writes.

.DESCRIPTION
Queries the schema naming context on the target domain controller and verifies
that the `drink` attribute exists, is not defunct, and is allowed on the
Active Directory `user` class.

.PARAMETER Server
Optional domain controller to query. When omitted, the default AD connection
behavior is used.

.PARAMETER PassThru
Returns a richer object describing both schema presence and write readiness.

.OUTPUTS
System.Boolean
System.Management.Automation.PSCustomObject

.EXAMPLE
Test-ADDrinkAttributeReadyForUserWrite -Server 'dc01.contoso.com'

Returns `$true` only when DrunkenAD can safely write `drink` values to user
objects on the target environment.

.EXAMPLE
Test-ADDrinkAttributeReadyForUserWrite -Server 'dc01.contoso.com' -PassThru

Returns detailed readiness information, including the blocking reason when user
writes are not currently supported.
#>
function Test-ADDrinkAttributeReadyForUserWrite {
    [CmdletBinding()]
    param(
        [string]$Server,

        [switch]$PassThru
    )

    $status = Get-DrunkenADDrinkAttributeStatus -Server $Server

    if ($PassThru) {
        $status
        return
    }

    $status.ReadyForUserWrite
}

function Assert-ADDrinkAttributeEnabled {
    [CmdletBinding()]
    param(
        [string]$Server
    )

    $status = Get-DrunkenADDrinkAttributeStatus -Server $Server

    if (-not $status.Enabled) {
        throw "The 'drink' attribute is not enabled in the target Active Directory schema."
    }
}

function Assert-ADDrinkAttributeReadyForUserWrite {
    [CmdletBinding()]
    param(
        [string]$Server
    )

    $status = Get-DrunkenADDrinkAttributeStatus -Server $Server

    if (-not $status.ReadyForUserWrite) {
        throw $status.BlockingMessage
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

function Get-DrunkenADDefaultProjectionAttributeMap {
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

function ConvertTo-DrunkenADProjectionDataMap {
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

function Add-DrunkenADCsvRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$DataMap,

        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $trimmedValue = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedValue)) {
        return
    }

    if (-not $DataMap.Contains($Prefix)) {
        $DataMap[$Prefix] = @()
    }

    if ($DataMap[$Prefix] -notcontains $trimmedValue) {
        $DataMap[$Prefix] += $trimmedValue
    }
}

<#
.SYNOPSIS
Splits a delimited CSV field into clean values for multivalue `drink` ingestion.

.DESCRIPTION
Splits a single CSV column value with a literal delimiter, trims each item, and
removes empty results. This is the same helper used by
`Import-ADUserDrinkCsvData` when a namespace mapping includes `SplitOn`.

The delimiter is escaped before splitting, so characters such as `|`, `.`, `+`,
or `[` are treated as text instead of regular expressions.

.PARAMETER Value
The source CSV field value to split.

.PARAMETER Delimiter
The literal delimiter between values. Defaults to `;`. The delimiter cannot be
empty or whitespace.

.EXAMPLE
Split-DrunkenADCsvField -Value 'Enabled; Audited ; Keep-Stable'

Returns `Enabled`, `Audited`, and `Keep-Stable`.

.EXAMPLE
Split-DrunkenADCsvField -Value 'One|Two||Three' -Delimiter '||'

Splits on the literal `||` delimiter.
#>
function Split-DrunkenADCsvField {
    [CmdletBinding()]
    param(
        [string]$Value,

        [string]$Delimiter = ';'
    )

    if ([string]::IsNullOrWhiteSpace($Delimiter)) {
        throw 'Delimiter cannot be empty or whitespace.'
    }

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    @(
        $Value -split [regex]::Escape($Delimiter) |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function ConvertTo-DrunkenADHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [hashtable]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = ConvertTo-DrunkenADHashtable -InputObject $InputObject[$key]
        }

        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += ,(ConvertTo-DrunkenADHashtable -InputObject $item)
        }

        return $items
    }

    if ($InputObject -is [psobject] -and @($InputObject.PSObject.Properties).Count -gt 0) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-DrunkenADHashtable -InputObject $property.Value
        }

        return $result
    }

    $InputObject
}

function Resolve-DrunkenADCsvNamespaceMap {
    [CmdletBinding(DefaultParameterSetName = 'ConfigPath')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'NamespaceMap')]
        [hashtable]$NamespaceMap,

        [Parameter(Mandatory = $true, ParameterSetName = 'ConfigPath')]
        [string]$ConfigPath
    )

    if ($PSCmdlet.ParameterSetName -eq 'NamespaceMap') {
        if ($NamespaceMap.Count -eq 0) {
            throw 'NamespaceMap cannot be empty when supplied.'
        }

        return $NamespaceMap
    }

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config path '$ConfigPath' was not found."
    }

    $configText = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
    $configObject = ConvertFrom-Json -InputObject $configText -ErrorAction Stop
    ConvertTo-DrunkenADHashtable -InputObject $configObject
}

function Get-DrunkenADCsvMappings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$NamespaceMap
    )

    $mappings = @()

    foreach ($prefix in $NamespaceMap.Keys) {
        if ([string]::IsNullOrWhiteSpace([string]$prefix)) {
            throw 'Namespace map prefixes cannot be null, empty, or whitespace.'
        }

        foreach ($entry in @($NamespaceMap[$prefix])) {
            if ($null -eq $entry) {
                continue
            }

            $normalizedEntry = if ($entry -is [hashtable]) {
                $entry
            }
            else {
                ConvertTo-DrunkenADHashtable -InputObject $entry
            }

            $column = [string]$normalizedEntry['Column']
            if ([string]::IsNullOrWhiteSpace($column)) {
                throw "Namespace map entry for prefix '$prefix' must include a non-empty Column value."
            }

            $mappings += [pscustomobject]@{
                Prefix  = [string]$prefix
                Column  = $column
                Label   = [string]$normalizedEntry['Label']
                SplitOn = [string]$normalizedEntry['SplitOn']
            }
        }
    }

    if ($mappings.Count -eq 0) {
        throw 'Namespace map did not contain any usable mappings.'
    }

    $mappings
}

function Assert-DrunkenADCsvColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,

        [Parameter(Mandatory = $true)]
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [object[]]$Mappings
    )

    if ($Rows.Count -eq 0) {
        return
    }

    $columns = @($Rows[0].PSObject.Properties.Name)
    if ($columns -notcontains 'SamAccountName') {
        throw "CSV file '$CsvPath' is missing required column 'SamAccountName'."
    }

    foreach ($mapping in $Mappings) {
        if ($columns -notcontains $mapping.Column) {
            throw "CSV file '$CsvPath' is missing required column '$($mapping.Column)' for prefix '$($mapping.Prefix)'."
        }
    }
}

function ConvertTo-DrunkenADCsvDataMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Row,

        [Parameter(Mandatory = $true)]
        [object[]]$Mappings
    )

    $dataMap = @{}

    foreach ($mapping in $Mappings) {
        $columnValue = [string]$Row.($mapping.Column)
        $fieldValues = if ([string]::IsNullOrWhiteSpace($mapping.SplitOn)) {
            @($columnValue)
        }
        else {
            @(Split-DrunkenADCsvField -Value $columnValue -Delimiter $mapping.SplitOn)
        }

        foreach ($fieldValue in $fieldValues) {
            $recordValue = if ([string]::IsNullOrWhiteSpace($mapping.Label)) {
                $fieldValue
            }
            else {
                '{0}={1}' -f $mapping.Label, $fieldValue
            }

            Add-DrunkenADCsvRecord -DataMap $dataMap -Prefix $mapping.Prefix -Value $recordValue
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

    $values = ConvertTo-DrunkenADStringArray -Values (Resolve-DrunkenADUser @resolveUserParams).drink -SkipBlank

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
Get-AdUserDrinkPrefixedData -SamAccountName 'TesterAccount' -DrinkValuePrefix 'Profile-' -DomainController 'dc01.contoso.com'

Returns all `drink` values on the user that start with `Profile-`.

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

<#
.SYNOPSIS
Imports namespaced `drink` data for one or more users from a CSV source.

.DESCRIPTION
Reads a CSV file, converts selected columns into namespace records using either
an in-memory `NamespaceMap` or a JSON config file, validates the required
columns, and writes the resulting data maps into each user's `drink` attribute.
Each row must include `SamAccountName`.

.PARAMETER CsvPath
Path to the source CSV file.

.PARAMETER NamespaceMap
Hashtable describing how CSV columns map into `drink` namespace records. Keys
are literal namespace prefixes. Each value is one or more entries with `Column`
and optional `Label` or `SplitOn` fields.

.PARAMETER ConfigPath
Path to a JSON file containing the same namespace map structure used by
`NamespaceMap`.

.PARAMETER DomainController
Optional domain controller to use consistently for validation and writes.

.PARAMETER LogPath
Optional log file path for appended activity records.

.OUTPUTS
System.Management.Automation.PSCustomObject

.EXAMPLE
Import-ADUserDrinkCsvData -CsvPath '.\users.csv' -ConfigPath '.\drink-config.json' -DomainController 'dc01.contoso.com'

Imports `drink` data using a JSON-backed namespace map.

.EXAMPLE
$namespaceMap = @{
    'Profile-' = @(
        @{ Column = 'ProfileTier'; Label = 'Tier' }
        @{ Column = 'ProfileRegion'; Label = 'Region' }
    )
    'Flags-' = @(
        @{ Column = 'Flags'; SplitOn = ';' }
    )
}
Import-ADUserDrinkCsvData -CsvPath '.\users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com' -WhatIf

Previews a CSV import using an in-memory namespace map.
#>
function Import-ADUserDrinkCsvData {
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ConfigPath')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'NamespaceMap')]
        [hashtable]$NamespaceMap,

        [Parameter(Mandatory = $true, ParameterSetName = 'ConfigPath')]
        [string]$ConfigPath,

        [Alias('Server')]
        [string]$DomainController,

        [string]$LogPath
    )

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        throw "CSV path '$CsvPath' was not found."
    }

    Assert-ADDrinkAttributeReadyForUserWrite -Server $DomainController

    $rows = @(Import-Csv -LiteralPath $CsvPath)
    $namespaceParams = @{}

    if ($PSCmdlet.ParameterSetName -eq 'NamespaceMap') {
        $namespaceParams['NamespaceMap'] = $NamespaceMap
    }
    else {
        $namespaceParams['ConfigPath'] = $ConfigPath
    }

    $effectiveNamespaceMap = Resolve-DrunkenADCsvNamespaceMap @namespaceParams
    $mappings = @(Get-DrunkenADCsvMappings -NamespaceMap $effectiveNamespaceMap)

    Assert-DrunkenADCsvColumns -CsvPath $CsvPath -Rows $rows -Mappings $mappings

    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace($row.SamAccountName)) {
            Write-Warning "Skipping a row with no SamAccountName in '$CsvPath'."
            continue
        }

        $dataMap = ConvertTo-DrunkenADCsvDataMap -Row $row -Mappings $mappings

        if ($dataMap.Count -eq 0) {
            Write-Warning "Skipping '$($row.SamAccountName)' because the row did not contain any drink data."
            continue
        }

        $finalDrinkValues = @()
        if ($PSCmdlet.ShouldProcess($row.SamAccountName, 'Import drink data from CSV')) {
            $finalDrinkValues = @(Set-ADUserDrinkData -SamAccountName $row.SamAccountName -DataMap $dataMap -DomainController $DomainController -LogPath $LogPath -Confirm:$false -PassThru)
        }

        [pscustomobject]@{
            SamAccountName   = $row.SamAccountName
            ConfigSource     = if ($PSCmdlet.ParameterSetName -eq 'NamespaceMap') { 'NamespaceMap' } else { $ConfigPath }
            Namespaces       = @($dataMap.Keys)
            DataMap          = $dataMap
            FinalDrinkValues = $finalDrinkValues
        }
    }
}

<#
.SYNOPSIS
Compatibility wrapper for the older projection command name.

.DESCRIPTION
Calls `Set-ADUserDrinkProjection` with the same parameters. Retained for
backward compatibility with earlier scripts and examples.

.NOTES
Prefer `Set-ADUserDrinkProjection` for new usage.
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

    Set-ADUserDrinkProjection @PSBoundParameters
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
Set-ADUserDrinkPrefixedData -SamAccountName 'TesterAccount' -PrefixMap @{ 'Profile-' = @('Tier=Gold') } -DomainController 'dc01.contoso.com' -Confirm:$false

Replaces the user's `Profile-` values with `Profile-Tier=Gold`.

.EXAMPLE
Set-ADUserDrinkPrefixedData -UserPrincipalName 'tester@contoso.com' -PrefixMap @{ 'App[01]-' = @('Second') } -WhatIf

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

        $escapedPrefix = [regex]::Escape($prefix)
        $updatedDrinks = @($updatedDrinks | Where-Object { $_ -notmatch ('^{0}' -f $escapedPrefix) })

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

Export-ModuleMember -Function @(
    'Get-ADUserDrinkData',
    'Set-ADUserDrinkData',
    'Remove-ADUserDrinkData',
    'Set-ADUserDrinkProjection',
    'Import-ADUserDrinkCsvData',
    'Split-DrunkenADCsvField',
    'Invoke-ADUserDrinkDataDemo',
    'Get-AdUserDrinkPrefixedData',
    'Set-ADUserDrinkPrefixedData',
    'Test-ADDrinkAttributeEnabled',
    'Test-ADDrinkAttributeReadyForUserWrite',
    'Update-ADUserDrinkAttribute'
)
