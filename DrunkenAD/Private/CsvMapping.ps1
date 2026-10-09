function Read-DrunkenADCsvRows {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$CsvPath)

    $path = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath)
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $codePage = 65001
    $offset = 0
    # Recognize the same Unicode BOMs as Get-Content, but retain strict decoding
    # after detection. UTF-32 LE must precede its shared UTF-16 LE prefix.
    if ($bytes.Length -ge 4 -and $bytes[0] -eq 0xff -and $bytes[1] -eq 0xfe -and $bytes[2] -eq 0 -and $bytes[3] -eq 0) {
        $codePage = 12000; $offset = 4
    }
    elseif ($bytes.Length -ge 4 -and $bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 0xfe -and $bytes[3] -eq 0xff) {
        $codePage = 12001; $offset = 4
    }
    elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
        $offset = 3
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xff -and $bytes[1] -eq 0xfe) {
        $codePage = 1200; $offset = 2
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xfe -and $bytes[1] -eq 0xff) {
        $codePage = 1201; $offset = 2
    }
    $encoding = [System.Text.Encoding]::GetEncoding($codePage, [System.Text.EncoderFallback]::ExceptionFallback, [System.Text.DecoderFallback]::ExceptionFallback)
    try { $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset) }
    catch [System.Text.DecoderFallbackException] {
        throw 'CSV encoding is invalid. Export the source as CSV UTF-8 and retry. UTF-16 and UTF-32 require a matching byte-order mark; malformed Unicode is not accepted.'
    }
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    # Import-Csv conflates missing fields with unquoted empty cells. Validate
    # record shape with the framework parser, using the same input snapshot.
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
    $parser = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new([System.IO.StringReader]::new($text))
    try {
        $parser.SetDelimiters(',')
        $parser.HasFieldsEnclosedInQuotes = $true
        $parser.TrimWhiteSpace = $false
        $parser.CommentTokens = @('#')
        if ($parser.EndOfData) { return }
        $header = $parser.ReadFields()
        $parser.CommentTokens = @()
        $record = 1
        while (-not $parser.EndOfData) {
            $record++
            $fields = $parser.ReadFields()
            if ($fields.Count -ne $header.Count) {
                throw "CSV record $record has $($fields.Count) fields; the header requires $($header.Count). Supply every field, using an empty cell when appropriate."
            }
        }
        $rows = @(ConvertFrom-Csv -InputObject $text -ErrorAction Stop)
        if ($rows.Count -ne ($record - 1)) {
            throw 'CSV records could not be validated consistently. Use a standard comma-delimited header and data records.'
        }
        $rows
    }
    finally { $parser.Dispose() }
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

function ConvertTo-DrunkenADHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
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

        return ,$items
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

    Assert-DrunkenADNonOverlappingPrefixes -Prefixes @($NamespaceMap.Keys | ForEach-Object { [string]$_ })

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

function Assert-DrunkenADCsvIdentities {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    $seenIdentities = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Rows) {
        $identity = [string]$row.SamAccountName
        if ([string]::IsNullOrWhiteSpace($identity)) {
            continue
        }

        $identity = $identity.Trim()
        if (-not $seenIdentities.Add($identity)) {
            throw "CSV contains duplicate SamAccountName '$identity'."
        }
    }
}

function ConvertTo-DrunkenADCsvDataMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Row,

        [Parameter(Mandatory = $true)]
        [object[]]$Mappings,

        [switch]$ClearBlankNamespaces
    )

    $dataMap = @{}

    foreach ($mapping in $Mappings) {
        if ($ClearBlankNamespaces -and -not $dataMap.ContainsKey($mapping.Prefix)) { $dataMap[$mapping.Prefix] = @() }
        $columnValue = [string]$Row.($mapping.Column)
        $fieldValues = if ([string]::IsNullOrWhiteSpace($mapping.SplitOn)) {
            @($columnValue)
        }
        else {
            @(Split-DrunkenADCsvField -Value $columnValue -Delimiter $mapping.SplitOn)
        }

        foreach ($fieldValue in $fieldValues) {
            if ([string]::IsNullOrWhiteSpace([string]$fieldValue)) {
                continue
            }

            $normalizedFieldValue = ([string]$fieldValue).Trim()
            $recordValue = if ([string]::IsNullOrWhiteSpace($mapping.Label)) {
                $normalizedFieldValue
            }
            else {
                '{0}={1}' -f $mapping.Label, $normalizedFieldValue
            }

            Add-DrunkenADCsvRecord -DataMap $dataMap -Prefix $mapping.Prefix -Value $recordValue
        }
    }

    $dataMap
}
