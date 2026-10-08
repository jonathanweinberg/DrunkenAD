Describe 'DrunkenAD release readiness' {
    BeforeAll {
        $script:projectRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:releaseScriptPath = Join-Path -Path $script:projectRoot -ChildPath 'scripts/Test-DrunkenADRelease.ps1'
        $script:testRunnerPath = Join-Path -Path $script:projectRoot -ChildPath 'tests/Invoke-DrunkenADTests.ps1'
        $script:docsScriptPath = Join-Path -Path $script:projectRoot -ChildPath 'scripts/Test-DrunkenADDocs.ps1'
        $script:architectureMapScriptPath = Join-Path -Path $script:projectRoot -ChildPath 'scripts/Test-DrunkenADArchitectureMap.ps1'
        $script:manifestPath = Join-Path -Path $script:projectRoot -ChildPath 'DrunkenAD/DrunkenAD.psd1'
        $script:manifest = Test-ModuleManifest -Path $script:manifestPath
    }

    It 'has a release-readiness script that does not publish artifacts' {
        Test-Path -LiteralPath $script:releaseScriptPath -PathType Leaf | Should -BeTrue

        $releaseScriptContent = Get-Content -LiteralPath $script:releaseScriptPath -Raw
        $releaseScriptContent | Should -Match 'Test-DrunkenADSyntax'
        $releaseScriptContent | Should -Match 'Test-DrunkenADDocs'
        $releaseScriptContent | Should -Not -Match 'Publish-Module'
    }

    It 'derives the current release version from the manifest in the release gate' {
        $releaseScriptContent = Get-Content -LiteralPath $script:releaseScriptPath -Raw
        $releaseScriptContent | Should -Match '\$releaseVersion\s*=\s*\$manifest\.Version\.ToString\(\)'
        $releaseScriptContent | Should -Not -Match 'Expected module version 0\.13\.0'
        $releaseScriptContent | Should -Not -Match 'ReleaseNotes must describe the 0\.13\.0 release'
    }

    It 'loads only the pinned Pester runtime and explicitly trusted test files' {
        $releaseScriptContent = Get-Content -LiteralPath $script:releaseScriptPath -Raw
        $runnerContent = Get-Content -LiteralPath $script:testRunnerPath -Raw

        $releaseScriptContent | Should -Not -Match 'Add-DrunkenADLocalPesterCache|tests/Live/results|PSModulePath'
        $runnerContent | Should -Not -Match 'Add-DrunkenADLocalPesterCache|tests/Live/results|PSModulePath|MinimumVersion'
        $runnerContent | Should -Match 'RequiredVersion\s+\$requiredPesterVersion'
        $runnerContent | Should -Match "\[version\]'5\.7\.1'"
        $runnerContent | Should -Not -Match '\$configuration\.Run\.Path\s*=\s*\$PSScriptRoot'

        foreach ($trustedTestName in @(
            'DrunkenAD.Unit.Tests.ps1',
            'Help.Unit.Tests.ps1',
            'LiveCampaign.Unit.Tests.ps1',
            'Release.Unit.Tests.ps1',
            'SchemaEnablement.Unit.Tests.ps1',
            'DrunkenAD.Integration.Tests.ps1'
        )) {
            $runnerContent | Should -Match ([regex]::Escape($trustedTestName))
        }
    }

    It 'keeps release metadata consistent with the declared module version' {
        $releaseVersion = $script:manifest.Version.ToString()
        $releaseVersion | Should -Match '^\d+\.\d+\.\d+(\.\d+)?$'
        $script:manifest.PrivateData.PSData.ProjectUri | Should -Be 'https://github.com/jonathanweinberg/DrunkenAD'
        $script:manifest.PrivateData.PSData.ReleaseNotes | Should -Match ([regex]::Escape($releaseVersion))
        $aboutHelpSuffix = 'en-US/about_DrunkenAD.help.txt'
        @($script:manifest.FileList | Where-Object {
            ($_ -replace '\\', '/').EndsWith($aboutHelpSuffix, [System.StringComparison]::OrdinalIgnoreCase)
        }) | Should -Not -BeNullOrEmpty
    }

    It 'records release notes in the changelog' {
        $changelogPath = Join-Path -Path $script:projectRoot -ChildPath 'CHANGELOG.md'

        Test-Path -LiteralPath $changelogPath -PathType Leaf | Should -BeTrue
        $content = Get-Content -LiteralPath $changelogPath -Raw
        $content | Should -Match ('(?m)^## ' + [regex]::Escape($script:manifest.Version.ToString()) + '\s*$')
        $content | Should -Match '## 0.13.1'
        $content | Should -Match '## 0.13.0'
        $content | Should -Match '## 0.12.1'
        $content | Should -Match '## 0.12.0'
        $content | Should -Match '## 0.11.0'
    }

    It 'lists the complete distributable module contents' {
        $moduleRoot = Split-Path $script:manifestPath -Parent
        $manifestData = Import-PowerShellDataFile $script:manifestPath
        $actualFiles = @(Get-ChildItem $moduleRoot -Recurse -File | ForEach-Object {
            $_.FullName.Substring($moduleRoot.Length + 1) -replace '\\', '/'
        } | Sort-Object)
        @(Compare-Object $actualFiles @($manifestData.FileList | Sort-Object)) | Should -BeNullOrEmpty
    }

    It 'returns a failing process exit code when Pester discovery fails' {
        $testRoot = Join-Path $TestDrive 'runner/tests'
        New-Item $testRoot -ItemType Directory -Force | Out-Null
        $runnerCopy = Join-Path $testRoot 'Invoke-DrunkenADTests.ps1'
        Copy-Item $script:testRunnerPath $runnerCopy
        foreach ($name in @(
            'DrunkenAD.Unit.Tests.ps1', 'Help.Unit.Tests.ps1', 'LiveCampaign.Unit.Tests.ps1',
            'Release.Unit.Tests.ps1', 'SchemaEnablement.Unit.Tests.ps1',
            'SchemaStatus.Unit.Tests.ps1', 'WriteOperation.Unit.Tests.ps1',
            'DrunkenAD.Integration.Tests.ps1'
        )) {
            Set-Content (Join-Path $testRoot $name) "Describe 'Fixture' { It 'passes' { 1 | Should -Be 1 } }"
        }
        Set-Content (Join-Path $testRoot 'DrunkenAD.Unit.Tests.ps1') "throw 'Synthetic discovery failure'"
        $pesterPath = (Get-Module Pester).Path -replace 'Pester\.psm1$', 'Pester.psd1'
        $processPath = (Get-Process -Id $PID).Path
        $savedErrorPreference = $ErrorActionPreference
        try {
            # Windows PowerShell turns redirected native stderr into ErrorRecords.
            $ErrorActionPreference = 'Continue'
            $output = & $processPath -NoLogo -NoProfile -File $runnerCopy -PesterManifestPath $pesterPath -Output None 2>&1
            $processExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedErrorPreference
        }
        $processExitCode | Should -Not -Be 0
        ($output | Out-String) | Should -Match 'Pester result was Failed'
    }

    It 'runs architecture map validation from documentation hygiene' {
        Test-Path -LiteralPath $script:docsScriptPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $script:architectureMapScriptPath -PathType Leaf | Should -BeTrue

        $docsScriptContent = Get-Content -LiteralPath $script:docsScriptPath -Raw
        $docsScriptContent | Should -Match 'Test-DrunkenADArchitectureMap'
    }

    It 'keeps the architecture map validator focused on atlas contract checks' {
        Test-Path -LiteralPath $script:architectureMapScriptPath -PathType Leaf | Should -BeTrue

        $validatorContent = Get-Content -LiteralPath $script:architectureMapScriptPath -Raw
        $validatorContent | Should -Match 'drunkenad-architecture-map\.json'
        $validatorContent | Should -Match 'drunkenad-architecture-map\.html'
        $validatorContent | Should -Match 'ConvertFrom-Json'
        $validatorContent | Should -Match 'Test-ModuleManifest'
    }
}

Describe 'DrunkenAD integration coverage shape' {
    BeforeAll {
        $integrationPath = Join-Path -Path $PSScriptRoot -ChildPath 'DrunkenAD.Integration.Tests.ps1'
        $tokens = $null
        $errors = $null
        $script:integrationAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $integrationPath,
            [ref]$tokens,
            [ref]$errors
        )
        $script:integrationParseErrors = $errors
    }

    It 'includes opt-in CSV ingestion and projection live coverage' {
        $script:integrationParseErrors | Should -BeNullOrEmpty

        $testNames = @(
            $script:integrationAst.FindAll(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -eq 'It'
                },
                $true
            ) | ForEach-Object { $_.CommandElements[1].Extent.Text.Trim("'`"") }
        )

        $testNames | Should -Contain 'imports CSV drink data and reads back mapped namespaces'
        $testNames | Should -Contain 'projects AD attributes into drink namespaces'
    }
}
