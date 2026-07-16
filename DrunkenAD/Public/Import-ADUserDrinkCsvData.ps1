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

.INPUTS
None. CSV rows are read from `CsvPath`.

.OUTPUTS
System.Management.Automation.PSCustomObject. Returns one object per imported
row with the resolved namespaces, data map, and final values when a write occurs.

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

.LINK
about_DrunkenAD

.LINK
Split-DrunkenADCsvField

.LINK
Set-ADUserDrinkData

.COMPONENT
DrunkenAD

.ROLE
Operator

.FUNCTIONALITY
Import CSV rows into Active Directory drink namespaces
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
    Assert-DrunkenADCsvIdentities -Rows $rows

    Assert-ADDrinkAttributeReadyForUserWrite -Server $DomainController

    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace($row.SamAccountName)) {
            Write-Warning "Skipping a row with no SamAccountName in '$CsvPath'."
            continue
        }

        $samAccountName = ([string]$row.SamAccountName).Trim()

        $dataMap = ConvertTo-DrunkenADCsvDataMap -Row $row -Mappings $mappings

        if ($dataMap.Count -eq 0) {
            Write-Warning "Skipping '$samAccountName' because the row did not contain any drink data."
            continue
        }

        $finalDrinkValues = @()
        if ($PSCmdlet.ShouldProcess($samAccountName, 'Import drink data from CSV')) {
            $finalDrinkValues = @(Set-ADUserDrinkData -SamAccountName $samAccountName -DataMap $dataMap -DomainController $DomainController -LogPath $LogPath -Confirm:$false -PassThru)
        }

        [pscustomobject]@{
            SamAccountName   = $samAccountName
            ConfigSource     = if ($PSCmdlet.ParameterSetName -eq 'NamespaceMap') { 'NamespaceMap' } else { $ConfigPath }
            Namespaces       = @($dataMap.Keys)
            DataMap          = $dataMap
            FinalDrinkValues = $finalDrinkValues
        }
    }
}
