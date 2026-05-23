Describe 'DrunkenAD release readiness' {
    BeforeAll {
        $script:projectRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:releaseScriptPath = Join-Path -Path $script:projectRoot -ChildPath 'scripts/Test-DrunkenADRelease.ps1'
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

    It 'marks the module as the 0.13.2 release with publish-ready metadata' {
        $script:manifest.Version.ToString() | Should -Be '0.13.2'
        $script:manifest.PrivateData.PSData.ProjectUri | Should -Be 'https://github.com/jonathanweinberg/DrunkenAD'
        $script:manifest.PrivateData.PSData.ReleaseNotes | Should -Match '0.13.2'
        @($script:manifest.FileList | Where-Object { $_ -like '*/en-US/about_DrunkenAD.help.txt' }) | Should -Not -BeNullOrEmpty
    }

    It 'records release notes in the changelog' {
        $changelogPath = Join-Path -Path $script:projectRoot -ChildPath 'CHANGELOG.md'

        Test-Path -LiteralPath $changelogPath -PathType Leaf | Should -BeTrue
        $content = Get-Content -LiteralPath $changelogPath -Raw
        $content | Should -Match '## 0.13.2'
        $content | Should -Match '## 0.13.1'
        $content | Should -Match '## 0.13.0'
        $content | Should -Match '## 0.12.1'
        $content | Should -Match '## 0.12.0'
        $content | Should -Match '## 0.11.0'
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
