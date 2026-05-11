@{
    RootModule        = 'DrunkenAD.psm1'
    ModuleVersion     = '0.12.1'
    GUID              = '1c86d181-178a-4a7e-8345-3bd739139dcb'
    Author            = 'Jonathan Weinberg'
    CompanyName       = 'None'
    Copyright         = '(c) 2024-2026 Jonathan Weinberg. BSD 3-Clause License.'
    Description       = 'Treat the Active Directory drink attribute as a lightweight namespaced data store with exact user resolution and guarded updates.'
    PowerShellVersion = '5.1'
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
            ReleaseNotes = '0.12.1 live-validation documentation cleanup: replace host-specific campaign wording with generic host-method guidance and keep release-readiness checks current.'
        }
    }
}
