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
        Mock Set-ADObject {}
        Mock Update-DrunkenADSchemaCache {}
        $script:applyParams = @{
            Server                = 'dc01.lab.example.test'
            Apply                 = $true
            ExpectedForestRoot    = 'lab.example.test'
            ExpectedDomainDnsRoot = 'lab.example.test'
            ExpectedSchemaMaster  = 'dc01.lab.example.test'
            Confirm               = $false
        }
        Mock Test-ADDrinkAttributeReadyForUserWrite {
            [pscustomobject]@{
                Enabled                    = $true
                AllowedOnUserClass         = $false
                ReadyForUserWrite          = $false
                BlockingReason             = 'NotAllowedOnUserClass'
                BlockingMessage            = "The 'drink' attribute is not allowed on the Active Directory user class."
                UserClassDistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=example,DC=test'
            }
        }
        Mock Get-ADForest {
            [pscustomobject]@{
                RootDomain   = 'lab.example.test'
                SchemaMaster = 'dc01.lab.example.test'
            }
        }
        Mock Get-ADDomain {
            [pscustomobject]@{
                DNSRoot = 'lab.example.test'
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
                UserClassDistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=example,DC=test'
            }
        }
        Mock Set-ADObject {}

        $result = Enable-ADDrinkAttributeOnUserClass -Server 'dc01.lab.example.test'

        $result.Status | Should -Be 'Preview'
        $result.ApplyRequested | Should -BeFalse
        $result.TargetIsSchemaMaster | Should -BeTrue
        Assert-MockCalled Set-ADObject -Times 0
        Assert-MockCalled Update-DrunkenADSchemaCache -Times 0
        Assert-MockCalled Test-ADDrinkAttributeReadyForUserWrite -Times 1 -Exactly
    }

    It 'refuses apply when the target server is not the schema master' {
        Mock Test-ADDrinkAttributeReadyForUserWrite {
            [pscustomobject]@{
                Enabled                    = $true
                AllowedOnUserClass         = $false
                ReadyForUserWrite          = $false
                BlockingReason             = 'NotAllowedOnUserClass'
                BlockingMessage            = "The 'drink' attribute exists in the target Active Directory schema but is not allowed on the Active Directory user class."
                UserClassDistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=example,DC=test'
            }
        }

        {
            Enable-ADDrinkAttributeOnUserClass -Server 'dc02.lab.example.test' -Apply -ExpectedForestRoot 'lab.example.test' -ExpectedDomainDnsRoot 'lab.example.test' -ExpectedSchemaMaster 'dc01.lab.example.test' -Confirm:$false
        } | Should -Throw '*schema master*'
        Assert-MockCalled Set-ADObject -Times 0
        Assert-MockCalled Update-DrunkenADSchemaCache -Times 0
    }

    It 'returns a no-op report when drink is already allowed on the user class' {
        Mock Test-ADDrinkAttributeReadyForUserWrite {
            [pscustomobject]@{
                Enabled                    = $true
                AllowedOnUserClass         = $true
                ReadyForUserWrite          = $true
                BlockingReason             = $null
                BlockingMessage            = $null
                UserClassDistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=example,DC=test'
            }
        }
        Mock Set-ADObject {}

        $reportPath = Join-Path $TestDrive 'already-ready.json'
        $result = Enable-ADDrinkAttributeOnUserClass @script:applyParams -ReportPath $reportPath

        $result.Status | Should -Be 'AlreadyReady'
        $result.Applied | Should -BeFalse
        Assert-MockCalled Set-ADObject -Times 0
        Assert-MockCalled Update-DrunkenADSchemaCache -Times 0
        (Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json).Status | Should -Be 'AlreadyReady'
    }

    It 'applies mayContain, refreshes the chosen schema master, then verifies readiness' {
        $script:readinessCallCount = 0
        $script:enablementOperations = New-Object 'System.Collections.Generic.List[string]'
        Mock Test-ADDrinkAttributeReadyForUserWrite {
            $script:readinessCallCount++
            $script:enablementOperations.Add('Readiness')

            if ($script:readinessCallCount -eq 1) {
                [pscustomobject]@{
                    Enabled                    = $true
                    AllowedOnUserClass         = $false
                    ReadyForUserWrite          = $false
                    BlockingReason             = 'NotAllowedOnUserClass'
                    BlockingMessage            = "The 'drink' attribute exists in the target Active Directory schema but is not allowed on the Active Directory user class."
                    UserClassDistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=example,DC=test'
                }
                return
            }

            [pscustomobject]@{
                Enabled                    = $true
                AllowedOnUserClass         = $true
                ReadyForUserWrite          = $true
                BlockingReason             = $null
                BlockingMessage            = $null
                UserClassDistinguishedName = 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=example,DC=test'
            }
        }
        Mock Set-ADObject { $script:enablementOperations.Add('Write') }
        Mock Update-DrunkenADSchemaCache { $script:enablementOperations.Add('Refresh') }

        $reportPath = Join-Path $TestDrive 'applied.json'
        $result = Enable-ADDrinkAttributeOnUserClass @script:applyParams -ReportPath $reportPath

        $result.Status | Should -Be 'Applied'
        $result.Applied | Should -BeTrue
        $result.After.ReadyForUserWrite | Should -BeTrue
        Assert-MockCalled Set-ADObject -Times 1 -Exactly -ParameterFilter {
            $Identity -eq 'CN=User,CN=Schema,CN=Configuration,DC=lab,DC=example,DC=test' -and
            $Server -eq 'dc01.lab.example.test' -and
            $Add['mayContain'] -eq 'drink'
        }
        Assert-MockCalled Update-DrunkenADSchemaCache -Times 1 -Exactly -ParameterFilter {
            $Server -eq 'dc01.lab.example.test'
        }
        Assert-MockCalled Test-ADDrinkAttributeReadyForUserWrite -Times 2 -Exactly -ParameterFilter {
            $Server -eq 'dc01.lab.example.test' -and $PassThru
        }
        Assert-MockCalled Start-Sleep -Times 0
        ($script:enablementOperations -join ',') | Should -Be 'Readiness,Write,Refresh,Readiness'
        $savedReport = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $savedReport.Status | Should -Be 'Applied'
        $savedReport.Before.ReadyForUserWrite | Should -BeFalse
        $savedReport.After.ReadyForUserWrite | Should -BeTrue
    }

    It 'writes the optional preview report without a schema write or refresh' {
        $reportPath = Join-Path $TestDrive 'preview/report.json'

        $result = Enable-ADDrinkAttributeOnUserClass -ReportPath $reportPath

        $result.Status | Should -Be 'Preview'
        $result.TargetServer | Should -Be 'dc01.lab.example.test'
        $savedReport = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $savedReport.Status | Should -Be 'Preview'
        $savedReport.Applied | Should -BeFalse
        $savedReport.TargetServer | Should -Be $result.TargetServer
        Assert-MockCalled Set-ADObject -Times 0
        Assert-MockCalled Update-DrunkenADSchemaCache -Times 0
    }

    It 'does not write schema, refresh the cache, or create a report under WhatIf' {
        $reportPath = Join-Path $TestDrive 'whatif.json'

        $result = Enable-ADDrinkAttributeOnUserClass @script:applyParams -WhatIf -ReportPath $reportPath

        $result.Status | Should -Be 'WhatIf'
        $result.ApplyRequested | Should -BeTrue
        $result.Applied | Should -BeFalse
        $result.After.ReadyForUserWrite | Should -BeFalse
        Test-Path -LiteralPath $reportPath | Should -BeFalse
        Assert-MockCalled Set-ADObject -Times 0
        Assert-MockCalled Update-DrunkenADSchemaCache -Times 0
        Assert-MockCalled Test-ADDrinkAttributeReadyForUserWrite -Times 1 -Exactly
    }

    It 'does not write or bind RootDSE through the executable <Status> entrypoint' -TestCases @(
        @{ ApplyMode = $false; UseWhatIf = $false; Status = 'Preview' }
        @{ ApplyMode = $true; UseWhatIf = $true; Status = 'WhatIf' }
    ) {
        param($ApplyMode, $UseWhatIf, $Status)
        Mock New-Object { throw 'RootDSE binding must not occur during preview or WhatIf.' } -ParameterFilter {
            $TypeName -eq 'System.DirectoryServices.DirectoryEntry'
        }
        $entryParams = $script:applyParams.Clone()
        $entryParams['Apply'] = $ApplyMode
        $entryParams['WhatIf'] = $UseWhatIf

        $result = & $script:enablementScriptPath @entryParams

        $result.Status | Should -Be $Status
        $result.Applied | Should -BeFalse
        Assert-MockCalled Set-ADObject -Times 0
        Assert-MockCalled New-Object -Times 0 -ParameterFilter {
            $TypeName -eq 'System.DirectoryServices.DirectoryEntry'
        }
        Assert-MockCalled Test-ADDrinkAttributeReadyForUserWrite -Times 1 -Exactly
    }

    It 'fails clearly after a cache refresh error without checking or reporting success' {
        Mock Update-DrunkenADSchemaCache { throw 'Refresh access denied.' }
        $reportPath = Join-Path $TestDrive 'refresh-failed.json'

        {
            Enable-ADDrinkAttributeOnUserClass @script:applyParams -ReportPath $reportPath
        } | Should -Throw "*update completed on 'dc01.lab.example.test'*schema cache refresh*schemaUpdateNow*failed*not been rolled back*readiness was not verified*Refresh access denied*"

        Test-Path -LiteralPath $reportPath | Should -BeFalse
        Assert-MockCalled Set-ADObject -Times 1 -Exactly
        Assert-MockCalled Update-DrunkenADSchemaCache -Times 1 -Exactly
        Assert-MockCalled Test-ADDrinkAttributeReadyForUserWrite -Times 1 -Exactly
    }

    It 'does not refresh or recheck when the schema write fails' {
        Mock Set-ADObject { throw 'Schema write denied.' }

        { Enable-ADDrinkAttributeOnUserClass @script:applyParams } | Should -Throw '*Schema write denied*'

        Assert-MockCalled Update-DrunkenADSchemaCache -Times 0
        Assert-MockCalled Test-ADDrinkAttributeReadyForUserWrite -Times 1 -Exactly
    }

    It 'still fails closed if readiness is false after a successful refresh' {
        { Enable-ADDrinkAttributeOnUserClass @script:applyParams } | Should -Throw '*still not ready*'

        Assert-MockCalled Set-ADObject -Times 1 -Exactly
        Assert-MockCalled Update-DrunkenADSchemaCache -Times 1 -Exactly
        Assert-MockCalled Test-ADDrinkAttributeReadyForUserWrite -Times 2 -Exactly
    }

    It 'does not write or refresh for invalid <Name>' -TestCases @(
        @{ Name = 'ExpectedForestRoot'; Value = ''; ErrorMessage = '*requires*' }
        @{ Name = 'ExpectedForestRoot'; Value = 'other.example.test'; ErrorMessage = '*Expected forest root*' }
        @{ Name = 'ExpectedDomainDnsRoot'; Value = 'other.example.test'; ErrorMessage = '*Expected domain DNS root*' }
        @{ Name = 'ExpectedSchemaMaster'; Value = 'dc02.lab.example.test'; ErrorMessage = '*Expected schema master*' }
    ) {
        param($Name, $Value, $ErrorMessage)
        $script:applyParams[$Name] = $Value

        { Enable-ADDrinkAttributeOnUserClass @script:applyParams } | Should -Throw $ErrorMessage

        Assert-MockCalled Set-ADObject -Times 0
        Assert-MockCalled Update-DrunkenADSchemaCache -Times 0
    }
}

