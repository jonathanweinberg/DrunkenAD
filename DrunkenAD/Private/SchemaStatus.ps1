function Get-DrunkenADSchemaPropertyValue {
    param(
        $InputObject,
        [string]$Name
    )

    if ($null -ne $InputObject) {
        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $property -and $null -ne $property.Value) {
            $property.Value
        }
    }
}

function Test-DrunkenADSchemaClassAllowsAttribute {
    param(
        $ClassObject,
        [System.Collections.Generic.HashSet[string]]$AttributeIdentifiers,
        [hashtable]$Context
    )

    $classDn = [string](Get-DrunkenADSchemaPropertyValue -InputObject $ClassObject -Name 'distinguishedName')
    if ([string]::IsNullOrWhiteSpace($classDn)) {
        throw 'A schema class has no distinguished name; its inheritance cannot be validated safely.'
    }

    if ($Context.Visiting.Contains($classDn)) {
        throw "A cycle was found in the schema class inheritance graph at '$classDn'."
    }

    if ($Context.Results.ContainsKey($classDn)) {
        return $Context.Results[$classDn]
    }

    [void]$Context.Visiting.Add($classDn)
    $allowed = $false
    foreach ($propertyName in @('mayContain', 'systemMayContain', 'mustContain', 'systemMustContain')) {
        foreach ($attributeReference in @(Get-DrunkenADSchemaPropertyValue -InputObject $ClassObject -Name $propertyName)) {
            if ($AttributeIdentifiers.Contains([string]$attributeReference)) {
                $allowed = $true
            }
        }
    }

    # Validate every reachable edge, even after finding the attribute on one class.
    foreach ($propertyName in @('subClassOf', 'auxiliaryClass', 'systemAuxiliaryClass')) {
        $references = @(Get-DrunkenADSchemaPropertyValue -InputObject $ClassObject -Name $propertyName)
        if ($propertyName -eq 'subClassOf' -and $references.Count -gt 1) {
            throw "Schema class '$classDn' has multiple subClassOf values; inheritance is ambiguous."
        }

        foreach ($referenceValue in $references) {
            $reference = [string]$referenceValue
            if ([string]::IsNullOrWhiteSpace($reference)) {
                throw "Schema class '$classDn' has an empty '$propertyName' reference."
            }

            if (-not $Context.Classes.ContainsKey($reference)) {
                $escapedReference = ConvertTo-DrunkenADLdapFilterValue -Value $reference
                $identifierFilter = if ($reference.Contains('=')) {
                    '(distinguishedName={0})' -f $escapedReference
                }
                elseif ($reference -match '^\d+(\.\d+)+$') {
                    '(governsID={0})' -f $escapedReference
                }
                else {
                    '(|(lDAPDisplayName={0})(cn={0}))' -f $escapedReference
                }

                $query = $Context.Query
                $classMatches = @(Get-ADObject @query -LDAPFilter ('(&(objectClass=classSchema){0})' -f $identifierFilter) -Properties $Context.Properties)
                if ($classMatches.Count -eq 0) {
                    throw "Schema class reference '$reference' could not be resolved from the target schema."
                }
                if ($classMatches.Count -gt 1) {
                    throw "Schema class reference '$reference' is ambiguous; multiple schema entries were returned."
                }

                $Context.Classes[$reference] = $classMatches[0]
            }

            $relatedClass = $Context.Classes[$reference]
            $relatedDn = [string](Get-DrunkenADSchemaPropertyValue -InputObject $relatedClass -Name 'distinguishedName')
            $className = [string](Get-DrunkenADSchemaPropertyValue -InputObject $ClassObject -Name 'lDAPDisplayName')
            # AD defines top.subClassOf = top. No other self-edge is a valid terminator.
            if ($propertyName -eq 'subClassOf' -and $className -eq 'top' -and
                [string]::Equals($classDn, $relatedDn, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $relatedAllowed = Test-DrunkenADSchemaClassAllowsAttribute -ClassObject $relatedClass -AttributeIdentifiers $AttributeIdentifiers -Context $Context
            $allowed = $allowed -or $relatedAllowed
        }
    }

    [void]$Context.Visiting.Remove($classDn)
    $Context.Results[$classDn] = $allowed
    return $allowed
}

function Get-DrunkenADDrinkAttributeStatus {
    [CmdletBinding()]
    param(
        [string]$Server,
        [switch]$PresenceOnly
    )

    Initialize-DrunkenADModule

    $rootDseParams = @{
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $rootDseParams['Server'] = $Server
    }

    $explicitPort = $null
    $endpointHost = $Server
    $parsedAddress = $null
    $isBareIPv6 = -not $Server.StartsWith('[') -and [System.Net.IPAddress]::TryParse($Server, [ref]$parsedAddress) -and
        $parsedAddress.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6
    if (-not [string]::IsNullOrWhiteSpace($Server) -and $Server.Contains(':') -and -not $isBareIPv6) {
        $endpointMatch = [regex]::Match($Server, '^(?:([^:\[\]\s]+):([0-9]+)|\[([^\]\s]+)\](?::([0-9]+))?)$')
        $portNumber = 0
        if (-not $endpointMatch.Success) {
            throw 'Server must specify a hostname and a valid port between 1 and 65535.'
        }
        if ($endpointMatch.Groups[3].Success) {
            $endpointHost = $endpointMatch.Groups[3].Value
            if (-not [System.Net.IPAddress]::TryParse($endpointHost, [ref]$parsedAddress) -or
                $parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                throw 'A bracketed Server address must be a valid IPv6 address.'
            }
            $explicitPort = $endpointMatch.Groups[4].Value
        }
        else {
            $endpointHost = $endpointMatch.Groups[1].Value
            $explicitPort = $endpointMatch.Groups[2].Value
        }
        if ($explicitPort -ne '' -and
            (-not [int]::TryParse($explicitPort, [ref]$portNumber) -or $portNumber -lt 1 -or $portNumber -gt 65535)) {
            throw 'Server must specify a hostname and a valid port between 1 and 65535.'
        }
    }

    $rootDse = Get-ADRootDSE @rootDseParams
    # Compare a DNS candidate's DN to authoritative domain metadata, never a hostname suffix.
    $defaultNamingContext = [string](Get-DrunkenADSchemaPropertyValue -InputObject $rootDse -Name 'defaultNamingContext')
    $isDomainEndpoint = $false
    if (-not [System.Net.IPAddress]::TryParse($endpointHost, [ref]$parsedAddress) -and
        $endpointHost -match '^(?i:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(?:\.(?i:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?))*\.?$') {
        $candidateDomainDn = ($endpointHost.TrimEnd('.').Split('.') | ForEach-Object { 'DC={0}' -f $_ }) -join ','
        $isDomainEndpoint = [string]::Equals($candidateDomainDn, $defaultNamingContext, [System.StringComparison]::OrdinalIgnoreCase)
    }
    if ([string]::IsNullOrWhiteSpace($Server) -or $isDomainEndpoint) {
        $Server = [string](Get-DrunkenADSchemaPropertyValue -InputObject $rootDse -Name 'dnsHostName')
        if ([string]::IsNullOrWhiteSpace($Server)) {
            throw 'RootDSE did not return dnsHostName; schema queries cannot be pinned to a domain controller.'
        }
        if (-not [string]::IsNullOrEmpty($explicitPort)) { $Server = '{0}:{1}' -f $Server, $explicitPort }
    }

    $schemaNamingContext = [string](Get-DrunkenADSchemaPropertyValue -InputObject $rootDse -Name 'schemaNamingContext')
    if ([string]::IsNullOrWhiteSpace($schemaNamingContext)) {
        throw 'RootDSE did not return the schema naming context.'
    }

    $commonSchemaParams = @{
        SearchBase  = $schemaNamingContext
        ErrorAction = 'Stop'
        Server      = $Server
    }

    $attributeMatches = @(Get-ADObject @commonSchemaParams -LDAPFilter '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))' -Properties @('isDefunct', 'lDAPDisplayName', 'distinguishedName', 'attributeID', 'rangeUpper'))
    if ($attributeMatches.Count -gt 1) {
        throw "Multiple schema entries named 'drink' were returned. Aborting because the schema lookup is ambiguous."
    }

    $classProperties = @('mayContain', 'systemMayContain', 'mustContain', 'systemMustContain', 'subClassOf', 'auxiliaryClass', 'systemAuxiliaryClass', 'lDAPDisplayName', 'distinguishedName', 'governsID')
    $userClassMatches = @()
    if (-not $PresenceOnly) {
        $userClassMatches = @(Get-ADObject @commonSchemaParams -LDAPFilter '(&(objectClass=classSchema)(lDAPDisplayName=user))' -Properties $classProperties)
    }
    if ($userClassMatches.Count -gt 1) {
        throw "Multiple schema entries for the Active Directory user class were returned. Aborting because the schema lookup is ambiguous."
    }

    if (-not $PresenceOnly -and $userClassMatches.Count -eq 0) {
        throw 'The Active Directory user class could not be resolved from the target schema.'
    }

    $attributeObject = if ($attributeMatches.Count -eq 1) { $attributeMatches[0] } else { $null }
    $userClassObject = if ($userClassMatches.Count -eq 1) { $userClassMatches[0] } else { $null }
    $attributePresent = $null -ne $attributeObject
    $isDefunct = if ($attributePresent) { [bool](Get-DrunkenADSchemaPropertyValue -InputObject $attributeObject -Name 'isDefunct') } else { $null }
    $isEnabled = $attributePresent -and (-not $isDefunct)
    $allowedOnUserClass = if ($PresenceOnly) { $null } else { $false }
    $attributeDn = Get-DrunkenADSchemaPropertyValue -InputObject $attributeObject -Name 'distinguishedName'
    $rangeUpper = $null
    $rangeValues = @(Get-DrunkenADSchemaPropertyValue -InputObject $attributeObject -Name 'rangeUpper')
    if (-not $PresenceOnly -and $rangeValues.Count -gt 0) {
        $parsedRangeUpper = 0
        if ($rangeValues.Count -ne 1 -or
            -not [int]::TryParse([string]$rangeValues[0], [ref]$parsedRangeUpper) -or $parsedRangeUpper -lt 0) {
            throw "The 'drink' schema attribute has invalid rangeUpper metadata."
        }

        $rangeUpper = $parsedRangeUpper
    }

    if ($isEnabled -and -not $PresenceOnly) {
        # String(OID) schema references normally use LDAP names; also accept numeric OIDs and DNs.
        $attributeIdentifiers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        [void]$attributeIdentifiers.Add('drink')
        foreach ($propertyName in @('lDAPDisplayName', 'attributeID', 'distinguishedName')) {
            foreach ($identifier in @(Get-DrunkenADSchemaPropertyValue -InputObject $attributeObject -Name $propertyName)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$identifier)) {
                    [void]$attributeIdentifiers.Add([string]$identifier)
                }
            }
        }

        $context = @{
            Query      = $commonSchemaParams
            Properties = $classProperties
            Classes    = @{}
            Results    = @{}
            Visiting   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
        $allowedOnUserClass = Test-DrunkenADSchemaClassAllowsAttribute -ClassObject $userClassObject -AttributeIdentifiers $attributeIdentifiers -Context $context
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
    elseif (-not $PresenceOnly -and -not $allowedOnUserClass) {
        $blockingReason = 'NotAllowedOnUserClass'
        $blockingMessage = "The 'drink' attribute exists in the target Active Directory schema but is not allowed on the Active Directory user class."
    }

    [pscustomobject]@{
        Server                   = $Server
        Enabled                  = $isEnabled
        IsDefunct                = $isDefunct
        DistinguishedName        = $attributeDn
        AttributeDistinguishedName = $attributeDn
        SchemaNamingContext      = $schemaNamingContext
        UserClassDistinguishedName = Get-DrunkenADSchemaPropertyValue -InputObject $userClassObject -Name 'distinguishedName'
        RangeUpper               = $rangeUpper
        AllowedOnUserClass       = $allowedOnUserClass
        ReadyForUserWrite        = if ($PresenceOnly) { $null } else { $isEnabled -and $allowedOnUserClass }
        ReadinessEvaluated       = (-not $PresenceOnly)
        BlockingReason           = $blockingReason
        BlockingMessage          = $blockingMessage
    }
}

function Assert-ADDrinkAttributeEnabled {
    [CmdletBinding()]
    param(
        [string]$Server,
        [switch]$PassThru
    )

    $status = Get-DrunkenADDrinkAttributeStatus -Server $Server -PresenceOnly

    if (-not $status.Enabled) {
        throw "The 'drink' attribute is not enabled in the target Active Directory schema."
    }
    if ($PassThru) { $status }
}
