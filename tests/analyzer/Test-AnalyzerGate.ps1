[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$gate = Join-Path $root 'scripts/Test-DrunkenADAnalyzer.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('drunkenad-analyzer-' + [guid]::NewGuid())
try {
    Copy-Item -LiteralPath (Join-Path $root 'DrunkenAD') -Destination $fixture -Recurse
    & $gate -ModulePath $fixture

    # Same rule and file as a reviewed naming exception, but a different function.
    Add-Content -LiteralPath (Join-Path $fixture 'Private/CsvMapping.ps1') -Value "`nfunction Get-RegressionWidgets { 'fixture' }"
    try {
        & $gate -ModulePath $fixture
    }
    catch {
        if ($_.Exception.Message -notmatch 'PSUseSingularNouns.*Get-RegressionWidgets') { throw }
        Write-Output 'Analyzer gate rejected the new warning.'
        return
    }
    throw 'Analyzer gate accepted a new warning in a file with existing exceptions.'
}
finally {
    if (Test-Path -LiteralPath $fixture) {
        Remove-Item -LiteralPath $fixture -Recurse -Force
    }
}
