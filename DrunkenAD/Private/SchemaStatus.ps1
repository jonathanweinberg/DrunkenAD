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
