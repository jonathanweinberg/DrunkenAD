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
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [object[]]$Mappings
    )

    if ($Rows.Count -eq 0) {
        throw "CSV file '$CsvPath' does not contain any data rows."
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
