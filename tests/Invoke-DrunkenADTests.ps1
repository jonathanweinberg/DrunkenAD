[CmdletBinding()]
param(
    [switch]$IncludeIntegration,

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed',

    [string]$TestResultPath
)

function Add-DrunkenADLocalPesterCache {
    [CmdletBinding()]
    param()

    if (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0' }) {
        return
    }

    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    $cacheRoot = Join-Path -Path $projectRoot -ChildPath 'tests/Live/results'
    if (-not (Test-Path -LiteralPath $cacheRoot)) {
        return
    }

    $candidate = Get-ChildItem -LiteralPath $cacheRoot -Directory |
        ForEach-Object { Join-Path -Path $_.FullName -ChildPath 'Modules' } |
        Where-Object { Test-Path -LiteralPath (Join-Path -Path $_ -ChildPath 'Pester') } |
        Sort-Object -Descending |
        Select-Object -First 1

    if ($candidate) {
        $env:PSModulePath = '{0}{1}{2}' -f $candidate, [System.IO.Path]::PathSeparator, $env:PSModulePath
    }
}

Add-DrunkenADLocalPesterCache
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

$configuration = New-PesterConfiguration
$configuration.Run.Path = $PSScriptRoot
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = $Output

if (-not $IncludeIntegration) {
    $configuration.Filter.ExcludeTag = @('Integration')
}

if ($TestResultPath) {
    $configuration.TestResult.Enabled = $true
    $configuration.TestResult.OutputPath = $TestResultPath
    $configuration.TestResult.OutputFormat = 'NUnitXml'
}

$result = Invoke-Pester -Configuration $configuration

if ($result.FailedCount -gt 0) {
    throw "Pester completed with $($result.FailedCount) failing test(s)."
}
