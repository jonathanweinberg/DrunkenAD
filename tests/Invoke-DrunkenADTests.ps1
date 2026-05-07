[CmdletBinding()]
param(
    [switch]$IncludeIntegration,

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed',

    [string]$TestResultPath
)

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

$configuration = New-PesterConfiguration
$configuration.Run.Path = $PSScriptRoot
$configuration.Output.Verbosity = $Output

if (-not $IncludeIntegration) {
    $configuration.Filter.ExcludeTag = @('Integration')
}

if ($TestResultPath) {
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = $TestResultPath
    $configuration.TestResult.OutputFormat = 'NUnitXml'
}

Invoke-Pester -Configuration $configuration
