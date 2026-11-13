@{
    RequiredVersion = '1.24.0'

    # Exact warning keys: module-relative path | rule | suppression ID or full diagnostic.
    # Each entry can excuse only one occurrence. No rules are disabled.
    ReviewedWarnings = @(
        # Private collection helpers: keep existing names and their callers unchanged.
        'Private/Core.ps1|PSUseSingularNouns|Get-DrunkenADCredentialParameters'
        'Private/CsvMapping.ps1|PSUseSingularNouns|Read-DrunkenADCsvRows'
        'Private/CsvMapping.ps1|PSUseSingularNouns|Get-DrunkenADCsvMappings'
        'Private/CsvMapping.ps1|PSUseSingularNouns|Assert-DrunkenADCsvColumns'
        'Private/CsvMapping.ps1|PSUseSingularNouns|Assert-DrunkenADCsvIdentities'
        'Private/PrefixMap.ps1|PSUseSingularNouns|Assert-DrunkenADNonOverlappingPrefixes'
        'Private/WriteOperation.ps1|PSUseSingularNouns|Get-DrunkenADIdentityParameters'

        # This constructor builds an in-memory context; it does not write to AD.
        "Private/WriteOperation.ps1|PSUseShouldProcessForStateChangingFunctions|Function 'New-DrunkenADWriteContext' has verb that could change system state. Therefore, the function has to support 'ShouldProcess'."

        # The wrappers forward PSBoundParameters (including WhatIf and Confirm) to
        # Set-ADUserDrinkPrefixedData or Set-ADUserDrinkProjection, which gate the write.
        "Public/Set-ADUserDrinkData.ps1|PSShouldProcess|'Set-ADUserDrinkData' has the ShouldProcess attribute but does not call ShouldProcess/ShouldContinue."
        "Public/Remove-ADUserDrinkData.ps1|PSShouldProcess|'Remove-ADUserDrinkData' has the ShouldProcess attribute but does not call ShouldProcess/ShouldContinue."
        "Public/Invoke-ADUserDrinkDataDemo.ps1|PSShouldProcess|'Invoke-ADUserDrinkDataDemo' has the ShouldProcess attribute but does not call ShouldProcess/ShouldContinue."
    )
}