Describe 'Update-DrunkenADSchemaCache RootDSE binding' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../scripts/Enable-ADDrinkAttributeOnUserClass.ps1')
    }

    BeforeEach {
        $script:rootDse = [pscustomobject]@{
            AuthenticationType = $null
            PropertyName       = $null
            PropertyValue      = $null
            FailureStage       = $null
            Operations         = (New-Object 'System.Collections.Generic.List[string]')
        }
        $script:rootDse | Add-Member -MemberType ScriptMethod -Name Put -Value {
            param($Name, $Value)
            $this.Operations.Add('Put')
            if ($this.FailureStage -eq 'Put') { throw 'RootDSE Put failed.' }
            $this.PropertyName = $Name
            $this.PropertyValue = $Value
        }
        $script:rootDse | Add-Member -MemberType ScriptMethod -Name SetInfo -Value {
            $this.Operations.Add('SetInfo')
            if ($this.FailureStage -eq 'SetInfo') { throw 'RootDSE SetInfo failed.' }
        }
        $script:rootDse | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
            $this.Operations.Add('Dispose')
        }
        Mock New-Object { $script:rootDse } -ParameterFilter {
            $TypeName -eq 'System.DirectoryServices.DirectoryEntry'
        }
    }

    It 'binds to the supplied server RootDSE and commits schemaUpdateNow with value 1' {
        Update-DrunkenADSchemaCache -Server 'dc09.lab.example.test'

        Assert-MockCalled New-Object -Times 1 -Exactly -ParameterFilter {
            $TypeName -eq 'System.DirectoryServices.DirectoryEntry' -and
            $ArgumentList.Count -eq 1 -and $ArgumentList[0] -eq 'LDAP://dc09.lab.example.test/RootDSE'
        }
        $script:rootDse.AuthenticationType | Should -Be ([System.DirectoryServices.AuthenticationTypes]::Secure)
        $script:rootDse.PropertyName | Should -Be 'schemaUpdateNow'
        $script:rootDse.PropertyValue | Should -Be 1
        ($script:rootDse.Operations -join ',') | Should -Be 'Put,SetInfo,Dispose'
    }

    It 'propagates <Stage> failure and disposes the connection' -TestCases @(
        @{ Stage = 'Put'; Operations = 'Put,Dispose' }
        @{ Stage = 'SetInfo'; Operations = 'Put,SetInfo,Dispose' }
    ) {
        param($Stage, $Operations)
        $script:rootDse.FailureStage = $Stage

        { Update-DrunkenADSchemaCache -Server 'dc09.lab.example.test' } | Should -Throw "*RootDSE $Stage failed*"

        ($script:rootDse.Operations -join ',') | Should -Be $Operations
    }

    It 'propagates construction failure without using a connection' {
        Mock New-Object { throw 'DirectoryEntry creation failed.' } -ParameterFilter {
            $TypeName -eq 'System.DirectoryServices.DirectoryEntry'
        }

        { Update-DrunkenADSchemaCache -Server 'dc09.lab.example.test' } | Should -Throw '*DirectoryEntry creation failed*'

        $script:rootDse.Operations.Count | Should -Be 0
    }
}
