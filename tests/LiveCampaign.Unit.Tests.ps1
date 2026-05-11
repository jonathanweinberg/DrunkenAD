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
            ForEach-Object { [System.IO.Path]::GetRelativePath($projectRoot, $_.FullName) })
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

    It 'keeps public live campaign docs host-method neutral' {
        $forbiddenPatterns = @(
            '(?i)\bparallels\b'
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
