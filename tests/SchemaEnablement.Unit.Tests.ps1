$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../DrunkenAD/DrunkenAD.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Describe 'Enable-ADDrinkAttributeOnUserClass admin script' {
    BeforeAll {
        $script:SchemaEnablementUnitOriginalFunctions = @{}
        $stubDefinitions = @{
            'Get-ADForest' = {
                param(
                    $Server,
                    $ErrorAction
                )

                throw 'Get-ADForest test stub should be configured by the current test.'
            }
            'Get-ADDomain' = {
                param(
                    $Server,
                    $ErrorAction
                )

                throw 'Get-ADDomain test stub should be configured by the current test.'
            }
            'Set-ADObject' = {
                param(
                    $Identity,
                    $Server,
                    $Add,
                    $ErrorAction
                )

                throw 'Set-ADObject test stub should be configured by the current test.'
            }
        }

        foreach ($functionName in $stubDefinitions.Keys) {
            $functionPath = 'Function:\global:{0}' -f $functionName
            $existingFunction = Get-Item -LiteralPath $functionPath -ErrorAction SilentlyContinue
            if ($existingFunction) {
                $script:SchemaEnablementUnitOriginalFunctions[$functionName] = $existingFunction.ScriptBlock
            }

            Set-Item -LiteralPath $functionPath -Value $stubDefinitions[$functionName]
        }

        $script:enablementScriptPath = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/Enable-ADDrinkAttributeOnUserClass.ps1'
        . $script:enablementScriptPath
    }

    AfterAll {
        foreach ($functionName in @('Get-ADForest', 'Get-ADDomain', 'Set-ADObject')) {
            $functionPath = 'Function:\global:{0}' -f $functionName
            if ($script:SchemaEnablementUnitOriginalFunctions.ContainsKey($functionName)) {
                Set-Item -LiteralPath $functionPath -Value $script:SchemaEnablementUnitOriginalFunctions[$functionName]
            }
            else {
                Remove-Item -LiteralPath $functionPath -ErrorAction SilentlyContinue
            }
        }
    }

    BeforeEach {
        Mock Import-Module {}
        Mock Start-Sleep {}
        Mock Get-ADForest {
            [pscustomobject]@{
                RootDomain   = 'lab.contoso.com'
                SchemaMaster = 'dc01.lab.contoso.com'
            }
        }
        Mock Get-ADDomain {
            [pscustomobject]@{
                DNSRoot = 'lab.contoso.com'
            }
        }
    }

    It 'exposes Confirm and WhatIf on the executable script entrypoint' {
        $scriptCommand = Get-Command -Name $script:enablementScriptPath -ErrorAction Stop

        $scriptCommand.Parameters.Keys | Should -Contain 'Confirm'
        $scriptCommand.Parameters.Keys | Should -Contain 'WhatIf'
    }

    It 'reports preflight information without writing by default' {
        Mock Test-ADDrinkAttributeReadyForUserWrite {
            [pscustomobject]@{
                Enabled                    = $true
                AllowedOnUserClass         = $false
                ReadyForUserWrite          = $false
                BlockingReason             = 'NotAllowedOnUserClass'
                BlockingMessage            = "The 'drink' attribute exists in the target Active Directory schema but is not allowed on the Active Directory user class."
                UserClassDistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=contoso,DC=com'
            }
        }
        Mock Set-ADObject {}

        $result = Enable-ADDrinkAttributeOnUserClass -Server 'dc01.lab.contoso.com'

        $result.Status | Should -Be 'Preview'
        $result.ApplyRequested | Should -BeFalse
        $result.TargetIsSchemaMaster | Should -BeTrue
        Assert-MockCalled Set-ADObject -Times 0
    }

    It 'refuses apply when the target server is not the schema master' {
        Mock Test-ADDrinkAttributeReadyForUserWrite {
            [pscustomobject]@{
                Enabled                    = $true
                AllowedOnUserClass         = $false
                ReadyForUserWrite          = $false
                BlockingReason             = 'NotAllowedOnUserClass'
                BlockingMessage            = "The 'drink' attribute exists in the target Active Directory schema but is not allowed on the Active Directory user class."
                UserClassDistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=contoso,DC=com'
            }
        }

        {
            Enable-ADDrinkAttributeOnUserClass -Server 'dc02.lab.contoso.com' -Apply -ExpectedForestRoot 'lab.contoso.com' -ExpectedDomainDnsRoot 'lab.contoso.com' -ExpectedSchemaMaster 'dc01.lab.contoso.com' -Confirm:$false
        } | Should -Throw '*schema master*'
    }

    It 'returns a no-op report when drink is already allowed on the user class' {
        Mock Test-ADDrinkAttributeReadyForUserWrite {
            [pscustomobject]@{
                Enabled                    = $true
                AllowedOnUserClass         = $true
                ReadyForUserWrite          = $true
                BlockingReason             = $null
                BlockingMessage            = $null
                UserClassDistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=contoso,DC=com'
            }
        }
        Mock Set-ADObject {}

        $result = Enable-ADDrinkAttributeOnUserClass -Server 'dc01.lab.contoso.com' -Apply -ExpectedForestRoot 'lab.contoso.com' -ExpectedDomainDnsRoot 'lab.contoso.com' -ExpectedSchemaMaster 'dc01.lab.contoso.com' -Confirm:$false

        $result.Status | Should -Be 'AlreadyReady'
        $result.Applied | Should -BeFalse
        Assert-MockCalled Set-ADObject -Times 0
    }

    It 'applies the mayContain update and verifies readiness after success' {
        $script:readinessCallCount = 0
        Mock Test-ADDrinkAttributeReadyForUserWrite {
            $script:readinessCallCount++

            if ($script:readinessCallCount -eq 1) {
                [pscustomobject]@{
                    Enabled                    = $true
                    AllowedOnUserClass         = $false
                    ReadyForUserWrite          = $false
                    BlockingReason             = 'NotAllowedOnUserClass'
                    BlockingMessage            = "The 'drink' attribute exists in the target Active Directory schema but is not allowed on the Active Directory user class."
                    UserClassDistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=contoso,DC=com'
                }
                return
            }

            [pscustomobject]@{
                Enabled                    = $true
                AllowedOnUserClass         = $true
                ReadyForUserWrite          = $true
                BlockingReason             = $null
                BlockingMessage            = $null
                UserClassDistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=contoso,DC=com'
            }
        }
        Mock Set-ADObject {}

        $result = Enable-ADDrinkAttributeOnUserClass -Server 'dc01.lab.contoso.com' -Apply -ExpectedForestRoot 'lab.contoso.com' -ExpectedDomainDnsRoot 'lab.contoso.com' -ExpectedSchemaMaster 'dc01.lab.contoso.com' -Confirm:$false

        $result.Status | Should -Be 'Applied'
        $result.Applied | Should -BeTrue
        $result.After.ReadyForUserWrite | Should -BeTrue
        Assert-MockCalled Set-ADObject -Times 1 -Exactly -ParameterFilter {
            $Identity -eq 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=contoso,DC=com' -and
            $Server -eq 'dc01.lab.contoso.com' -and
            $Add['mayContain'] -eq 'drink'
        }
    }
}
