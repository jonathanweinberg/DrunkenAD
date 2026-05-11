[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path -Path $projectRoot -ChildPath 'DrunkenAD/DrunkenAD.psd1'
$moduleRoot = Split-Path -Path $manifestPath -Parent
$changelogPath = Join-Path -Path $projectRoot -ChildPath 'CHANGELOG.md'

function Add-DrunkenADLocalPesterCache {
    [CmdletBinding()]
    param()

    if (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0' }) {
        return
    }

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

& (Join-Path -Path $PSScriptRoot -ChildPath 'Test-DrunkenADSyntax.ps1')
& (Join-Path -Path $PSScriptRoot -ChildPath 'Test-DrunkenADDocs.ps1')

$manifest = Test-ModuleManifest -Path $manifestPath
if ($manifest.Version.ToString() -ne '0.11.0') {
    throw "Expected module version 0.11.0 but found $($manifest.Version)."
}

if ($manifest.PrivateData.PSData.ProjectUri -ne 'https://github.com/jonathanweinberg/DrunkenAD') {
    throw 'Manifest ProjectUri must point to the DrunkenAD repository.'
}

if ([string]::IsNullOrWhiteSpace($manifest.PrivateData.PSData.ReleaseNotes) -or $manifest.PrivateData.PSData.ReleaseNotes -notmatch '0\.11\.0') {
    throw 'Manifest ReleaseNotes must describe the 0.11.0 release.'
}

if (-not (Test-Path -LiteralPath $changelogPath -PathType Leaf)) {
    throw 'CHANGELOG.md is required for release readiness.'
}

$changelogContent = Get-Content -LiteralPath $changelogPath -Raw
foreach ($requiredHeading in @('## 0.11.0', '## 0.10.1')) {
    if ($changelogContent -notmatch [regex]::Escape($requiredHeading)) {
        throw "CHANGELOG.md is missing '$requiredHeading'."
    }
}

$module = Import-Module $manifestPath -Force -PassThru -ErrorAction Stop
$manifestExports = @($manifest.ExportedFunctions.Keys | Sort-Object)
$moduleExports = @(Get-Command -Module $module.Name -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
$exportDifferences = @(Compare-Object -ReferenceObject $manifestExports -DifferenceObject $moduleExports)
if ($exportDifferences.Count -gt 0) {
    throw 'Manifest exports and imported module exports do not match.'
}

foreach ($requiredDirectory in @('Private', 'Public')) {
    if (-not (Test-Path -LiteralPath (Join-Path -Path $moduleRoot -ChildPath $requiredDirectory) -PathType Container)) {
        throw "Module source directory '$requiredDirectory' was not found."
    }
}

Add-DrunkenADLocalPesterCache
& (Join-Path -Path $projectRoot -ChildPath 'tests/Invoke-DrunkenADTests.ps1') -Output Normal

Write-Host 'DrunkenAD release-readiness checks passed.' -ForegroundColor Green
