<#
.SYNOPSIS
Imports namespaced `drink` data for one or more users from a CSV source.

.DESCRIPTION
Reads a CSV file, converts selected columns into namespace records using either
an in-memory `NamespaceMap` or a JSON config file, validates the required
columns, and writes the resulting data maps into each user's `drink` attribute.
Each row must include `SamAccountName`. All usable rows are resolved and length
validated before the first write. A runtime write failure stops processing;
the error TargetObject contains completed, failed, and pending row counts.

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
row with the resolved namespaces, data map, and computed values, including
previews. Computed values are based on preflight reads, not a fresh read-back.

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

    $context = New-DrunkenADWriteContext -Server $DomainController
    $preparedRows = New-Object 'System.Collections.Generic.List[object]'
    $rowNumber = 1
    foreach ($row in $rows) {
        $rowNumber++
        if ([string]::IsNullOrWhiteSpace($row.SamAccountName)) {
            Write-Warning "Skipping CSV row $rowNumber because it has no SamAccountName."
            continue
        }
        $samAccountName = ([string]$row.SamAccountName).Trim()
        $dataMap = ConvertTo-DrunkenADCsvDataMap -Row $row -Mappings $mappings
        if ($dataMap.Count -eq 0) {
            Write-Warning "Skipping CSV row $rowNumber because it has no drink data."
            continue
        }

        # Resolve and validate the entire input before the first directory write.
        $user = Resolve-DrunkenADUser -SamAccountName $samAccountName -Server $context.Server -Properties @('drink')
        $plan = Get-DrunkenADPrefixWritePlan -CurrentValues $user.drink -PrefixMap $dataMap -RangeUpper $context.RangeUpper
        $preparedRows.Add([pscustomobject]@{ RowNumber = $rowNumber; User = $user; DataMap = $dataMap; Plan = $plan })
    }

    $completedCount = 0
    foreach ($prepared in $preparedRows) {
        $writeParams = @{
            User = $prepared.User
            PrefixMap = $prepared.DataMap
            Context = $context
            LogPath = $LogPath
            PassThru = $true
            Confirm = $false
        }
        try {
            $hasChanges = $prepared.Plan.Remove.Count -gt 0 -or $prepared.Plan.Add.Count -gt 0
            # Keep Yes/No to All state in this command's scope across rows.
            if (-not $hasChanges -or $PSCmdlet.ShouldProcess($prepared.User.SamAccountName, 'Write CSV drink data')) {
                $finalDrinkValues = @(Invoke-DrunkenADPrefixWrite @writeParams)
            }
            else {
                $finalDrinkValues = @($prepared.Plan.FinalDrinkValues)
            }
        }
        catch {
            $progress = [pscustomobject]@{
                CompletedRowCount = $completedCount
                FailedRowNumber = $prepared.RowNumber
                PendingRowCount = $preparedRows.Count - $completedCount - 1
                PreparedRowCount = $preparedRows.Count
            }
            $exception = New-Object System.InvalidOperationException(
                "CSV import stopped at row $($prepared.RowNumber) after $completedCount completed row(s). Inspect the error TargetObject for progress; earlier writes are not rolled back.",
                $_.Exception
            )
            $errorRecord = New-Object System.Management.Automation.ErrorRecord(
                $exception, 'DrunkenADCsvWriteFailed',
                [System.Management.Automation.ErrorCategory]::WriteError, $progress
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        $completedCount++
        [pscustomobject]@{
            SamAccountName = $prepared.User.SamAccountName
            ConfigSource = if ($PSCmdlet.ParameterSetName -eq 'NamespaceMap') { 'NamespaceMap' } else { $ConfigPath }
            Namespaces = @($prepared.DataMap.Keys)
            DataMap = $prepared.DataMap
            FinalDrinkValues = $finalDrinkValues
        }
    }
}
