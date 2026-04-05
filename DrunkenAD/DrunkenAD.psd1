@{
    RootModule        = 'DrunkenAD.psm1'
    ModuleVersion     = '0.8.0'
    GUID              = '1c86d181-178a-4a7e-8345-3bd739139dcb'
    Author            = 'Jonathan Weinberg'
    CompanyName       = 'None'
    Copyright         = '(c) 2024 Jonathan Weinberg. BSD 3-Clause License.'
    Description       = 'Treat the Active Directory drink attribute as a small prefixed data store with exact user resolution and guarded updates.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-ADUserDrinkData',
        'Set-ADUserDrinkData',
        'Remove-ADUserDrinkData',
        'Invoke-ADUserDrinkDataDemo',
        'Get-AdUserDrinkPrefixedData',
        'Set-ADUserDrinkPrefixedData',
        'Test-ADDrinkAttributeEnabled',
        'Update-ADUserDrinkAttribute'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('ActiveDirectory', 'PowerShell', 'drink', 'AD')
            LicenseUri = 'https://opensource.org/license/bsd-3-clause'
        }
    }
}
