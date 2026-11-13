Describe 'Invoke-DrunkenADLiveCampaign portability' {
    BeforeAll {
        $projectRoot = Split-Path -Path $PSScriptRoot -Parent
        $liveCampaignScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Live/Invoke-DrunkenADLiveCampaign.ps1'
        $guestCampaignScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Live/Invoke-DrunkenADGuestCampaign.ps1'
        $liveValidationDocPath = Join-Path -Path $projectRoot -ChildPath 'docs/LIVE-VALIDATION.md'
        $hostMethodsDocPath = Join-Path -Path $projectRoot -ChildPath 'docs/LIVE-CAMPAIGN-HOSTS.md'
        $script:liveCampaignTokens = $null
        $script:liveCampaignParseErrors = $null
        $script:liveCampaignAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $liveCampaignScriptPath,
            [ref]$script:liveCampaignTokens,
            [ref]$script:liveCampaignParseErrors
        )
        $script:guestCampaignTokens = $null
        $script:guestCampaignParseErrors = $null
        $script:guestCampaignAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $guestCampaignScriptPath,
            [ref]$script:guestCampaignTokens,
            [ref]$script:guestCampaignParseErrors
        )
        $script:liveCampaignContent = Get-Content -LiteralPath $liveCampaignScriptPath -Raw
        $script:guestCampaignContent = Get-Content -LiteralPath $guestCampaignScriptPath -Raw
        $script:liveValidationDocContent = Get-Content -LiteralPath $liveValidationDocPath -Raw
        $script:hostMethodsDocPath = $hostMethodsDocPath
        $publicDocPaths = @(
            'README.md'
            'CHANGELOG.md'
            'docs/README.md'
            'docs/TESTING.md'
            'docs/LIVE-VALIDATION.md'
            'docs/OPERATIONS.md'
        )
        $publicDocPaths += @(Get-ChildItem -LiteralPath (Join-Path -Path $projectRoot -ChildPath 'docs/issues') -Filter '*.md' |
            ForEach-Object { 'docs/issues/{0}' -f $_.Name })
        $script:publicLiveCampaignDocContent = ($publicDocPaths | ForEach-Object {
            Get-Content -LiteralPath (Join-Path -Path $projectRoot -ChildPath $_) -Raw
        }) -join [Environment]::NewLine
    }

    It 'does not default VmWrapperPath to a user-specific absolute path' {
        $script:liveCampaignParseErrors | Should -BeNullOrEmpty

        $vmWrapperParameter = $script:liveCampaignAst.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'VmWrapperPath' }

        $vmWrapperParameter | Should -Not -BeNullOrEmpty
        $vmWrapperParameter.DefaultValue.Extent.Text | Should -Be '$null'
    }

    It 'defines a resolver for the VM wrapper path' {
        $resolver = $script:liveCampaignAst.FindAll(
            {
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq 'Resolve-DrunkenADVmWrapperPath'
            },
            $true
        )

        $resolver | Should -Not -BeNullOrEmpty
    }

    It 'accepts a campaign profile on both host and guest live campaign scripts' {
        $script:guestCampaignParseErrors | Should -BeNullOrEmpty

        foreach ($ast in @($script:liveCampaignAst, $script:guestCampaignAst)) {
            $parameter = $ast.ParamBlock.Parameters |
                Where-Object { $_.Name.VariablePath.UserPath -eq 'CampaignProfile' }

            $parameter | Should -Not -BeNullOrEmpty
            $parameter.Attributes.TypeName.Name | Should -Contain 'ValidateSet'
            $parameter.Extent.Text | Should -Match "'Quick'"
            $parameter.Extent.Text | Should -Match "'Standard'"
            $parameter.Extent.Text | Should -Match "'Full'"
            $parameter.DefaultValue.Extent.Text | Should -Be "'Full'"
        }
    }

    It 'requires bounded root scope and rollback evidence for the guest campaign' {
        $rootOuParameter = $script:guestCampaignAst.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'RootOuName' }
        $snapshotNameParameter = $script:guestCampaignAst.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'SnapshotName' }
        $snapshotIdParameter = $script:guestCampaignAst.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'SnapshotId' }

        $rootOuParameter.Attributes.TypeName.Name | Should -Contain 'ValidatePattern'
        $snapshotNameParameter.Extent.Text | Should -Match 'Mandatory\s*=\s*\$true'
        $snapshotIdParameter.Extent.Text | Should -Match 'Mandatory\s*=\s*\$true'
    }

    It 'allows a guest WhatIf preview without requiring the seed password' {
        $confirmationIndex = $script:guestCampaignContent.IndexOf('$PSCmdlet.ShouldProcess')
        $passwordCheckIndex = $script:guestCampaignContent.IndexOf('if ([string]::IsNullOrWhiteSpace($env:DRUNKENAD_SEED_PASSWORD))')

        $confirmationIndex | Should -BeGreaterOrEqual 0
        $passwordCheckIndex | Should -BeGreaterThan $confirmationIndex
    }

    It 'allows the inline smoke assertion to expect an empty value set' {
        $assertionFunction = $script:guestCampaignAst.FindAll(
            {
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq 'Assert-DrinkValuesMatch'
            },
            $true
        ) | Select-Object -First 1
        $expectedParameter = $assertionFunction.Body.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'Expected' }

        $assertionFunction | Should -Not -BeNullOrEmpty
        $expectedParameter.Attributes.TypeName.Name | Should -Contain 'AllowEmptyCollection'
    }

    It 'validates exact manifest and CSV identities before any campaign mutation' {
        $script:guestCampaignContent | Should -Match 'function Assert-SeedIdentitySetsMatch'
        $script:guestCampaignContent | Should -Match '(?s)Assert-SeedIdentitySetsMatch.+foreach \(\$ouDn'
        $script:guestCampaignContent | Should -Match 'duplicate.*SamAccountName|SamAccountName.*duplicate'
    }

    It 'never prunes unexpected users or adopts users outside the campaign root' {
        $script:guestCampaignContent | Should -Not -Match '\bRemove-ADObject\b'
        $script:guestCampaignContent | Should -Match 'Unexpected.*campaign root|campaign root.*unexpected'
        $script:guestCampaignContent | Should -Match 'function ConvertTo-DrunkenADLdapFilterValue'
        $script:guestCampaignContent | Should -Match 'Set-ManagedSeedUser.+-SearchBaseDn\s+\$ouLayout\[''Root''\]'
        $script:guestCampaignContent | Should -Match '\$objectChanged\s*=\s*\$true'
    }

    It 'uses profile-sized immutable run inputs and safely quotes guest arguments' {
        $seedCountParameter = $script:liveCampaignAst.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'SeedCount' }

        $seedCountParameter | Should -BeNullOrEmpty
        $script:liveCampaignContent | Should -Match '\$runDataDirectory'
        $script:liveCampaignContent | Should -Match '-OutputDirectory\s+\$runDataDirectory'
        $script:liveCampaignContent | Should -Match 'function ConvertTo-PowerShellSingleQuotedLiteral'
    }

    It 'keeps public live campaign docs host-method neutral' {
        $legacyVendorPattern = '(?i)\b{0}\b' -f ('para' + 'llels')
        $forbiddenPatterns = @(
            $legacyVendorPattern
            '\bprlctl\b'
            'WindowsServer2025_ADDNS'
            '\\\\psf'
            'DrunkenAD_CODEX'
            'Invoke-WindowsAddnsGuestPowerShell'
        )

        foreach ($pattern in $forbiddenPatterns) {
            $script:publicLiveCampaignDocContent | Should -Not -Match $pattern
        }
    }

    It 'documents the generic host-method contract for future live campaign implementations' {
        Test-Path -LiteralPath $script:hostMethodsDocPath -PathType Leaf | Should -BeTrue
        $hostMethodsDocContent = Get-Content -LiteralPath $script:hostMethodsDocPath -Raw

        $hostMethodsDocContent | Should -Match 'Host Wrapper Responsibilities'
        $hostMethodsDocContent | Should -Match 'Snapshot Or Rollback Point'
        $hostMethodsDocContent | Should -Match 'Guest Or Remote Workspace'
        $hostMethodsDocContent | Should -Match 'Result Collection'
        $hostMethodsDocContent | Should -Match 'Credential Handling'
    }

    It 'generates deterministic quick-profile seed data' {
        $outputDirectory = Join-Path -Path $TestDrive -ChildPath 'quick-seed'
        $seedScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Live/Export-DrunkenADSeedData.ps1'

        $result = & $seedScriptPath -SeedCount 30 -OutputDirectory $outputDirectory
        $manifest = Get-Content -LiteralPath $result.ManifestPath -Raw | ConvertFrom-Json
        $csvRows = Import-Csv -LiteralPath $result.CsvPath

        $result.SeedCount | Should -Be 30
        $manifest.Count | Should -Be 30
        $csvRows.Count | Should -Be 30
        @($manifest | Where-Object Region -eq 'NA').Count | Should -Be 10
        @($manifest | Where-Object Region -eq 'EMEA').Count | Should -Be 10
        @($manifest | Where-Object Region -eq 'APAC').Count | Should -Be 10
    }
}

