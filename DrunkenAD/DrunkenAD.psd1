@{
    RootModule        = 'DrunkenAD.psm1'
    ModuleVersion     = '0.13.2'
    GUID              = '1c86d181-178a-4a7e-8345-3bd739139dcb'
    Author            = 'Jonathan Weinberg'
    CompanyName       = 'None'
    Copyright         = '(c) 2024-2026 Jonathan Weinberg. BSD 3-Clause License.'
    Description       = 'Treat the Active Directory drink attribute as a lightweight namespaced data store with exact user resolution and guarded updates.'
    PowerShellVersion = '5.1'
    FileList          = @(
        'DrunkenAD.psd1',
        'DrunkenAD.psm1',
        'Private/Core.ps1',
        'Private/CsvMapping.ps1',
        'Private/PrefixMap.ps1',
        'Private/ProjectionMap.ps1',
        'Private/SchemaStatus.ps1',
        'Private/WriteOperation.ps1',
        'Public/Get-ADUserDrinkData.ps1',
        'Public/Get-AdUserDrinkPrefixedData.ps1',
        'Public/Import-ADUserDrinkCsvData.ps1',
        'Public/Invoke-ADUserDrinkDataDemo.ps1',
        'Public/Remove-ADUserDrinkData.ps1',
        'Public/SchemaReadiness.ps1',
        'Public/Set-ADUserDrinkData.ps1',
        'Public/Set-ADUserDrinkPrefixedData.ps1',
        'Public/Set-ADUserDrinkProjection.ps1',
        'Public/Split-DrunkenADCsvField.ps1',
        'Public/Update-ADUserDrinkAttribute.ps1',
        'en-US/about_DrunkenAD.help.txt'
    )
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('ActiveDirectory', 'PowerShell', 'drink', 'AD')
            ProjectUri   = 'https://github.com/jonathanweinberg/DrunkenAD'
            LicenseUri   = 'https://github.com/jonathanweinberg/DrunkenAD/blob/main/LICENSE'
            ReleaseNotes = '0.13.2 safety and release-integrity patch: prefix-scoped writes, operation-scoped schema and DC selection, inherited schema readiness, CSV preflight, payload-free logging, and trusted cross-platform tests.'
        }
    }
}
