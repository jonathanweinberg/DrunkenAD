Describe 'Invoke-DrunkenADLiveCampaign portability' {
    BeforeAll {
        $liveCampaignScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'Live/Invoke-DrunkenADLiveCampaign.ps1'
        $script:liveCampaignTokens = $null
        $script:liveCampaignParseErrors = $null
        $script:liveCampaignAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $liveCampaignScriptPath,
            [ref]$script:liveCampaignTokens,
            [ref]$script:liveCampaignParseErrors
        )
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
}
