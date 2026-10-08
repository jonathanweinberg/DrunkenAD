<#
.SYNOPSIS
Imports namespaced `drink` data for one or more users from a CSV source.

.DESCRIPTION
Reads a CSV file, converts selected columns into namespace records using either
an in-memory `NamespaceMap` or a JSON config file, validates the required
columns, and writes the resulting data maps into each user's `drink` attribute.
Blank cells contribute no records. Every mapped namespace is replaced; a
namespace whose mapped columns are all blank is cleared.
Each row must include `SamAccountName`. All usable rows are resolved and length
validated before the first write. A runtime write failure stops processing;
the error TargetObject contains processed, written, outcome, and pending counts.
CompletedRowCount counts processed rows, including declined and previewed rows.

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
previews, and Status (Written, NoChange, Declined, or WhatIf). Approved writes
refresh the resolved identity on the pinned controller after confirmation.
Computed values are not a post-write read-back; declined previews use preflight.

.EXAMPLE
Import-ADUserDrinkCsvData -CsvPath '.\users.csv' -ConfigPath '.\drink-config.json' -DomainController 'dc01.contoso.com'

Imports `drink` data using a JSON-backed namespace map.

.EXAMPLE
$namespaceMap = @{
    'CsvProfile-' = @(
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

        # Resolve and validate the entire input before the first directory write.
        $user = Resolve-DrunkenADUser -SamAccountName $samAccountName -Server $context.Server -Properties @('drink')
        $plan = Get-DrunkenADPrefixWritePlan -CurrentValues $user.drink -PrefixMap $dataMap -RangeUpper $context.RangeUpper
        $preparedRows.Add([pscustomobject]@{ RowNumber = $rowNumber; User = $user; DataMap = $dataMap; Plan = $plan })
    }

    $completedCount = 0
    $counts = @{ Written = 0; NoChange = 0; Declined = 0; WhatIf = 0 }
    foreach ($prepared in $preparedRows) {
        $writeParams = @{
            User = $prepared.User
            PrefixMap = $prepared.DataMap
            Context = $context
            LogPath = $LogPath
            PassThru = $true
            ResultObject = $true
            Confirm = $false
        }
        try {
            $resolvedIdentity = $prepared.User.DistinguishedName
            if ($prepared.User.PSObject.Properties['ObjectGUID'] -and $prepared.User.ObjectGUID) {
                $resolvedIdentity = $prepared.User.ObjectGUID
            }
            $hasChanges = $prepared.Plan.Remove.Count -gt 0 -or $prepared.Plan.Add.Count -gt 0
            if (-not $hasChanges) {
                $freshUser = Get-ADUser -Identity $resolvedIdentity -Server $context.Server -Properties @('drink') -ErrorAction Stop
                if ($null -eq $freshUser) { throw 'The resolved CSV user could not be refreshed.' }
                $freshPlan = Get-DrunkenADPrefixWritePlan -CurrentValues $freshUser.drink -PrefixMap $prepared.DataMap -RangeUpper $context.RangeUpper
                $hasChanges = $freshPlan.Remove.Count -gt 0 -or $freshPlan.Add.Count -gt 0
                $prepared.Plan = $freshPlan
                $writeParams.User = $freshUser
            }
            # Keep Yes/No to All state in this command's scope across rows.
            $reason = [System.Management.Automation.ShouldProcessReason]::None
            $description = "Write CSV drink data for $($prepared.User.SamAccountName): remove $($prepared.Plan.Remove.Count), add $($prepared.Plan.Add.Count) value(s)"
            if (-not $hasChanges -or $PSCmdlet.ShouldProcess($description, $description + '?', 'Confirm CSV drink write', [ref]$reason)) {
                if ($hasChanges) {
                    $writeParams.User = Get-ADUser -Identity $resolvedIdentity -Server $context.Server -Properties @('drink') -ErrorAction Stop
                }
                if ($null -eq $writeParams.User) { throw 'The resolved CSV user could not be refreshed.' }
                $writeResult = Invoke-DrunkenADPrefixWrite @writeParams
                $status = $writeResult.Status
                $finalDrinkValues = @($writeResult.FinalDrinkValues)
            }
            else {
                $status = if ($reason -eq [System.Management.Automation.ShouldProcessReason]::WhatIf) { 'WhatIf' } else { 'Declined' }
                $finalDrinkValues = @($prepared.Plan.FinalDrinkValues)
            }
        }
        catch {
            $progress = [pscustomobject]@{
                CompletedRowCount = $completedCount
                FailedRowNumber = $prepared.RowNumber
                PendingRowCount = $preparedRows.Count - $completedCount - 1
                PreparedRowCount = $preparedRows.Count
                WrittenRowCount = $counts.Written
                NoChangeRowCount = $counts.NoChange
                DeclinedRowCount = $counts.Declined
                WhatIfRowCount = $counts.WhatIf
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
        $counts[$status]++
        [pscustomobject]@{
            SamAccountName = $prepared.User.SamAccountName
            ConfigSource = if ($PSCmdlet.ParameterSetName -eq 'NamespaceMap') { 'NamespaceMap' } else { $ConfigPath }
            Namespaces = @($prepared.DataMap.Keys)
            DataMap = $prepared.DataMap
            FinalDrinkValues = $finalDrinkValues
            Status = $status
        }
    }
}