Describe 'Isolated smoke account cleanup behavior' {
    BeforeAll {
        $path = Join-Path $PSScriptRoot 'Live/Invoke-DrunkenADGuestCampaign.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw 'Guest campaign failed to parse.' }
        foreach ($name in @('ConvertTo-DrunkenADLdapFilterValue', 'Remove-DrunkenADSmokeAccount', 'Test-DrinkValuesMatch', 'Assert-DrinkValuesMatch')) {
            $definition = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true) | Select-Object -First 1
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $script:cleanupOriginalFunctions = @{}
        foreach ($name in @('Remove-ADUser', 'Get-ADUser')) {
            $existingFunction = Get-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue
            if ($existingFunction) { $script:cleanupOriginalFunctions[$name] = $existingFunction.ScriptBlock }
        }
        function global:Remove-ADUser { param($Identity, $Server, $Confirm, $ErrorAction) throw 'Unmocked removal is forbidden.' }
        function global:Get-ADUser { param($LDAPFilter, $Server, $ErrorAction) throw 'Unmocked lookup is forbidden.' }
    }
    AfterAll {
        foreach ($name in @('Remove-ADUser', 'Get-ADUser')) {
            if ($script:cleanupOriginalFunctions.ContainsKey($name)) {
                Set-Item "Function:\global:$name" $script:cleanupOriginalFunctions[$name]
            }
            else { Remove-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue }
        }
    }
    BeforeEach {
        Mock Remove-ADUser {}
        Mock Get-ADUser { @() }
    }
    It 'removes only the captured identity and verifies absence on the same server' {
        Remove-DrunkenADSmokeAccount -DistinguishedName 'CN=isolated,OU=Tests,DC=example,DC=test' -Server 'dc.example.test'
        Should -Invoke Remove-ADUser -Times 1 -Exactly -ParameterFilter { $Identity -eq 'CN=isolated,OU=Tests,DC=example,DC=test' -and $Server -eq 'dc.example.test' }
        Should -Invoke Get-ADUser -Times 1 -Exactly -ParameterFilter { $LDAPFilter -eq '(distinguishedName=CN=isolated,OU=Tests,DC=example,DC=test)' -and $Server -eq 'dc.example.test' }
    }
    It 'reports a removal failure without attempting broader deletion' {
        Mock Remove-ADUser { throw 'Access denied' }
        { Remove-DrunkenADSmokeAccount -DistinguishedName 'CN=isolated,DC=example,DC=test' -Server 'dc.example.test' } | Should -Throw '*Smoke account cleanup failed*Access denied*'
        Should -Invoke Remove-ADUser -Times 1 -Exactly
        Should -Invoke Get-ADUser -Times 0 -Exactly
    }
    It 'executes the real script-local LDAP escaping helper during cleanup' {
        $dn = 'CN=isolated*(test)\name,DC=example,DC=test'
        Remove-DrunkenADSmokeAccount -DistinguishedName $dn -Server 'dc.example.test'
        Should -Invoke Get-ADUser -Times 1 -Exactly -ParameterFilter {
            $LDAPFilter -eq '(distinguishedName=CN=isolated\2a\28test\29\5cname,DC=example,DC=test)'
        }
        ConvertTo-DrunkenADLdapFilterValue -Value ([string][char]0) | Should -BeExactly '\00'
    }
    It 'compares individual values without delimiter collisions' {
        { Assert-DrinkValuesMatch -Actual @('A|B', 'C') -Expected @('A', 'B|C') -Message 'Mismatch' } | Should -Throw '*Mismatch*'
        { Assert-DrinkValuesMatch -Actual @('C', 'A|B') -Expected @('A|B', 'C') -Message 'Mismatch' } | Should -Not -Throw
        { Assert-DrinkValuesMatch -Actual @() -Expected @() -Message 'Mismatch' } | Should -Not -Throw
        { Assert-DrinkValuesMatch -Actual @('Case') -Expected @('case') -Message 'Mismatch' } | Should -Throw '*Mismatch*'
    }
    It 'runs the inline smoke path with script-local helpers in a fresh scope' {
        $definitions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('ConvertTo-DrunkenADLdapFilterValue', 'Remove-DrunkenADSmokeAccount', 'Test-DrinkValuesMatch', 'Assert-DrinkValuesMatch', 'New-SmokeValidationPassword', 'Invoke-DrunkenADSmokeValidation') }, $true) | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine
        $isolated = New-Module -ScriptBlock {
            param($Definitions)
            . ([scriptblock]::Create($Definitions))
            $script:DomainController = 'dc.example.test'
            $script:writeCount = 0
            $script:removed = $false
            function New-ADUser { param($Name, $SamAccountName, $UserPrincipalName, $AccountPassword, $Enabled, $EmployeeID, $OtherAttributes, $Path, $Server, $ErrorAction, [switch]$PassThru) [pscustomobject]@{ DistinguishedName = 'CN=isolated,OU=Tests,DC=example,DC=test' } }
            function Test-ADDrinkAttributeReadyForUserWrite { param($Server) $true }
            function Set-ADUserDrinkData { param($SamAccountName, $DataMap, $DomainController, $Confirm, $ErrorAction) $script:writeCount++ }
            function Remove-ADUserDrinkData { param($SamAccountName, $Prefixes, $DomainController, $Confirm, $ErrorAction) }
            function Get-ADUserDrinkData {
                param($SamAccountName, $Prefix, $DomainController)
                if ($Prefix -eq 'Keep-' -or -not $Prefix) { return 'Keep-Stable' }
                if ($script:writeCount -eq 1) { return 'Smoke[01]-First' }
                if ($script:writeCount -eq 2 -and $Prefix -eq 'Smoke[01]-') {
                    $script:writeCount++
                    return 'Smoke[01]-Second'
                }
            }
            function Remove-ADUser { param($Identity, $Server, $Confirm, $ErrorAction) $script:removed = $true }
            function Get-ADUser { param($LDAPFilter, $Server, $ErrorAction) if (-not $script:removed) { throw 'Absence checked before removal.' } }
        } -ArgumentList $definitions
        try {
            $result = & $isolated { Invoke-DrunkenADSmokeValidation -TestOuDn 'OU=Tests,DC=example,DC=test' -DnsRoot 'example.test' }
            $result.FailedCount | Should -Be 0
            $result.Lines[-1] | Should -Match 'removal was verified'
        }
        finally { Remove-Module $isolated -ErrorAction SilentlyContinue }
    }
    It 'reports an account still present after removal' {
        Mock Get-ADUser { [pscustomobject]@{ DistinguishedName = 'CN=isolated,DC=example,DC=test' } }
        { Remove-DrunkenADSmokeAccount -DistinguishedName 'CN=isolated,DC=example,DC=test' -Server 'dc.example.test' } | Should -Throw '*still present*'
        Should -Invoke Remove-ADUser -Times 1 -Exactly
    }
    It 'reports failure to verify absence rather than claiming cleanup succeeded' {
        Mock Get-ADUser { throw 'Directory unavailable' }
        { Remove-DrunkenADSmokeAccount -DistinguishedName 'CN=isolated,DC=example,DC=test' -Server 'dc.example.test' } | Should -Throw '*Smoke account cleanup failed*Directory unavailable*'
    }
}
