[CmdletBinding()]
param()

$projectRoot = Split-Path -Path $PSScriptRoot -Parent
$paths = @(
    'DrunkenAD/DrunkenAD.psm1'
    'DrunkenAD/DrunkenAD.psd1'
    'examples/Import-DrunkenADCsv.ps1'
    'scripts/Enable-ADDrinkAttributeOnUserClass.ps1'
    'tests/DrunkenAD.Unit.Tests.ps1'
    'tests/DrunkenAD.Integration.Tests.ps1'
    'tests/SchemaEnablement.Unit.Tests.ps1'
    'tests/Invoke-DrunkenADTests.ps1'
)

$parseFailures = @()

foreach ($relativePath in $paths) {
    $fullPath = Join-Path -Path $projectRoot -ChildPath $relativePath
    $tokens = $null
    $errors = $null

    [System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$tokens, [ref]$errors) | Out-Null

    if ($errors.Count -gt 0) {
        $parseFailures += [pscustomobject]@{
            Path   = $relativePath
            Errors = @($errors | ForEach-Object { $_.Message })
        }
    }
}

if ($parseFailures.Count -gt 0) {
    foreach ($failure in $parseFailures) {
        Write-Host "PARSE_ERROR $($failure.Path)" -ForegroundColor Red
        foreach ($message in $failure.Errors) {
            Write-Host "  $message" -ForegroundColor Red
        }
    }

    throw "One or more PowerShell files failed to parse."
}

Write-Host 'All tracked PowerShell files parsed successfully.' -ForegroundColor Green
