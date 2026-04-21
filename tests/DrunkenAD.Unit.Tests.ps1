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
                    $Replace
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
                $global:DrunkenADTest_GetADRootDSEHandler = { [pscustomobject]@{ SchemaNamingContext = 'CN=Schema,CN=Configuration,DC=contoso,DC=com' } }
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
                $global:DrunkenADTest_GetADRootDSEHandler = { [pscustomobject]@{ SchemaNamingContext = 'CN=Schema,CN=Configuration,DC=contoso,DC=com' } }
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
        }

        Context 'Set-ADUserDrinkPrefixedData' {
            BeforeEach {
                Mock Assert-ADDrinkAttributeReadyForUserWrite {}
                Mock Write-DrunkenADLog {}
                $global:DrunkenADTest_SetADUserCalls = @()
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
                $global:DrunkenADTest_SetADUserCalls[0]['Replace']['drink'] | Should -Contain 'Test[1]-new'
                $global:DrunkenADTest_SetADUserCalls[0]['Replace']['drink'] | Should -Contain 'Test1-old'
                $global:DrunkenADTest_SetADUserCalls[0]['Replace']['drink'] | Should -Contain 'Keep-me'
                $global:DrunkenADTest_SetADUserCalls[0]['Replace']['drink'] | Should -Not -Contain 'Test[1]-old'
            }

            It 'clears the attribute when all values are removed' {
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
                $global:DrunkenADTest_SetADUserCalls[0]['Clear'] | Should -Be 'drink'
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

            It 'normalizes preserved values to strings before calling Set-ADUser Replace' {
                $preservedValue = New-Object psobject
                $preservedValue | Add-Member -MemberType ScriptMethod -Name ToString -Value { 'Keep-me' } -Force

                Mock Resolve-DrunkenADUser {
                    [pscustomobject]@{
                        SamAccountName    = 'demo'
                        DistinguishedName = 'CN=Demo User,DC=contoso,DC=com'
                        drink             = @('Test[1]-old', $preservedValue)
                    }
                }

                Set-ADUserDrinkPrefixedData -SamAccountName 'demo' -PrefixMap @{ 'Test[1]-' = @('new') } -Confirm:$false

                $replaceValues = @($global:DrunkenADTest_SetADUserCalls[0]['Replace']['drink'])

                $replaceValues | Should -Be @('Keep-me', 'Test[1]-new')
                ($replaceValues | ForEach-Object { $_.GetType().FullName } | Sort-Object -Unique) | Should -Be @('System.String')
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
                Mock Assert-ADDrinkAttributeReadyForUserWrite {
                    throw "The 'drink' attribute exists in the target Active Directory schema but is not allowed on the Active Directory user class."
                }

                {
                    Set-ADUserDrinkPrefixedData -SamAccountName 'demo' -PrefixMap @{ 'Test-' = @('new') } -Confirm:$false
                } | Should -Throw '*not allowed on the Active Directory user class*'
            }
        }

        Context 'Set-ADUserDrinkData' {
            BeforeEach {
                Mock Assert-ADDrinkAttributeReadyForUserWrite {}
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

                Assert-MockCalled Set-ADUserDrinkPrefixedData -Times 0
            }
        }

        Context 'Remove-ADUserDrinkData' {
            BeforeEach {
                Mock Assert-ADDrinkAttributeReadyForUserWrite {}
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

                Assert-MockCalled Set-ADUserDrinkData -Times 0
            }
        }

        Context 'Set-ADUserDrinkProjection' {
            BeforeEach {
                Mock Assert-ADDrinkAttributeReadyForUserWrite {}
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
                    }
                }
                Mock Set-ADUserDrinkData {
                    @('Profile-samAccountName=demo')
                }
            }

            It 'uses the built-in default attribute map when none is supplied' {
                $result = Set-ADUserDrinkProjection -SamAccountName 'demo' -Confirm:$false -PassThru

                Assert-MockCalled Resolve-DrunkenADUser -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    (@($Properties) -contains 'samAccountName') -and
                    (@($Properties) -contains 'userPrincipalName') -and
                    (@($Properties) -contains 'employeeID') -and
                    (@($Properties) -contains 'mail') -and
                    (@($Properties) -contains 'pager')
                }

                Assert-MockCalled Set-ADUserDrinkData -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    ((@($DataMap['Profile-']) -join ',') -eq 'samAccountName=demo') -and
                    ((@($DataMap['Identity-']) -join ',') -eq 'userPrincipalName=demo@contoso.com') -and
                    ((@($DataMap['Meta-']) -join ',') -eq 'employeeID=123456') -and
                    ((@($DataMap['Routing-']) -join ',') -eq 'mail=demo@contoso.com') -and
                    ((@($DataMap['Notify-']) -join ',') -eq 'pager=555-0100')
                }

                $result.SamAccountName | Should -Be 'demo'
                $result.DataMap.Contains('Profile-') | Should -BeTrue
            }

            It 'replaces the default projection map when a custom map is supplied' {
                Set-ADUserDrinkProjection -SamAccountName 'demo' -AttributeMap @{ 'Org-' = @('department', 'title') } -Confirm:$false | Out-Null

                Assert-MockCalled Resolve-DrunkenADUser -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    (@($Properties).Count -eq 2) -and
                    (@($Properties) -contains 'department') -and
                    (@($Properties) -contains 'title')
                }

                Assert-MockCalled Set-ADUserDrinkData -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    $DataMap.Count -eq 1 -and
                    ((@($DataMap['Org-']) | Sort-Object) -join ',') -eq 'department=Identity,title=Engineer'
                }
            }

            It 'merges a custom map with the default projection map when requested' {
                Set-ADUserDrinkProjection -SamAccountName 'demo' -AttributeMap @{ 'Org-' = @('company') } -IncludeDefaultAttributeMap -Confirm:$false | Out-Null

                Assert-MockCalled Resolve-DrunkenADUser -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'demo' -and
                    (@($Properties) -contains 'company') -and
                    (@($Properties) -contains 'samAccountName')
                }

                Assert-MockCalled Set-ADUserDrinkData -Times 1 -Exactly -ParameterFilter {
                    $DataMap.Contains('Org-') -and
                    $DataMap.Contains('Profile-') -and
                    ((@($DataMap['Org-']) -join ',') -eq 'company=Contoso')
                }
            }

            It 'honors WhatIf at the projection layer' {
                Set-ADUserDrinkProjection -SamAccountName 'demo' -WhatIf

                Assert-MockCalled Set-ADUserDrinkData -Times 0
            }
        }

        Context 'Import-ADUserDrinkCsvData' {
            BeforeEach {
                Mock Test-Path { $true }
                Mock Assert-ADDrinkAttributeReadyForUserWrite {}
                Mock Import-Csv {
                    @(
                        [pscustomobject]@{
                            SamAccountName = 'alice'
                            ProfileTier    = 'Gold'
                            Flags          = 'Enabled;Audited'
                        }
                    )
                }
                Mock Set-ADUserDrinkData {
                    @('Profile-Tier=Gold', 'Flags-Enabled', 'Flags-Audited')
                }
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

                $result = Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com'

                Assert-MockCalled Assert-ADDrinkAttributeReadyForUserWrite -Times 1 -Exactly -ParameterFilter {
                    $Server -eq 'dc01.contoso.com'
                }

                Assert-MockCalled Set-ADUserDrinkData -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'alice' -and
                    $DomainController -eq 'dc01.contoso.com' -and
                    ((@($DataMap['Profile-']) -join ',') -eq 'Tier=Gold') -and
                    ((@($DataMap['Flags-']) | Sort-Object) -join ',') -eq 'Audited,Enabled' -and
                    $PassThru -and
                    ($Confirm -eq $false)
                }

                $result.ConfigSource | Should -Be 'NamespaceMap'
                $result.Namespaces | Should -Contain 'Profile-'
                $result.Namespaces | Should -Contain 'Flags-'
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

                Assert-MockCalled Set-ADUserDrinkData -Times 1 -Exactly -ParameterFilter {
                    $SamAccountName -eq 'alice' -and
                    ((@($DataMap['Tenant-']) -join ',') -eq 'Id=TEN-001')
                }
            }

            It 'honors WhatIf and skips the underlying write during CSV import' {
                $namespaceMap = @{
                    'Profile-' = @(
                        @{ Column = 'ProfileTier'; Label = 'Tier' }
                    )
                }

                $result = Import-ADUserDrinkCsvData -CsvPath '/tmp/users.csv' -NamespaceMap $namespaceMap -DomainController 'dc01.contoso.com' -WhatIf

                Assert-MockCalled Set-ADUserDrinkData -Times 0
                @($result.FinalDrinkValues).Count | Should -Be 0
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
                Mock Assert-ADDrinkAttributeReadyForUserWrite {}
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

                Assert-MockCalled Set-ADUserDrinkPrefixedData -Times 0
            }
        }
    }
}
