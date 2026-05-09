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
