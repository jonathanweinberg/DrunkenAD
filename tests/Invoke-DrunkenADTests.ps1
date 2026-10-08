[CmdletBinding()]
param(
    [switch]$IncludeIntegration,

    [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output = 'Detailed',

    [string]$TestResultPath,

    [string]$PesterManifestPath = $env:DRUNKENAD_PESTER_MANIFEST
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$requiredPesterVersion = [version]'5.7.1'
$projectRoot = Split-Path -Path $PSScriptRoot -Parent
$ignoredResultsRoot = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Live') -ChildPath 'results'

function Test-DrunkenADPathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $trimCharacters = [char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd($trimCharacters)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd($trimCharacters)
    $rootPrefix = '{0}{1}' -f $fullRoot, [System.IO.Path]::DirectorySeparatorChar

    $fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-DrunkenADPesterManifest {
    [CmdletBinding()]
    param(
        [string]$ExplicitManifestPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitManifestPath)) {
        $resolvedManifestPath = (Resolve-Path -LiteralPath $ExplicitManifestPath -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
            throw "Pester manifest '$resolvedManifestPath' is not a file."
        }

        if (Test-DrunkenADPathWithinRoot -Path $resolvedManifestPath -Root $ignoredResultsRoot) {
            throw 'Pester must not be loaded from ignored live-result storage.'
        }

        $manifestData = Import-PowerShellDataFile -LiteralPath $resolvedManifestPath
        if ([version]$manifestData.ModuleVersion -ne $requiredPesterVersion) {
            throw "Pester $requiredPesterVersion is required, but '$resolvedManifestPath' declares version $($manifestData.ModuleVersion)."
        }

        return $resolvedManifestPath
    }

    $installedCandidates = @(
        Get-Module -ListAvailable -Name Pester |
            Where-Object { $_.Version -eq $requiredPesterVersion } |
            Sort-Object Path
    )

    foreach ($candidate in $installedCandidates) {
        if (-not (Test-DrunkenADPathWithinRoot -Path $candidate.Path -Root $ignoredResultsRoot)) {
            return $candidate.Path
        }
    }

    throw "Pester $requiredPesterVersion is required. Install that exact version or set DRUNKENAD_PESTER_MANIFEST to its fully qualified Pester.psd1 path."
}

$resolvedPesterManifest = Resolve-DrunkenADPesterManifest -ExplicitManifestPath $PesterManifestPath
Import-Module -Name $resolvedPesterManifest -RequiredVersion $requiredPesterVersion -Force -ErrorAction Stop
Write-Host ('Pester {0} from {1}' -f $requiredPesterVersion, $resolvedPesterManifest)

$trustedTestNames = @(
    'DrunkenAD.Unit.Tests.ps1'
    'Help.Unit.Tests.ps1'
    'LiveCampaign.Unit.Tests.ps1'
    'Release.Unit.Tests.ps1'
    'SchemaEnablement.Unit.Tests.ps1'
    'SchemaStatus.Unit.Tests.ps1'
    'WriteOperation.Unit.Tests.ps1'
    'DrunkenAD.Integration.Tests.ps1'
)
$trustedTestPaths = @(
    foreach ($trustedTestName in $trustedTestNames) {
        $trustedTestPath = Join-Path -Path $PSScriptRoot -ChildPath $trustedTestName
        if (-not (Test-Path -LiteralPath $trustedTestPath -PathType Leaf)) {
            throw "Trusted test file '$trustedTestPath' was not found."
        }

        $trustedTestPath
    }
)

$configuration = New-PesterConfiguration
$configuration.Run.Path = $trustedTestPaths
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

if ($result.Result -ne 'Passed') {
    throw "Pester result was $($result.Result), with $($result.FailedCount) failing test(s). Inspect discovery and container errors as well as test failures."
}
