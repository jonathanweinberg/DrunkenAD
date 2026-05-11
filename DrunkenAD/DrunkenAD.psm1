Set-StrictMode -Version 3.0

foreach ($sourceDirectory in @('Private', 'Public')) {
    $sourceRoot = Join-Path -Path $PSScriptRoot -ChildPath $sourceDirectory
    Get-ChildItem -LiteralPath $sourceRoot -Filter '*.ps1' -File |
        Sort-Object FullName |
        ForEach-Object { . $_.FullName }
}

Export-ModuleMember -Function @(
    'Get-ADUserDrinkData',
    'Set-ADUserDrinkData',
    'Remove-ADUserDrinkData',
    'Set-ADUserDrinkProjection',
    'Import-ADUserDrinkCsvData',
    'Split-DrunkenADCsvField',
    'Invoke-ADUserDrinkDataDemo',
    'Get-AdUserDrinkPrefixedData',
    'Set-ADUserDrinkPrefixedData',
    'Test-ADDrinkAttributeEnabled',
    'Test-ADDrinkAttributeReadyForUserWrite',
    'Update-ADUserDrinkAttribute'
)
