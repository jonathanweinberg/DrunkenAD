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
                $matches = @(Get-ADObject @query -LDAPFilter ('(&(objectClass=classSchema){0})' -f $identifierFilter) -Properties $Context.Properties)
                if ($matches.Count -eq 0) {
                    throw "Schema class reference '$reference' could not be resolved from the target schema."
                }
                if ($matches.Count -gt 1) {
                    throw "Schema class reference '$reference' is ambiguous; multiple schema entries were returned."
                }

                $Context.Classes[$reference] = $matches[0]
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
    if ([string]::IsNullOrWhiteSpace($Server)) {
        $Server = [string](Get-DrunkenADSchemaPropertyValue -InputObject $rootDse -Name 'dnsHostName')
        if ([string]::IsNullOrWhiteSpace($Server)) {
            throw 'RootDSE did not return dnsHostName; schema queries cannot be pinned to a domain controller.'
        }
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
    $userClassMatches = @(Get-ADObject @commonSchemaParams -LDAPFilter '(&(objectClass=classSchema)(lDAPDisplayName=user))' -Properties $classProperties)
    if ($userClassMatches.Count -gt 1) {
        throw "Multiple schema entries for the Active Directory user class were returned. Aborting because the schema lookup is ambiguous."
    }

    if ($userClassMatches.Count -eq 0) {
        throw 'The Active Directory user class could not be resolved from the target schema.'
    }

    $attributeObject = if ($attributeMatches.Count -eq 1) { $attributeMatches[0] } else { $null }
    $userClassObject = $userClassMatches[0]
    $attributePresent = $null -ne $attributeObject
    $isDefunct = if ($attributePresent) { [bool](Get-DrunkenADSchemaPropertyValue -InputObject $attributeObject -Name 'isDefunct') } else { $null }
    $isEnabled = $attributePresent -and (-not $isDefunct)
    $allowedOnUserClass = $false
    $attributeDn = Get-DrunkenADSchemaPropertyValue -InputObject $attributeObject -Name 'distinguishedName'
    $rangeUpper = $null
    $rangeValues = @(Get-DrunkenADSchemaPropertyValue -InputObject $attributeObject -Name 'rangeUpper')
    if ($rangeValues.Count -gt 0) {
        $parsedRangeUpper = 0
        if ($rangeValues.Count -ne 1 -or
            -not [int]::TryParse([string]$rangeValues[0], [ref]$parsedRangeUpper) -or $parsedRangeUpper -lt 0) {
            throw "The 'drink' schema attribute has invalid rangeUpper metadata."
        }

        $rangeUpper = $parsedRangeUpper
    }

    if ($isEnabled) {
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
    elseif (-not $allowedOnUserClass) {
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
        ReadyForUserWrite        = ($isEnabled -and $allowedOnUserClass)
        BlockingReason           = $blockingReason
        BlockingMessage          = $blockingMessage
    }
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
