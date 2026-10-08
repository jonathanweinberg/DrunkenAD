$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../DrunkenAD/DrunkenAD.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

$global:DrunkenADTest_GetADUserCalls = @()
$global:DrunkenADTest_GetADUserHandler = { throw 'Get-ADUser test stub should be configured by the current test.' }
$global:DrunkenADTest_GetADRootDSECalls = @()
$global:DrunkenADTest_GetADRootDSEHandler = { throw 'Get-ADRootDSE test stub should be configured by the current test.' }
$global:DrunkenADTest_GetADObjectCalls = @()
$global:DrunkenADTest_GetADObjectHandler = { throw 'Get-ADObject test stub should be configured by the current test.' }
$global:DrunkenADTest_SetADUserCalls = @()
$global:DrunkenADTest_SetADUserHandler = { return }

Describe 'DrunkenAD unit tests' {
    BeforeAll {
        $script:DrunkenADUnitModulePath = Join-Path -Path $PSScriptRoot -ChildPath '../DrunkenAD/DrunkenAD.psd1'
        $script:DrunkenADUnitOriginalFunctions = @{}
        $stubDefinitions = @{
            'Get-ADUser' = {
                param(
                    $Identity,
                    $LDAPFilter,
                    $Properties,
                    $ErrorAction,
                    $Server
                )

                $global:DrunkenADTest_GetADUserCalls += ,(@{} + $PSBoundParameters)
                & $global:DrunkenADTest_GetADUserHandler @PSBoundParameters
            }
            'Get-ADRootDSE' = {
                param(
                    $Server,
                    $ErrorAction
                )

                $global:DrunkenADTest_GetADRootDSECalls += ,(@{} + $PSBoundParameters)
                & $global:DrunkenADTest_GetADRootDSEHandler @PSBoundParameters
            }
            'Get-ADObject' = {
                param(
                    $SearchBase,
                    $LDAPFilter,
                    $Properties,
                    $ErrorAction,
                    $Server
                )

                $global:DrunkenADTest_GetADObjectCalls += ,(@{} + $PSBoundParameters)
                & $global:DrunkenADTest_GetADObjectHandler @PSBoundParameters
            }
            'Set-ADUser' = {
                param(
                    $Identity,
                    $ErrorAction,
                    $Server,
                    $Clear,
                    $Replace,
                    $Add,
                    $Remove,
                    $Confirm
                )

                $global:DrunkenADTest_SetADUserCalls += ,(@{} + $PSBoundParameters)
                & $global:DrunkenADTest_SetADUserHandler @PSBoundParameters
            }
        }

        foreach ($functionName in $stubDefinitions.Keys) {
            $functionPath = 'Function:\global:{0}' -f $functionName
            $existingFunction = Get-Item -LiteralPath $functionPath -ErrorAction SilentlyContinue
            if ($existingFunction) {
                $script:DrunkenADUnitOriginalFunctions[$functionName] = $existingFunction.ScriptBlock
            }

            Set-Item -LiteralPath $functionPath -Value $stubDefinitions[$functionName]
        }
    }

    AfterAll {
        foreach ($functionName in @('Get-ADUser', 'Get-ADRootDSE', 'Get-ADObject', 'Set-ADUser')) {
            $functionPath = 'Function:\global:{0}' -f $functionName
            if ($script:DrunkenADUnitOriginalFunctions.ContainsKey($functionName)) {
                Set-Item -LiteralPath $functionPath -Value $script:DrunkenADUnitOriginalFunctions[$functionName]
            }
            else {
                Remove-Item -LiteralPath $functionPath -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Public command surface' {
        It 'exports the CSV multivalue splitter as an explicit helper' {
            Get-Command -Name Split-DrunkenADCsvField -Module DrunkenAD | Should -Not -BeNullOrEmpty
        }

        It 'keeps manifest exports and module exports in lockstep from a clean import' {
            $manifest = Test-ModuleManifest -Path $script:DrunkenADUnitModulePath
            $module = Import-Module $script:DrunkenADUnitModulePath -Force -PassThru -ErrorAction Stop

            $manifestExports = @($manifest.ExportedFunctions.Keys | Sort-Object)
            $moduleExports = @(Get-Command -Module $module.Name -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)

            $moduleExports | Should -Be $manifestExports
        }

        It 'loads source from focused Public and Private module directories' {
            $moduleRoot = Split-Path -Path $script:DrunkenADUnitModulePath -Parent
            $rootModulePath = Join-Path -Path $moduleRoot -ChildPath 'DrunkenAD.psm1'
            $rootModuleContent = Get-Content -LiteralPath $rootModulePath -Raw

            Test-Path -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'Private') -PathType Container | Should -BeTrue
            Test-Path -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'Public') -PathType Container | Should -BeTrue
            $rootModuleContent | Should -Match 'Private'
            $rootModuleContent | Should -Match 'Public'
        }
    }

    InModuleScope DrunkenAD {
        Context 'ConvertTo-DrunkenADPrefixMap' {
            It 'maps a single prefix to multiple values' {
                $result = ConvertTo-DrunkenADPrefixMap -Prefixes 'Demo-' -DrinkValues 'One', 'Two'

                $result.Keys | Should -Be @('Demo-')
                $result['Demo-'] | Should -Be @('One', 'Two')
            }

            It 'fans out a single value to many prefixes' {
                $result = ConvertTo-DrunkenADPrefixMap -Prefixes 'One-', 'Two-' -DrinkValues 'Shared'

                $result['One-'] | Should -Be @('Shared')
                $result['Two-'] | Should -Be @('Shared')
            }

            It 'merges repeated prefixes when values are aligned' {
                $result = ConvertTo-DrunkenADPrefixMap -Prefixes 'One-', 'One-', 'Two-' -DrinkValues 'A', 'B', 'C'

                $result.Keys | Should -Be @('One-', 'Two-')
                $result['One-'] | Should -Be @('A', 'B')
                $result['Two-'] | Should -Be @('C')
            }

            It 'rejects mismatched arrays that cannot be mapped safely' {
                {
                    ConvertTo-DrunkenADPrefixMap -Prefixes 'One-', 'Two-' -DrinkValues 'A', 'B', 'C'
                } | Should -Throw
            }

            It 'rejects blank prefixes' {
                {
                    ConvertTo-DrunkenADPrefixMap -Prefixes 'One-', '' -DrinkValues 'A', 'B'
                } | Should -Throw
            }
        }

        Context 'Assert-DrunkenADNonOverlappingPrefixes' {
            It 'allows distinct literal prefixes' {
                {
                    Assert-DrunkenADNonOverlappingPrefixes -Prefixes 'Profile-', 'Flags-', 'Literal[01]-'
                } | Should -Not -Throw
            }

            It 'rejects nested prefixes case-insensitively' {
                {
                    Assert-DrunkenADNonOverlappingPrefixes -Prefixes 'Profile-', 'profile-tier-'
                } | Should -Throw '*overlap*'
            }

            It 'rejects an empty prefix set with a deterministic error' {
                {
                    Assert-DrunkenADNonOverlappingPrefixes -Prefixes @()
                } | Should -Throw '*at least one prefix*'
            }
        }

        Context 'ConvertTo-DrunkenADHashtable' {
            It 'preserves nested JSON null values without a binding error' {
                $configObject = '{"Profile-":[{"Column":"Tier","Label":null}]}' | ConvertFrom-Json

                $result = ConvertTo-DrunkenADHashtable -InputObject $configObject

                $result['Profile-'][0]['Label'] | Should -BeNullOrEmpty
            }
        }

        Context 'Split-DrunkenADCsvField' {
            It 'splits CSV multivalue fields with trimming and empty item removal' {
                $result = Split-DrunkenADCsvField -Value 'Enabled; Audited ; ; Keep-Stable ' -Delimiter ';'

                $result | Should -Be @('Enabled', 'Audited', 'Keep-Stable')
            }

            It 'treats the delimiter literally instead of as a regex' {
                $result = Split-DrunkenADCsvField -Value 'One|Two||Three' -Delimiter '||'

                $result | Should -Be @('One|Two', 'Three')
            }

            It 'rejects blank delimiters to avoid character-level CSV splitting' {
                {
                    Split-DrunkenADCsvField -Value 'Enabled;Audited' -Delimiter ''
                } | Should -Throw '*Delimiter cannot be empty*'
            }
        }

        Context 'Resolve-DrunkenADUser' {
            BeforeEach {
                Mock Get-Module { [pscustomobject]@{ Name = 'ActiveDirectory' } }
                Mock Import-Module {}
                $global:DrunkenADTest_GetADUserCalls = @()
            }

            It 'uses an exact escaped LDAP filter for mail lookups' {
                $global:DrunkenADTest_GetADUserHandler = {
                    [pscustomobject]@{
                        SamAccountName    = 'demo'
                        DistinguishedName = 'CN=Demo User,DC=contoso,DC=com'
                        drink             = @()
                    }
                }

                Resolve-DrunkenADUser -Mail 'user*(test)\name@example.com' -Server 'dc01.contoso.com' | Out-Null

                $global:DrunkenADTest_GetADUserCalls.Count | Should -Be 1
                $global:DrunkenADTest_GetADUserCalls[0]['LDAPFilter'] | Should -Be '(mail=user\2a\28test\29\5cname@example.com)'
                $global:DrunkenADTest_GetADUserCalls[0]['Server'] | Should -Be 'dc01.contoso.com'
                $global:DrunkenADTest_GetADUserCalls[0]['ErrorAction'] | Should -Be 'Stop'
            }

            It 'throws when a lookup returns more than one user' {
                $global:DrunkenADTest_GetADUserHandler = {
                    @(
                        [pscustomobject]@{ SamAccountName = 'demo1'; DistinguishedName = 'CN=Demo1,DC=contoso,DC=com' }
                        [pscustomobject]@{ SamAccountName = 'demo2'; DistinguishedName = 'CN=Demo2,DC=contoso,DC=com' }
                    )
                }

                {
                    Resolve-DrunkenADUser -SamAccountName 'demo'
                } | Should -Throw '*matched 2 users*'
            }
        }

        Context 'Test-ADDrinkAttributeEnabled' {
            BeforeEach {
                Mock Get-Module { [pscustomobject]@{ Name = 'ActiveDirectory' } }
                Mock Import-Module {}
                $global:DrunkenADTest_GetADRootDSECalls = @()
                $global:DrunkenADTest_GetADObjectCalls = @()
                $global:DrunkenADTest_GetADRootDSEHandler = { [pscustomobject]@{ SchemaNamingContext = 'CN=Schema,CN=Configuration,DC=contoso,DC=com'; dnsHostName = 'dc01.contoso.com' } }
            }

            It 'returns true when the drink attribute exists and is active' {
                $global:DrunkenADTest_GetADObjectHandler = {
                    param($SearchBase, $LDAPFilter)

                    switch ($LDAPFilter) {
                        '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))' {
                            [pscustomobject]@{ isDefunct = $false; DistinguishedName = 'CN=drink,CN=Schema,CN=Configuration,DC=contoso,DC=com' }
                        }
                        '(&(objectClass=classSchema)(lDAPDisplayName=user))' {
                            [pscustomobject]@{ DistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=contoso,DC=com'; mayContain = @('drink'); systemMayContain = @('cn') }
                        }
                        default {
                            throw "Unexpected LDAP filter '$LDAPFilter'."
                        }
                    }
                }

                Test-ADDrinkAttributeEnabled -Server 'dc01.contoso.com' | Should -BeTrue

                $global:DrunkenADTest_GetADRootDSECalls.Count | Should -Be 1
                $global:DrunkenADTest_GetADObjectCalls.Count | Should -Be 2
                $global:DrunkenADTest_GetADObjectCalls[0]['SearchBase'] | Should -Be 'CN=Schema,CN=Configuration,DC=contoso,DC=com'
                $global:DrunkenADTest_GetADObjectCalls[0]['LDAPFilter'] | Should -Be '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))'
                $global:DrunkenADTest_GetADObjectCalls[0]['Server'] | Should -Be 'dc01.contoso.com'
                $global:DrunkenADTest_GetADObjectCalls[1]['LDAPFilter'] | Should -Be '(&(objectClass=classSchema)(lDAPDisplayName=user))'
            }

            It 'returns false when the drink attribute is missing' {
                $global:DrunkenADTest_GetADObjectHandler = {
                    param($SearchBase, $LDAPFilter)

                    switch ($LDAPFilter) {
                        '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))' {
                            @()
                        }
                        '(&(objectClass=classSchema)(lDAPDisplayName=user))' {
                            [pscustomobject]@{ DistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=contoso,DC=com'; mayContain = @(); systemMayContain = @('cn') }
                        }
                        default {
                            throw "Unexpected LDAP filter '$LDAPFilter'."
                        }
                    }
                }

                Test-ADDrinkAttributeEnabled | Should -BeFalse
            }

            It 'returns write-readiness details through PassThru without changing the Boolean meaning' {
                $global:DrunkenADTest_GetADObjectHandler = {
                    param($SearchBase, $LDAPFilter)

                    switch ($LDAPFilter) {
                        '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))' {
                            [pscustomobject]@{ isDefunct = $false; DistinguishedName = 'CN=drink,CN=Schema,CN=Configuration,DC=contoso,DC=com' }
                        }
                        '(&(objectClass=classSchema)(lDAPDisplayName=user))' {
                            [pscustomobject]@{ DistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=contoso,DC=com'; mayContain = @(); systemMayContain = @('cn') }
                        }
                        default {
                            throw "Unexpected LDAP filter '$LDAPFilter'."
                        }
                    }
                }

                $result = Test-ADDrinkAttributeEnabled -PassThru

                $result.Enabled | Should -BeTrue
                $result.AllowedOnUserClass | Should -BeFalse
                $result.ReadyForUserWrite | Should -BeFalse
                $result.BlockingReason | Should -Be 'NotAllowedOnUserClass'
                $result.SchemaNamingContext | Should -Be 'CN=Schema,CN=Configuration,DC=contoso,DC=com'
                $result.UserClassDistinguishedName | Should -Be 'CN=User,CN=Schema,CN=Configuration,DC=contoso,DC=com'
            }
        }

        Context 'Test-ADDrinkAttributeReadyForUserWrite' {
            BeforeEach {
                Mock Get-Module { [pscustomobject]@{ Name = 'ActiveDirectory' } }
                Mock Import-Module {}
                $global:DrunkenADTest_GetADRootDSECalls = @()
                $global:DrunkenADTest_GetADObjectCalls = @()
                $global:DrunkenADTest_GetADRootDSEHandler = { [pscustomobject]@{ SchemaNamingContext = 'CN=Schema,CN=Configuration,DC=contoso,DC=com'; dnsHostName = 'dc01.contoso.com' } }
            }

            It 'returns true when drink is allowed on the user class' {
                $global:DrunkenADTest_GetADObjectHandler = {
                    param($SearchBase, $LDAPFilter)

                    switch ($LDAPFilter) {
                        '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))' {
                            [pscustomobject]@{ isDefunct = $false; DistinguishedName = 'CN=drink,CN=Schema,CN=Configuration,DC=contoso,DC=com' }
                        }
                        '(&(objectClass=classSchema)(lDAPDisplayName=user))' {
                            [pscustomobject]@{ DistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=contoso,DC=com'; mayContain = @('drink'); systemMayContain = @() }
                        }
                        default {
                            throw "Unexpected LDAP filter '$LDAPFilter'."
                        }
                    }
                }

                Test-ADDrinkAttributeReadyForUserWrite | Should -BeTrue
            }

            It 'returns false with a blocking reason when drink is not allowed on the user class' {
                $global:DrunkenADTest_GetADObjectHandler = {
                    param($SearchBase, $LDAPFilter)

                    switch ($LDAPFilter) {
                        '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))' {
                            [pscustomobject]@{ isDefunct = $false; DistinguishedName = 'CN=drink,CN=Schema,CN=Configuration,DC=contoso,DC=com' }
                        }
                        '(&(objectClass=classSchema)(lDAPDisplayName=user))' {
                            [pscustomobject]@{ DistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=contoso,DC=com'; mayContain = @(); systemMayContain = @('cn') }
                        }
                        default {
                            throw "Unexpected LDAP filter '$LDAPFilter'."
                        }
                    }
                }

                $result = Test-ADDrinkAttributeReadyForUserWrite -PassThru

                $result.ReadyForUserWrite | Should -BeFalse
                $result.BlockingReason | Should -Be 'NotAllowedOnUserClass'
                $result.BlockingMessage | Should -BeLike '*not allowed on the Active Directory user class*'
            }

            It 'returns false when the drink attribute is defunct' {
                $global:DrunkenADTest_GetADObjectHandler = {
                    param($SearchBase, $LDAPFilter)

                    switch ($LDAPFilter) {
                        '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))' {
                            [pscustomobject]@{ isDefunct = $true; DistinguishedName = 'CN=drink,CN=Schema,CN=Configuration,DC=contoso,DC=com' }
                        }
                        '(&(objectClass=classSchema)(lDAPDisplayName=user))' {
                            [pscustomobject]@{ DistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=contoso,DC=com'; mayContain = @('drink'); systemMayContain = @() }
                        }
                        default {
                            throw "Unexpected LDAP filter '$LDAPFilter'."
                        }
                    }
                }

                $result = Test-ADDrinkAttributeReadyForUserWrite -PassThru

                $result.ReadyForUserWrite | Should -BeFalse
                $result.BlockingReason | Should -Be 'AttributeDefunct'
            }
        }

        Context 'Get-AdUserDrinkPrefixedData' {
            BeforeEach {
                Mock Assert-ADDrinkAttributeEnabled {}
                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        drink = @('Prefix[01]-Old', 'Prefix01-Other', 'Keep-Me')
                    }
                }
            }

            It 'treats the requested prefix literally instead of as a regex' {
                $result = Get-AdUserDrinkPrefixedData -SamAccountName 'demo' -DrinkValuePrefix 'Prefix[01]-'

                $result | Should -Be @('Prefix[01]-Old')
            }

            It 'returns an empty array when no values match the prefix' {
                $result = Get-AdUserDrinkPrefixedData -SamAccountName 'demo' -DrinkValuePrefix 'Missing-'

                @($result) | Should -Be @()
            }
        }

        Context 'Get-ADUserDrinkData' {
            BeforeEach {
                Mock Assert-ADDrinkAttributeEnabled {}
                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        drink = @('Profile-Tier=Gold', 'Flags-Audited', 'Flags-Enabled')
                    }
                }
            }

            It 'returns the whole generic data set when no prefix is supplied' {
                $result = Get-ADUserDrinkData -SamAccountName 'demo'

                $result | Should -Be @('Profile-Tier=Gold', 'Flags-Audited', 'Flags-Enabled')
            }

            It 'filters the generic data set by literal prefix when requested' {
                $result = Get-ADUserDrinkData -SamAccountName 'demo' -Prefix 'Flags-'

                $result | Should -Be @('Flags-Audited', 'Flags-Enabled')
            }

            It 'rejects a blank supplied prefix before checking AD readiness' {
                {
                    Get-ADUserDrinkData -SamAccountName 'demo' -Prefix '   '
                } | Should -Throw '*Prefix*blank*'

                Assert-MockCalled Assert-ADDrinkAttributeEnabled -Times 0
                Assert-MockCalled Resolve-DrunkenADUser -Times 0
            }

            It 'matches prefix ownership ordinally under Turkish culture' {
                $previousCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
                $previousUiCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
                try {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
                    [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
                    Mock Resolve-DrunkenADUser {
                        [pscustomobject]@{
                            drink = @('FILE-Old', 'Keep-Stable')
                        }
                    }

                    $result = Get-ADUserDrinkData -SamAccountName 'demo' -Prefix 'file-'

                    $result | Should -Be @('FILE-Old')
                }
                finally {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = $previousCulture
                    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $previousUiCulture
                }
            }
        }

        Context 'Set-ADUserDrinkPrefixedData' {
            BeforeEach {
                Mock New-DrunkenADWriteContext {
                    [pscustomobject]@{ Server = 'dc01.contoso.com'; RangeUpper = 256; ReadyForUserWrite = $true }
                }
                Mock Write-DrunkenADLog {}
                $global:DrunkenADTest_SetADUserCalls = @()
            }

            It 'rejects overlapping prefixes before checking AD readiness' {
                {
                    Set-ADUserDrinkPrefixedData -SamAccountName 'demo' -PrefixMap @{
                        'Profile-'      = @('Tier=Gold')
                        'Profile-Tier-' = @('Gold')
                    } -Confirm:$false
                } | Should -Throw '*overlap*'

                Assert-MockCalled New-DrunkenADWriteContext -Times 0
                $global:DrunkenADTest_SetADUserCalls.Count | Should -Be 0
            }

            It 'replaces only the targeted literal prefix and preserves unrelated values' {
                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        SamAccountName    = 'demo'
                        DistinguishedName = 'CN=Demo User,DC=contoso,DC=com'
                        drink             = @('Test[1]-old', 'Test1-old', 'Keep-me')
                    }
                }

                $result = Set-ADUserDrinkPrefixedData -SamAccountName 'demo' -PrefixMap @{ 'Test[1]-' = @('new') } -Confirm:$false -PassThru

                $result | Should -Contain 'Test[1]-new'
                $result | Should -Contain 'Test1-old'
                $result | Should -Contain 'Keep-me'
                $result | Should -Not -Contain 'Test[1]-old'

                $global:DrunkenADTest_SetADUserCalls.Count | Should -Be 1
                $global:DrunkenADTest_SetADUserCalls[0]['Identity'] | Should -Be 'CN=Demo User,DC=contoso,DC=com'
                $global:DrunkenADTest_SetADUserCalls[0]['Add']['drink'] | Should -Be @('Test[1]-new')
                $global:DrunkenADTest_SetADUserCalls[0]['Remove']['drink'] | Should -Be @('Test[1]-old')
                $global:DrunkenADTest_SetADUserCalls[0].ContainsKey('Replace') | Should -BeFalse
                $global:DrunkenADTest_SetADUserCalls[0].ContainsKey('Clear') | Should -BeFalse
                $global:DrunkenADTest_SetADUserCalls[0]['Server'] | Should -Be 'dc01.contoso.com'
                $global:DrunkenADTest_SetADUserCalls[0]['Confirm'] | Should -BeFalse
            }

            It 'replaces prefix ownership ordinally under Turkish culture' {
                $previousCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
                $previousUiCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
                try {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
                    [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
                    Mock Resolve-DrunkenADUser {
                        [pscustomobject]@{
                            SamAccountName    = 'demo'
                            DistinguishedName = 'CN=Demo User,DC=contoso,DC=com'
                            drink             = @('FILE-Old', 'Keep-Stable')
                        }
                    }

                    $result = Set-ADUserDrinkPrefixedData -SamAccountName 'demo' -PrefixMap @{ 'file-' = @('New') } -Confirm:$false -PassThru

                    $result | Should -Contain 'file-New'
                    $result | Should -Contain 'Keep-Stable'
                    $result | Should -Not -Contain 'FILE-Old'
                    $global:DrunkenADTest_SetADUserCalls.Count | Should -Be 1
                    $global:DrunkenADTest_SetADUserCalls[0]['Remove']['drink'] | Should -Be @('FILE-Old')
                    $global:DrunkenADTest_SetADUserCalls[0]['Add']['drink'] | Should -Be @('file-New')
                }
                finally {
                    [System.Threading.Thread]::CurrentThread.CurrentCulture = $previousCulture
                    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $previousUiCulture
                }
            }

            It 'removes all owned values without clearing the whole attribute' {
                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        SamAccountName    = 'demo'
                        DistinguishedName = 'CN=Demo User,DC=contoso,DC=com'
                        drink             = @('OnlyPrefix-old')
                    }
                }

                Set-ADUserDrinkPrefixedData -SamAccountName 'demo' -PrefixMap @{ 'OnlyPrefix-' = @() } -Confirm:$false

                $global:DrunkenADTest_SetADUserCalls.Count | Should -Be 1
                $global:DrunkenADTest_SetADUserCalls[0]['Identity'] | Should -Be 'CN=Demo User,DC=contoso,DC=com'
                $global:DrunkenADTest_SetADUserCalls[0]['Remove']['drink'] | Should -Be @('OnlyPrefix-old')
                $global:DrunkenADTest_SetADUserCalls[0].ContainsKey('Add') | Should -BeFalse
                $global:DrunkenADTest_SetADUserCalls[0].ContainsKey('Clear') | Should -BeFalse
                $global:DrunkenADTest_SetADUserCalls[0].ContainsKey('Replace') | Should -BeFalse
            }

            It 'does not write when the attribute is already in the desired state' {
                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        SamAccountName    = 'demo'
                        DistinguishedName = 'CN=Demo User,DC=contoso,DC=com'
                        drink             = @('Stable-value', 'Keep-me')
                    }
                }

                Set-ADUserDrinkPrefixedData -SamAccountName 'demo' -PrefixMap @{ 'Stable-' = @('value') } -Confirm:$false

                $global:DrunkenADTest_SetADUserCalls.Count | Should -Be 0
            }

            It 'does not confuse one newline-containing value with two values' {
                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        SamAccountName    = 'demo'
                        DistinguishedName = 'CN=Demo User,DC=contoso,DC=com'
                        drink             = @("Target-a`nTarget-b", 'Keep-stable')
                    }
                }

                Set-ADUserDrinkPrefixedData -SamAccountName 'demo' -PrefixMap @{ 'Target-' = @('a', 'b') } -Confirm:$false

                $global:DrunkenADTest_SetADUserCalls.Count | Should -Be 1
                $global:DrunkenADTest_SetADUserCalls[0]['Remove']['drink'] | Should -Be @("Target-a`nTarget-b")
                $global:DrunkenADTest_SetADUserCalls[0]['Add']['drink'] | Should -Be @('Target-a', 'Target-b')
            }

            It 'normalizes preserved values to strings without including them in the write delta' {
                $preservedValue = New-Object psobject
                $preservedValue | Add-Member -MemberType ScriptMethod -Name ToString -Value { 'Keep-me' } -Force

                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        SamAccountName    = 'demo'
                        DistinguishedName = 'CN=Demo User,DC=contoso,DC=com'
                        drink             = @('Test[1]-old', $preservedValue)
                    }
                }

                $result = @(Set-ADUserDrinkPrefixedData -SamAccountName 'demo' -PrefixMap @{ 'Test[1]-' = @('new') } -Confirm:$false -PassThru)

                $result | Should -Be @('Keep-me', 'Test[1]-new')
                ($result | ForEach-Object { $_.GetType().FullName } | Sort-Object -Unique) | Should -Be @('System.String')
                $global:DrunkenADTest_SetADUserCalls.Count | Should -Be 1
                $global:DrunkenADTest_SetADUserCalls[0]['Add']['drink'] | Should -Be @('Test[1]-new')
                $global:DrunkenADTest_SetADUserCalls[0]['Remove']['drink'] | Should -Be @('Test[1]-old')
            }

            It 'respects WhatIf and skips the underlying write' {
                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        SamAccountName    = 'demo'
                        DistinguishedName = 'CN=Demo User,DC=contoso,DC=com'
                        drink             = @('Old-value')
                    }
                }

                Set-ADUserDrinkPrefixedData -SamAccountName 'demo' -PrefixMap @{ 'Old-' = @('new') } -WhatIf

                $global:DrunkenADTest_SetADUserCalls.Count | Should -Be 0
            }

            It 'throws the readiness error when user writes are not supported' {
                Mock New-DrunkenADWriteContext {
                    throw "The 'drink' attribute exists in the target Active Directory schema but is not allowed on the Active Directory user class."
                }

                {
                    Set-ADUserDrinkPrefixedData -SamAccountName 'demo' -PrefixMap @{ 'Test-' = @('new') } -Confirm:$false
                } | Should -Throw '*not allowed on the Active Directory user class*'
            }
        }

        Context 'Set-ADUserDrinkData' {
            BeforeEach {
                Mock New-DrunkenADWriteContext {
                    [pscustomobject]@{ Server = 'dc01.contoso.com'; RangeUpper = 256; ReadyForUserWrite = $true }
                }
                Mock Set-ADUserDrinkPrefixedData {}
            }

            It 'forwards the generic DataMap to the lower-level prefixed writer' {
                Set-ADUserDrinkData -SamAccountName 'demo' -DataMap @{ 'Profile-' = @('Tier=Gold'); 'Flags-' = @('Enabled') }

                Assert-MockCalled Set-ADUserDrinkPrefixedData -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    ((@($PrefixMap['Profile-']) -join ',') -eq 'Tier=Gold') -and
                    ((@($PrefixMap['Flags-']) -join ',') -eq 'Enabled')
                }
            }

            It 'honors WhatIf at the generic writer layer' {
                Set-ADUserDrinkData -SamAccountName 'demo' -DataMap @{ 'Profile-' = @('Tier=Gold') } -WhatIf

                Assert-MockCalled Set-ADUserDrinkPrefixedData -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and $WhatIf -and
                    (@($PrefixMap['Profile-']) -join ',') -eq 'Tier=Gold'
                }
            }

            It 'rejects an overlapping DataMap before checking AD readiness' {
                Mock New-DrunkenADWriteContext {
                    throw 'AD readiness should not run for invalid local input.'
                }

                {
                    Set-ADUserDrinkData -SamAccountName 'demo' -DataMap @{
                        'Profile-'      = @('Tier=Gold')
                        'Profile-Tier-' = @('Gold')
                    } -Confirm:$false
                } | Should -Throw '*overlap*'

                Assert-MockCalled New-DrunkenADWriteContext -Times 0
                Assert-MockCalled Set-ADUserDrinkPrefixedData -Times 0
            }
        }

        Context 'Remove-ADUserDrinkData' {
            BeforeEach {
                Mock New-DrunkenADWriteContext {
                    [pscustomobject]@{ Server = 'dc01.contoso.com'; RangeUpper = 256; ReadyForUserWrite = $true }
                }
                Mock Set-ADUserDrinkData {}
            }

            It 'builds an empty namespace map for the prefixes being removed' {
                Remove-ADUserDrinkData -SamAccountName 'demo' -Prefixes 'Profile-', 'Flags-'

                Assert-MockCalled Set-ADUserDrinkData -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    $DataMap.Contains('Profile-') -and
                    $DataMap.Contains('Flags-') -and
                    (@($DataMap['Profile-']).Count -eq 0) -and
                    (@($DataMap['Flags-']).Count -eq 0)
                }
            }

            It 'honors WhatIf at the generic remover layer' {
                Remove-ADUserDrinkData -SamAccountName 'demo' -Prefixes 'Profile-' -WhatIf

                Assert-MockCalled Set-ADUserDrinkData -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and $WhatIf -and
                    $DataMap.Contains('Profile-') -and @($DataMap['Profile-']).Count -eq 0
                }
            }

            It 'rejects a blank prefix before checking AD readiness' {
                Mock New-DrunkenADWriteContext {
                    throw 'AD readiness should not run for invalid local input.'
                }

                {
                    Remove-ADUserDrinkData -SamAccountName 'demo' -Prefixes '   ' -Confirm:$false
                } | Should -Throw '*cannot be null, empty, or whitespace*'

                Assert-MockCalled New-DrunkenADWriteContext -Times 0
                Assert-MockCalled Set-ADUserDrinkData -Times 0
            }
        }

        Context 'Set-ADUserDrinkProjection' {
            BeforeEach {
                Mock New-DrunkenADWriteContext {
                    [pscustomobject]@{ Server = 'dc01.contoso.com'; RangeUpper = 256; ReadyForUserWrite = $true }
                }
                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        SamAccountName    = 'demo'
                        DistinguishedName = 'CN=Demo User,DC=contoso,DC=com'
                        userPrincipalName = 'demo@contoso.com'
                        employeeID        = '123456'
                        mail              = 'demo@contoso.com'
                        pager             = '555-0100'
                        department        = 'Identity'
                        title             = 'Engineer'
                        company           = 'Contoso'
                        description       = 'Demo account'
                        drink             = @('Keep-Stable')
                    }
                }
                Mock Invoke-DrunkenADPrefixWrite {
                    @('Profile-samAccountName=demo')
                }
                Mock Set-ADUserDrinkData { throw 'Projection must use the resolved user and write context directly.' }
            }

            AfterEach {
                Assert-MockCalled Set-ADUserDrinkData -Times 0
            }

            It 'uses the built-in default attribute map when none is supplied' {
                $result = Set-ADUserDrinkProjection -SamAccountName 'demo' -Confirm:$false -PassThru

                Assert-MockCalled Resolve-DrunkenADUser -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    $Server -eq 'dc01.contoso.com' -and
                    (@($Properties) -contains 'samAccountName') -and
                    (@($Properties) -contains 'userPrincipalName') -and
                    (@($Properties) -contains 'employeeID') -and
                    (@($Properties) -contains 'mail') -and
                    (@($Properties) -contains 'pager')
                }

                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 1 -Exactly -ParameterFilter {
                    $User.SamAccountName -eq 'demo' -and
                    $User.DistinguishedName -eq 'CN=Demo User,DC=contoso,DC=com' -and
                    (@($User.drink) -join ',') -eq 'Keep-Stable' -and
                    $Context.Server -eq 'dc01.contoso.com' -and
                    $Context.RangeUpper -eq 256 -and $Context.ReadyForUserWrite -and
                    $PassThru -and ($Confirm -eq $false) -and
                    ((@($PrefixMap['Profile-']) -join ',') -eq 'samAccountName=demo') -and
                    ((@($PrefixMap['Identity-']) -join ',') -eq 'userPrincipalName=demo@contoso.com') -and
                    ((@($PrefixMap['Meta-']) -join ',') -eq 'employeeID=123456') -and
                    ((@($PrefixMap['Routing-']) -join ',') -eq 'mail=demo@contoso.com') -and
                    ((@($PrefixMap['Notify-']) -join ',') -eq 'pager=555-0100')
                }

                $result.SamAccountName | Should -Be 'demo'
                $result.DataMap.Contains('Profile-') | Should -BeTrue
                $result.FinalDrinkValues | Should -Be @('Profile-samAccountName=demo')
            }

            It 'replaces the default projection map when a custom map is supplied' {
                Set-ADUserDrinkProjection -SamAccountName 'demo' -AttributeMap @{ 'Org-' = @('department', 'title') } -Confirm:$false | Out-Null

                Assert-MockCalled Resolve-DrunkenADUser -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    (@($Properties).Count -eq 2) -and
                    (@($Properties) -contains 'department') -and
                    (@($Properties) -contains 'title')
                }

                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 1 -Exactly -ParameterFilter {
                    $User.SamAccountName -eq 'demo' -and
                    $Context.Server -eq 'dc01.contoso.com' -and
                    $PrefixMap.Count -eq 1 -and
                    ((@($PrefixMap['Org-']) | Sort-Object) -join ',') -eq 'department=Identity,title=Engineer'
                }
            }

            It 'clears a projected namespace when all mapped source values are blank' {
                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        SamAccountName    = 'demo'
                        DistinguishedName = 'CN=Demo User,DC=contoso,DC=com'
                        department        = $null
                        title             = '   '
                        drink             = @('Org-department=Old', 'Keep-Stable')
                    }
                }

                Set-ADUserDrinkProjection -SamAccountName 'demo' -AttributeMap @{ 'Org-' = @('department', 'title') } -Confirm:$false | Out-Null

                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 1 -Exactly -ParameterFilter {
                    $User.SamAccountName -eq 'demo' -and
                    (@($User.drink) -contains 'Org-department=Old') -and
                    $PrefixMap.Contains('Org-') -and
                    @($PrefixMap['Org-']).Count -eq 0
                }
            }

            It 'rejects an invalid projection map before checking AD readiness' {
                Mock New-DrunkenADWriteContext {
                    throw 'AD readiness should not run for invalid local input.'
                }

                {
                    Set-ADUserDrinkProjection -SamAccountName 'demo' -AttributeMap @{ 'Org-' = @('   ') } -Confirm:$false
                } | Should -Throw '*must include at least one attribute name*'

                Assert-MockCalled New-DrunkenADWriteContext -Times 0
                Assert-MockCalled Resolve-DrunkenADUser -Times 0
                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 0
            }

            It 'merges a custom map with the default projection map when requested' {
                Set-ADUserDrinkProjection -SamAccountName 'demo' -AttributeMap @{ 'Org-' = @('company') } -IncludeDefaultAttributeMap -Confirm:$false | Out-Null

                Assert-MockCalled Resolve-DrunkenADUser -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    (@($Properties) -contains 'company') -and
                    (@($Properties) -contains 'samAccountName')
                }

                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 1 -Exactly -ParameterFilter {
                    $PrefixMap.Contains('Org-') -and
                    $PrefixMap.Contains('Profile-') -and
                    ((@($PrefixMap['Org-']) -join ',') -eq 'company=Contoso')
                }
            }

            It 'honors WhatIf at the projection layer' {
                $result = Set-ADUserDrinkProjection -SamAccountName 'demo' -WhatIf -PassThru

                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 1 -Exactly -ParameterFilter {
                    $User.SamAccountName -eq 'demo' -and $WhatIf -and $PassThru -and
                    $Context.Server -eq 'dc01.contoso.com' -and $PrefixMap.Contains('Profile-')
                }
                $result.FinalDrinkValues | Should -Be @('Profile-samAccountName=demo')
            }
        }

        Context 'Import-ADUserDrinkCsvData' {
            BeforeEach {
                Mock Test-Path { $true }
                Mock New-DrunkenADWriteContext {
                    [pscustomobject]@{ Server = 'dc01.contoso.com'; RangeUpper = 256; ReadyForUserWrite = $true }
                }
                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        SamAccountName = $SamAccountName
                        DistinguishedName = "CN=$SamAccountName,DC=contoso,DC=com"
                        drink = @('Keep-Stable')
                    }
                }
                Mock Import-Csv {
                    @(
                        [pscustomobject]@{
                            SamAccountName = 'alice'
                            ProfileTier    = 'Gold'
                            Flags          = 'Enabled;Audited'
                        }
                    )
                }
                Mock Invoke-DrunkenADPrefixWrite {
                    @('Profile-Tier=Gold', 'Flags-Enabled', 'Flags-Audited')
                }
                Mock Set-ADUserDrinkData { throw 'CSV imports must reuse the resolved user and write context.' }
            }

            AfterEach {
                Assert-MockCalled Set-ADUserDrinkData -Times 0
            }

            It 'imports a CSV row using an in-memory namespace map' {
                $namespaceMap = @{
                    'Profile-' = @(
                        @{ Column = 'ProfileTier'; Label = 'Tier' }
                    )
                    'Flags-' = @(
                        @{ Column = 'Flags'; SplitOn = ';' }
                    )
                }

                $result = Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com' -Confirm:$false

                Assert-MockCalled New-DrunkenADWriteContext -Times 1 -Exactly -ParameterFilter {
                    $Server -eq 'dc01.contoso.com'
                }

                Assert-MockCalled Resolve-DrunkenADUser -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'alice' -and
                    $Server -eq 'dc01.contoso.com' -and (@($Properties) -contains 'drink')
                }

                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 1 -Exactly -ParameterFilter {
                    $User.SamAccountName -eq 'alice' -and
                    $User.DistinguishedName -eq 'CN=alice,DC=contoso,DC=com' -and
                    (@($User.drink) -join ',') -eq 'Keep-Stable' -and
                    $Context.Server -eq 'dc01.contoso.com' -and
                    $Context.RangeUpper -eq 256 -and $Context.ReadyForUserWrite -and
                    ((@($PrefixMap['Profile-']) -join ',') -eq 'Tier=Gold') -and
                    ((@($PrefixMap['Flags-']) | Sort-Object) -join ',') -eq 'Audited,Enabled' -and
                    $PassThru -and
                    ($Confirm -eq $false)
                }

                $result.ConfigSource | Should -Be 'NamespaceMap'
                $result.Namespaces | Should -Contain 'Profile-'
                $result.Namespaces | Should -Contain 'Flags-'
            }

            It 'does not create label-only records from blank CSV fields' {
                Mock Import-Csv {
                    @(
                        [pscustomobject]@{
                            SamAccountName = 'alice'
                            ProfileTier    = '   '
                            Flags          = 'Enabled'
                        }
                    )
                }

                $namespaceMap = @{
                    'Profile-' = @(
                        @{ Column = 'ProfileTier'; Label = 'Tier' }
                    )
                    'Flags-' = @(
                        @{ Column = 'Flags' }
                    )
                }

                Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com' | Out-Null

                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 1 -Exactly -ParameterFilter {
                    -not $PrefixMap.Contains('Profile-') -and
                    ((@($PrefixMap['Flags-']) -join ',') -eq 'Enabled')
                }
            }

            It 'rejects duplicate normalized CSV identities before checking AD readiness' {
                Mock Import-Csv {
                    @(
                        [pscustomobject]@{ SamAccountName = 'Alice'; ProfileTier = 'Gold' }
                        [pscustomobject]@{ SamAccountName = ' alice '; ProfileTier = 'Silver' }
                    )
                }
                $namespaceMap = @{
                    'Profile-' = @(
                        @{ Column = 'ProfileTier'; Label = 'Tier' }
                    )
                }

                {
                    Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com'
                } | Should -Throw '*duplicate*SamAccountName*'

                Assert-MockCalled New-DrunkenADWriteContext -Times 0
                Assert-MockCalled Resolve-DrunkenADUser -Times 0
                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 0
            }

            It 'trims a unique CSV identity before writing and reporting it' {
                Mock Import-Csv {
                    @(
                        [pscustomobject]@{ SamAccountName = ' alice '; ProfileTier = 'Gold' }
                    )
                }
                $namespaceMap = @{
                    'Profile-' = @(
                        @{ Column = 'ProfileTier'; Label = 'Tier' }
                    )
                }

                $result = Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com'

                $result.SamAccountName | Should -Be 'alice'
                Assert-MockCalled Resolve-DrunkenADUser -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'alice'
                }
                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 1 -Exactly -ParameterFilter {
                    $User.SamAccountName -eq 'alice'
                }
            }

            It 'loads mappings from a JSON config file when ConfigPath is supplied' {
                Mock Get-Content {
                    @'
{
  "Tenant-": [
    {
      "Column": "TenantId",
      "Label": "Id"
    }
  ]
}
'@
                }

                Mock Import-Csv {
                    @(
                        [pscustomobject]@{
                            SamAccountName = 'alice'
                            TenantId       = 'TEN-001'
                        }
                    )
                }

                Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -ConfigPath '/tmp/drink-config.json' -DomainController 'dc01.contoso.com' | Out-Null

                Assert-MockCalled Get-Content -Times 1 -Exactly -ParameterFilter {
                    $LiteralPath -eq '/tmp/drink-config.json' -and
                    $Raw
                }

                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 1 -Exactly -ParameterFilter {
                    $User.SamAccountName -eq 'alice' -and
                    ((@($PrefixMap['Tenant-']) -join ',') -eq 'Id=TEN-001')
                }
            }

            It 'returns planned values without invoking the writer during CSV WhatIf' {
                $namespaceMap = @{
                    'Profile-' = @(
                        @{ Column = 'ProfileTier'; Label = 'Tier' }
                    )
                }

                $result = Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com' -WhatIf

                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 0
                $result.FinalDrinkValues | Should -Be @('Keep-Stable', 'Profile-Tier=Gold')
            }

            It 'throws a deterministic error when the CSV is missing SamAccountName' {
                Mock Import-Csv {
                    @(
                        [pscustomobject]@{
                            ProfileTier = 'Gold'
                        }
                    )
                }

                $namespaceMap = @{
                    'Profile-' = @(
                        @{ Column = 'ProfileTier'; Label = 'Tier' }
                    )
                }

                {
                    Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com'
                } | Should -Throw "*missing required column 'SamAccountName'*"

                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 0
            }

            It 'validates CSV columns before checking AD readiness' {
                Mock New-DrunkenADWriteContext {
                    throw 'AD readiness should not run for invalid local input.'
                }
                Mock Import-Csv {
                    @(
                        [pscustomobject]@{
                            Department = 'Engineering'
                        }
                    )
                }

                $namespaceMap = @{
                    'Org-' = @(
                        @{ Column = 'Department'; Label = 'Department' }
                    )
                }

                {
                    Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com'
                } | Should -Throw "*missing required column 'SamAccountName'*"

                Assert-MockCalled New-DrunkenADWriteContext -Times 0
                Assert-MockCalled Resolve-DrunkenADUser -Times 0
                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 0
            }

            It 'rejects a CSV with no data rows before checking AD readiness' {
                Mock New-DrunkenADWriteContext {
                    throw 'AD readiness should not run for invalid local input.'
                }
                Mock Import-Csv { @() }

                $namespaceMap = @{
                    'Profile-' = @(
                        @{ Column = 'ProfileTier'; Label = 'Tier' }
                    )
                }

                {
                    Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com'
                } | Should -Throw '*does not contain any data rows*'

                Assert-MockCalled New-DrunkenADWriteContext -Times 0
                Assert-MockCalled Resolve-DrunkenADUser -Times 0
                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 0
            }

            It 'rejects overlapping CSV namespaces before checking AD readiness' {
                Mock New-DrunkenADWriteContext {
                    throw 'AD readiness should not run for invalid local input.'
                }
                Mock Import-Csv {
                    @(
                        [pscustomobject]@{
                            SamAccountName = 'alice'
                            ProfileTier    = 'Gold'
                        }
                    )
                }

                $namespaceMap = @{
                    'Profile-'      = @(@{ Column = 'ProfileTier'; Label = 'Tier' })
                    'Profile-Tier-' = @(@{ Column = 'ProfileTier' })
                }

                {
                    Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com'
                } | Should -Throw '*overlap*'

                Assert-MockCalled New-DrunkenADWriteContext -Times 0
                Assert-MockCalled Resolve-DrunkenADUser -Times 0
                Assert-MockCalled Invoke-DrunkenADPrefixWrite -Times 0
            }
        }

        Context 'Invoke-ADUserDrinkDataDemo' {
            BeforeEach {
                Mock Set-ADUserDrinkProjection {}
            }

            It 'remains as a compatibility wrapper around Set-ADUserDrinkProjection' {
                Invoke-ADUserDrinkDataDemo -SamAccountName 'demo' -AttributeMap @{ 'Org-' = @('company') } -IncludeDefaultAttributeMap -Confirm:$false -PassThru

                Assert-MockCalled Set-ADUserDrinkProjection -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    $AttributeMap.Contains('Org-') -and
                    $IncludeDefaultAttributeMap -and
                    $PassThru
                }
            }
        }

        Context 'Update-ADUserDrinkAttribute' {
            BeforeEach {
                Mock New-DrunkenADWriteContext {
                    [pscustomobject]@{ Server = 'dc01.contoso.com'; RangeUpper = 256; ReadyForUserWrite = $true }
                }
                Mock Set-ADUserDrinkPrefixedData {}
            }

            It 'maps aligned prefix and value arrays into the safer PrefixMap shape' {
                Update-ADUserDrinkAttribute -SamAccountName 'demo' -Prefixes 'One-', 'Two-' -DrinkValues 'A', 'B'

                Assert-MockCalled Set-ADUserDrinkPrefixedData -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    ((@($PrefixMap['One-']) -join ',') -eq 'A') -and
                    ((@($PrefixMap['Two-']) -join ',') -eq 'B')
                }
            }

            It 'honors WhatIf at the wrapper layer' {
                Update-ADUserDrinkAttribute -SamAccountName 'demo' -Prefixes 'One-' -DrinkValues 'A' -WhatIf

                Assert-MockCalled Set-ADUserDrinkPrefixedData -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and $WhatIf -and
                    (@($PrefixMap['One-']) -join ',') -eq 'A'
                }
            }

            It 'rejects mismatched arrays before checking AD readiness' {
                Mock New-DrunkenADWriteContext {
                    throw 'AD readiness should not run for invalid local input.'
                }

                {
                    Update-ADUserDrinkAttribute -SamAccountName 'demo' -Prefixes 'One-', 'Two-', 'Three-' -DrinkValues 'A', 'B' -Confirm:$false
                } | Should -Throw '*counts must match*'

                Assert-MockCalled New-DrunkenADWriteContext -Times 0
                Assert-MockCalled Set-ADUserDrinkPrefixedData -Times 0
            }

            It 'uses AutoConfirm to suppress wrapper confirmation prompts' {
                $previousConfirmPreference = $ConfirmPreference
                try {
                    $ConfirmPreference = 'Low'
                    Update-ADUserDrinkAttribute -SamAccountName 'demo' -Prefixes 'One-' -DrinkValues 'A' -AutoConfirm
                }
                finally {
                    $ConfirmPreference = $previousConfirmPreference
                }

                Assert-MockCalled Set-ADUserDrinkPrefixedData -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    ((@($PrefixMap['One-']) -join ',') -eq 'A') -and
                    ($Confirm -eq $false)
                }
            }
        }
    }
}
