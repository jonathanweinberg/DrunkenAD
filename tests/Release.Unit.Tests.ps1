Describe 'DrunkenAD release readiness' {
    BeforeAll {
        $script:projectRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:releaseScriptPath = Join-Path -Path $script:projectRoot -ChildPath 'scripts/Test-DrunkenADRelease.ps1'
        $script:testRunnerPath = Join-Path -Path $script:projectRoot -ChildPath 'tests/Invoke-DrunkenADTests.ps1'
        $script:docsScriptPath = Join-Path -Path $script:projectRoot -ChildPath 'scripts/Test-DrunkenADDocs.ps1'
        $script:architectureMapScriptPath = Join-Path -Path $script:projectRoot -ChildPath 'scripts/Test-DrunkenADArchitectureMap.ps1'
        $script:manifestPath = Join-Path -Path $script:projectRoot -ChildPath 'DrunkenAD/DrunkenAD.psd1'
        $script:manifest = Test-ModuleManifest -Path $script:manifestPath

        function Get-TrustedTestNames {
            param([string]$RunnerContent)

            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($RunnerContent, [ref]$tokens, [ref]$parseErrors)
            if ($parseErrors.Count -gt 0) { throw 'Test runner must parse without errors.' }
            $assignments = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -eq 'trustedTestNames'
            }, $true))
            if ($assignments.Count -ne 1 -or
                $assignments[0].Right -isnot [System.Management.Automation.Language.CommandExpressionAst] -or
                $assignments[0].Right.Expression -isnot [System.Management.Automation.Language.ArrayExpressionAst]) {
                throw 'Expected one explicit literal trusted test allowlist.'
            }
            @($assignments[0].Right.Expression.SafeGetValue())
        }

        function Assert-TrustedTestCoverage {
            param([string]$RunnerContent, [string]$TestRoot)

            $names = @(Get-TrustedTestNames $RunnerContent)
            $unique = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($name in $names) {
                if (-not $unique.Add($name)) { throw 'Duplicate trusted test entry.' }
            }
            $actual = @(Get-ChildItem -LiteralPath $TestRoot -File -Filter '*.Tests.ps1' | Select-Object -ExpandProperty Name)
            if ($names.Count -eq 0 -or $names.Count -ne $actual.Count -or
                @(Compare-Object $names $actual -CaseSensitive).Count -gt 0) {
                throw 'Trusted allowlist must exactly match top-level test files.'
            }
        }
    }

    Context 'Release gate behavior in an isolated fixture' {
        BeforeEach {
            $script:fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item (Join-Path $script:fixtureRoot 'scripts') -ItemType Directory -Force | Out-Null
            New-Item (Join-Path $script:fixtureRoot 'tests') -ItemType Directory -Force | Out-Null
            Copy-Item (Join-Path $script:projectRoot 'DrunkenAD') $script:fixtureRoot -Recurse
            Copy-Item (Join-Path $script:projectRoot 'CHANGELOG.md') $script:fixtureRoot
            $script:fixtureGate = Join-Path $script:fixtureRoot 'scripts/Test-DrunkenADRelease.ps1'
            Copy-Item $script:releaseScriptPath $script:fixtureGate
            Set-Content (Join-Path $script:fixtureRoot 'scripts/Test-DrunkenADSyntax.ps1') "'syntax' | Add-Content (Join-Path `$PSScriptRoot '../calls.txt')"
            Set-Content (Join-Path $script:fixtureRoot 'scripts/Test-DrunkenADDocs.ps1') "'docs' | Add-Content (Join-Path `$PSScriptRoot '../calls.txt')"
            Set-Content (Join-Path $script:fixtureRoot 'tests/Invoke-DrunkenADTests.ps1') "[CmdletBinding()] param(`$Output, `$PesterManifestPath, `$TestResultPath) ('tests:' + `$PesterManifestPath) | Add-Content (Join-Path `$PSScriptRoot '../calls.txt'); if (`$TestResultPath) { Set-Content `$TestResultPath 'test receipt' }"
            Mock Publish-Module { throw 'Publishing is forbidden in release gate tests.' }
        }

        AfterEach {
            $fixtureModuleRoot = Join-Path $script:fixtureRoot 'DrunkenAD'
            $fixtureModules = @(Get-Module -Name DrunkenAD | Where-Object { $_.ModuleBase -eq $fixtureModuleRoot })
            if ($fixtureModules.Count -gt 0) {
                Remove-Module -ModuleInfo $fixtureModules -Force -ErrorAction Stop
            }
            Import-Module $script:manifestPath -Global -Force -ErrorAction Stop
            @(Get-Module -Name DrunkenAD | Where-Object { $_.ModuleBase -eq $fixtureModuleRoot }).Count | Should -Be 0
            @(Get-Module -Name DrunkenAD | Where-Object { $_.ModuleBase -eq (Split-Path $script:manifestPath -Parent) }).Count | Should -Be 1
        }

        It 'runs prerequisite checks and forwards the selected test runtime without publishing' {
            & $script:fixtureGate -PesterManifestPath 'synthetic-pester.psd1'
            $calls = @(Get-Content (Join-Path $script:fixtureRoot 'calls.txt'))
            $calls.Count | Should -Be 3
            $calls[0] | Should -Be 'syntax'
            $calls[1] | Should -Be 'docs'
            $calls[2] | Should -Be 'tests:synthetic-pester.psd1'
            Should -Invoke Publish-Module -Times 0 -Exactly
        }

        It 'stops before tests when a prerequisite fails' {
            Set-Content (Join-Path $script:fixtureRoot 'scripts/Test-DrunkenADDocs.ps1') "throw 'Synthetic documentation failure'"
            { & $script:fixtureGate } | Should -Throw '*Synthetic documentation failure*'
            @(Get-Content (Join-Path $script:fixtureRoot 'calls.txt')).Count | Should -Be 1
            Should -Invoke Publish-Module -Times 0 -Exactly
        }

        It 'retains CI test receipts through script parameter defaults with only the release gate' {
            $key = 'Invoke-DrunkenADTests.ps1:TestResultPath'
            $hadDefault = $PSDefaultParameterValues.ContainsKey($key)
            $savedDefault = $PSDefaultParameterValues[$key]
            $receiptPath = Join-Path $script:fixtureRoot 'ci-results.xml'
            try {
                $PSDefaultParameterValues[$key] = $receiptPath
                & $script:fixtureGate
                Get-Content $receiptPath | Should -Be 'test receipt'
                @(Get-Content (Join-Path $script:fixtureRoot 'calls.txt') | Where-Object { $_ -like 'tests:*' }).Count | Should -Be 1
            }
            finally {
                if ($hadDefault) { $PSDefaultParameterValues[$key] = $savedDefault }
                else { $PSDefaultParameterValues.Remove($key) }
            }
        }

        It 'uses the manifest version rather than a hard-coded release version' {
            Mock Test-ModuleManifest {
                param($Path)
                $exports = @{}
                foreach ($name in (Import-PowerShellDataFile -LiteralPath $Path).FunctionsToExport) {
                    $exports[$name] = $true
                }
                [pscustomobject]@{
                    Version = [version]'9.8.7'
                    PrivateData = @{ PSData = @{
                        ProjectUri = 'https://github.com/jonathanweinberg/DrunkenAD'
                        ReleaseNotes = 'Release 9.8.7 fixture'
                    } }
                    ExportedFunctions = $exports
                }
            }
            Add-Content (Join-Path $script:fixtureRoot 'CHANGELOG.md') "`n## 9.8.7"
            { & $script:fixtureGate } | Should -Not -Throw
            Should -Invoke Test-ModuleManifest -Times 1 -Exactly
        }

        It 'rejects release notes that do not describe the manifest version' {
            Mock Test-ModuleManifest {
                param($Path)
                [pscustomobject]@{
                    Version = [version](Import-PowerShellDataFile -LiteralPath $Path).ModuleVersion
                    PrivateData = @{ PSData = @{
                        ProjectUri = 'https://github.com/jonathanweinberg/DrunkenAD'
                        ReleaseNotes = 'Unrelated release'
                    } }
                }
            }
            { & $script:fixtureGate } | Should -Throw '*ReleaseNotes must describe*'
            @(Get-Content (Join-Path $script:fixtureRoot 'calls.txt')).Count | Should -Be 2
            Should -Invoke Test-ModuleManifest -Times 1 -Exactly
        }
    }

    It 'loads only the pinned Pester runtime and explicitly trusted test files' {
        $releaseScriptContent = Get-Content -LiteralPath $script:releaseScriptPath -Raw
        $runnerContent = Get-Content -LiteralPath $script:testRunnerPath -Raw

        $releaseScriptContent | Should -Not -Match 'Add-DrunkenADLocalPesterCache|tests/Live/results|PSModulePath'
        $runnerContent | Should -Not -Match 'Add-DrunkenADLocalPesterCache|tests/Live/results|PSModulePath|MinimumVersion'
        $runnerContent | Should -Match 'RequiredVersion\s+\$requiredPesterVersion'
        $runnerContent | Should -Match "\[version\]'5\.7\.1'"
        $runnerContent | Should -Not -Match '\$configuration\.Run\.Path\s*=\s*\$PSScriptRoot'

        { Assert-TrustedTestCoverage $runnerContent $PSScriptRoot } | Should -Not -Throw
    }

    Context 'Trusted test allowlist guard regressions' {
        BeforeEach {
            $script:allowlistRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item $script:allowlistRoot -ItemType Directory | Out-Null
            Set-Content (Join-Path $script:allowlistRoot 'First.Tests.ps1') ''
            Set-Content (Join-Path $script:allowlistRoot 'Second.Tests.ps1') ''
        }

        It 'rejects a missing trusted entry' {
            { Assert-TrustedTestCoverage "`$trustedTestNames = @('First.Tests.ps1')" $script:allowlistRoot } | Should -Throw '*exactly match*'
        }

        It 'rejects a newly added top-level test until explicitly trusted' {
            Set-Content (Join-Path $script:allowlistRoot 'New.Tests.ps1') ''
            { Assert-TrustedTestCoverage "`$trustedTestNames = @('First.Tests.ps1', 'Second.Tests.ps1')" $script:allowlistRoot } | Should -Throw '*exactly match*'
        }

        It 'rejects duplicate entries including case variants' {
            { Assert-TrustedTestCoverage "`$trustedTestNames = @('First.Tests.ps1', 'FIRST.Tests.ps1')" $script:allowlistRoot } | Should -Throw '*Duplicate*'
        }

        It 'rejects an allowlisted file that does not exist' {
            { Assert-TrustedTestCoverage "`$trustedTestNames = @('First.Tests.ps1', 'Absent.Tests.ps1')" $script:allowlistRoot } | Should -Throw '*exactly match*'
        }

        It 'excludes nested result storage from the expected top-level set' {
            $nested = Join-Path $script:allowlistRoot 'Live/results'
            New-Item $nested -ItemType Directory -Force | Out-Null
            Set-Content (Join-Path $nested 'Untrusted.Tests.ps1') "throw 'Must never execute'"
            { Assert-TrustedTestCoverage "`$trustedTestNames = @('First.Tests.ps1', 'Second.Tests.ps1')" $script:allowlistRoot } | Should -Not -Throw
        }

        It 'rejects dynamic or multiply assigned allowlists' {
            { Get-TrustedTestNames '$trustedTestNames = @(Get-ChildItem)' } | Should -Throw
            { Get-TrustedTestNames "`$trustedTestNames = @('First.Tests.ps1'); `$trustedTestNames = @('Second.Tests.ps1')" } | Should -Throw '*one explicit*'
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

    It 'returns a failing process exit code for <FailureMode>' -TestCases @(
        @{ FailureMode = 'discovery failure'; ExpectedError = 'Pester result was Failed' }
        @{ FailureMode = 'release guard self-exclusion'; ExpectedError = 'allowlist must exactly match' }
    ) {
        param($FailureMode, $ExpectedError)
        $testRoot = Join-Path $TestDrive 'runner/tests'
        New-Item $testRoot -ItemType Directory -Force | Out-Null
        $runnerCopy = Join-Path $testRoot 'Invoke-DrunkenADTests.ps1'
        Copy-Item $script:testRunnerPath $runnerCopy
        foreach ($name in @(
            'DrunkenAD.Unit.Tests.ps1', 'Help.Unit.Tests.ps1', 'LiveCampaign.Unit.Tests.ps1',
            'IntegrationLifecycle.Unit.Tests.ps1', 'IntegrationOwnership.Unit.Tests.ps1',
            'Release.Unit.Tests.ps1', 'SchemaEnablement.Unit.Tests.ps1',
            'SchemaStatus.Unit.Tests.ps1', 'WriteOperation.Unit.Tests.ps1',
            'Logging.Unit.Tests.ps1', 'SampleOwnership.Unit.Tests.ps1',
            'DrunkenAD.Integration.Tests.ps1'
        )) {
            Set-Content (Join-Path $testRoot $name) "Describe 'Fixture' { It 'passes' { 1 | Should -Be 1 } }"
        }
        if ($FailureMode -eq 'discovery failure') {
            Set-Content (Join-Path $testRoot 'DrunkenAD.Unit.Tests.ps1') "throw 'Synthetic discovery failure'"
        }
        else {
            $runnerText = Get-Content $runnerCopy -Raw
            $tokens = $null; $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($runnerText, [ref]$tokens, [ref]$parseErrors)
            $entry = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -eq 'Release.Unit.Tests.ps1' }, $true)
            Set-Content $runnerCopy $runnerText.Remove($entry.Extent.StartOffset, $entry.Extent.EndOffset - $entry.Extent.StartOffset)
        }
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
        ($output | Out-String) | Should -Match $ExpectedError
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

Describe 'Unit-test function isolation' {
    It 'restores <InitialState> functions after repeated unit fixture runs' -ForEach @(
        @{ InitialState = 'absent' }
        @{ InitialState = 'preexisting global' }
    ) {
        $probePath = Join-Path $TestDrive 'unit-isolation.ps1'
        Set-Content -LiteralPath $probePath -Value @'
param($PesterPath, $TestRoot, $InitialState)
$ErrorActionPreference = 'Stop'
Import-Module $PesterPath -RequiredVersion 5.7.1 -Force -ErrorAction Stop
$names = @('Get-ADRootDSE', 'Get-ADObject', 'Get-ADUser', 'Set-ADUser', 'Remove-ADUser', 'Get-ADForest', 'Get-ADDomain', 'Set-ADObject')
$originals = @{}
$variableNames = @('GetADUser', 'GetADRootDSE', 'GetADObject', 'SetADUser') | ForEach-Object {
    "DrunkenADTest_${_}Calls"
    "DrunkenADTest_${_}Handler"
}
$originalVariables = @{}
foreach ($name in $variableNames) {
    if (Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue) { throw "Unexpected test variable: $name" }
    if ($InitialState -eq 'preexisting global') {
        $originalVariables[$name] = [pscustomobject]@{ Original = $name }
        Set-Variable -Name $name -Scope Global -Value $originalVariables[$name]
    }
}
foreach ($name in $names) {
    if (Get-Item -LiteralPath ('Function:\{0}' -f $name) -ErrorAction SilentlyContinue) {
        throw "Unexpected function in fresh process: $name"
    }
    if ($InitialState -eq 'preexisting global') {
        $originals[$name] = [scriptblock]::Create("throw 'Original ${name}: must not execute.'")
        Set-Item -LiteralPath ('Function:\global:{0}' -f $name) -Value $originals[$name]
    }
}
for ($run = 1; $run -le 2; $run++) {
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = @(
        'DrunkenAD.Unit.Tests.ps1', 'LiveCampaign.Unit.Tests.ps1', 'Logging.Unit.Tests.ps1',
        'SchemaEnablement.Unit.Tests.ps1', 'SchemaStatus.Unit.Tests.ps1',
        'WriteOperation.Unit.Tests.ps1'
    ) | ForEach-Object { Join-Path $TestRoot $_ }
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'None'
    # Exercise each owning fixture without recursively selecting this release file.
    $configuration.Filter.FullName = @(
        '*exports the CSV multivalue splitter as an explicit helper',
        '*runs the inline smoke path with script-local helpers in a fresh scope',
        '*does not throw after a completed public write when the real warning stream is set to Stop',
        '*reports preflight information without writing by default',
        '*does not confuse a similarly named attribute with drink',
        '*does not write an unchanged value set'
    )
    $result = Invoke-Pester -Configuration $configuration
    if ($result.Result -ne 'Passed' -or $result.PassedCount -ne 6 -or $result.FailedCount -ne 0) {
        throw "Unit isolation probe failed: $($result.Result), $($result.PassedCount) passed."
    }
    foreach ($name in $names) {
        $current = Get-Item -LiteralPath ('Function:\{0}' -f $name) -ErrorAction SilentlyContinue
        if ($InitialState -eq 'absent') {
            if ($current) { throw "Leaked function after run ${run}: $name" }
        }
        elseif (-not $current -or -not [object]::ReferenceEquals($current.ScriptBlock, $originals[$name])) {
            throw "Original function was not restored after run ${run}: $name"
        }
        $moduleFunction = & (Get-Module DrunkenAD) {
            param($Name)
            Get-Item -LiteralPath ('Function:\{0}' -f $Name) -ErrorAction SilentlyContinue
        } $name
        if ($InitialState -eq 'absent') {
            if ($moduleFunction) { throw "Leaked module function after run ${run}: $name" }
        }
        elseif (-not $moduleFunction -or -not [object]::ReferenceEquals($moduleFunction.ScriptBlock, $originals[$name])) {
            throw "Original function is shadowed in the module after run ${run}: $name"
        }
    }
    foreach ($name in $variableNames) {
        $current = Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
        if ($InitialState -eq 'absent') {
            if ($current) { throw "Leaked variable after run ${run}: $name" }
        }
        elseif (-not $current -or -not [object]::ReferenceEquals($current.Value, $originalVariables[$name])) {
            throw "Original variable was not restored after run ${run}: $name"
        }
    }
}
'Unit isolation verified across two runs.'
'@
        $pesterPath = (Get-Module Pester).Path -replace 'Pester\.psm1$', 'Pester.psd1'
        $processPath = (Get-Process -Id $PID).Path
        $savedErrorPreference = $ErrorActionPreference
        try {
            # Windows PowerShell turns redirected native stderr into ErrorRecords.
            $ErrorActionPreference = 'Continue'
            $output = & $processPath -NoLogo -NoProfile -File $probePath -PesterPath $pesterPath -TestRoot $PSScriptRoot -InitialState $InitialState 2>&1
            $processExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedErrorPreference
        }
        $processExitCode | Should -Be 0 -Because ($output | Out-String)
        ($output | Out-String) | Should -Match 'Unit isolation verified across two runs\.'
    }
}

Describe 'Integration selection isolation' {
    It 'performs no discovery reads and honors <Mode>' -ForEach @(
        @{ Mode = 'Excluded' }
        @{ Mode = 'MissingPrimaryOptIn' }
        @{ Mode = 'BaseIntegration' }
        @{ Mode = 'Tier1Integration' }
        @{ Mode = 'CapacityFlagAlone' }
        @{ Mode = 'AllOptIns' }
        @{ Mode = 'CapacityTagOnly' }
        @{ Mode = 'CapacityTagWithoutOptIn' }
    ) {
        $fixtureRoot = Join-Path $TestDrive $Mode
        $testRoot = Join-Path $fixtureRoot 'tests'
        $moduleRoot = Join-Path $fixtureRoot 'DrunkenAD'
        New-Item $testRoot, $moduleRoot -ItemType Directory -Force | Out-Null
        Copy-Item (Join-Path $PSScriptRoot 'Invoke-DrunkenADTests.ps1') $testRoot
        foreach ($file in Get-ChildItem $PSScriptRoot -File -Filter '*.Tests.ps1') {
            Set-Content (Join-Path $testRoot $file.Name) "Describe 'Offline fixture' { It 'passes' { 1 | Should -Be 1 } }"
        }
        Copy-Item (Join-Path $PSScriptRoot 'DrunkenAD.Integration.Tests.ps1') $testRoot -Force
        Set-Content (Join-Path $moduleRoot 'DrunkenAD.psd1') "@{ RootModule = 'DrunkenAD.psm1'; ModuleVersion = '0.0.0'; FunctionsToExport = @('Test-ADDrinkAttributeReadyForUserWrite') }"
        Set-Content (Join-Path $moduleRoot 'DrunkenAD.psm1') @'
function Test-ADDrinkAttributeReadyForUserWrite {
    param($Server, [switch]$PassThru)
    if ($Server -ne 'dc.offline.invalid') { throw 'Integration runtime lost its server environment.' }
    $global:offlineReadinessCalls++
    [pscustomobject]@{ ReadyForUserWrite = $false; BlockingReason = 'OfflineFixture'; BlockingMessage = 'Offline fixture'; Server = $Server }
}
Export-ModuleMember -Function Test-ADDrinkAttributeReadyForUserWrite
'@
        Set-Content (Join-Path $fixtureRoot 'ActiveDirectory.psm1') @'
function Get-ADOrganizationalUnit {
    param($Identity, $Server, $ErrorAction)
    if ($Identity -ne 'OU=Offline,DC=offline,DC=invalid' -or $Server -ne 'dc.offline.invalid') { throw 'Integration runtime lost its OU environment.' }
    $global:offlineOuReads++
    [pscustomobject]@{ DistinguishedName = $Identity }
}
function Get-ADUser { param($Identity, $Server, $Properties) $global:offlineUnexpectedCalls++; throw 'Directory access forbidden.' }
function Set-ADUser { [CmdletBinding(SupportsShouldProcess)] param($Identity, $Server, $Add, $Remove, $Replace) $global:offlineUnexpectedCalls++; throw 'Directory access forbidden.' }
function Get-ADReplicationAttributeMetadata { param($Object, $Server, $Properties) $global:offlineUnexpectedCalls++; throw 'Directory access forbidden.' }
function New-ADUser { $global:offlineUnexpectedCalls++; throw 'Directory access forbidden.' }
function Remove-ADUser { $global:offlineUnexpectedCalls++; throw 'Directory access forbidden.' }
Export-ModuleMember -Function *
'@
        $probePath = Join-Path $fixtureRoot 'integration-selection.ps1'
        Set-Content $probePath @'
param($PesterPath, $FixtureRoot, $Mode)
$ErrorActionPreference = 'Stop'
Import-Module $PesterPath -RequiredVersion 5.7.1 -Force
Import-Module Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility
$global:PSModuleAutoLoadingPreference = 'None'
$global:offlinePesterPath = $PesterPath
$global:offlineModulePath = Join-Path $FixtureRoot 'DrunkenAD/DrunkenAD.psd1'
$global:offlineAdPath = Join-Path $FixtureRoot 'ActiveDirectory.psm1'
$global:offlineImportCalls = 0
$global:offlineReadinessCalls = 0
$global:offlineOuReads = 0
$global:offlineUnexpectedCalls = 0
$global:offlineAllowInitialization = $false
function global:Import-Module {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Name, [switch]$Force, [version]$RequiredVersion)
    if ($Name -eq 'ActiveDirectory' -or [IO.Path]::GetFullPath($Name) -eq [IO.Path]::GetFullPath($global:offlineModulePath)) {
        $global:offlineImportCalls++
        if (-not $global:offlineAllowInitialization) { throw 'Integration import outside selected runtime.' }
        if ($Name -eq 'ActiveDirectory') { $PSBoundParameters['Name'] = $global:offlineAdPath }
    }
    elseif ($Name -ne $global:offlinePesterPath) { throw "Unexpected module import: $Name" }
    Microsoft.PowerShell.Core\Import-Module @PSBoundParameters -Global
}
$env:DRUNKENAD_RUN_INTEGRATION = if ($Mode -in @('MissingPrimaryOptIn', 'CapacityFlagAlone')) { '0' } else { '1' }
$env:DRUNKENAD_RUN_TIER1 = if ($Mode -in @('BaseIntegration', 'CapacityFlagAlone')) { '0' } else { '1' }
$env:DRUNKENAD_RUN_CAPACITY = if ($Mode -in @('Tier1Integration', 'CapacityTagWithoutOptIn')) { '0' } else { '1' }
$env:DRUNKENAD_TEST_DC = 'dc.offline.invalid'
$env:DRUNKENAD_TEST_DNS_SUFFIX = 'offline.invalid'
$env:DRUNKENAD_TEST_USER_OU = 'OU=Offline,DC=offline,DC=invalid'
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $FixtureRoot 'tests/DrunkenAD.Integration.Tests.ps1'
$configuration.Run.SkipRun = $true
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'None'
if ($Mode -eq 'Excluded') { $configuration.Filter.ExcludeTag = @('Integration') }
if ($Mode -in @('CapacityTagOnly', 'CapacityTagWithoutOptIn')) { $configuration.Filter.Tag = @('Capacity') }
$discovery = Invoke-Pester -Configuration $configuration
if ($discovery.TotalCount -ne 27 -or @($discovery.Tests | Where-Object { $_.Path -contains 'Bounded Tier1 live regressions' }).Count -ne 15) {
    throw 'Expected coverage of 12 base and 15 Tier1 integration cases.'
}
if ($global:offlineImportCalls -ne 0 -or $global:offlineReadinessCalls -ne 0) { throw 'Integration discovery attempted directory initialization.' }
$eligible = @($discovery.Tests | Where-Object { $_.ShouldRun -and -not $_.Skip })
$expectedEligible = @{
    Excluded = 0; MissingPrimaryOptIn = 0; BaseIntegration = 12; Tier1Integration = 26
    CapacityFlagAlone = 0; AllOptIns = 27; CapacityTagOnly = 1; CapacityTagWithoutOptIn = 0
}[$Mode]
$capacity = @($discovery.Tests | Where-Object { $_.Tag -contains 'Capacity' })
$eligibleCapacity = @($eligible | Where-Object { $_.Tag -contains 'Capacity' })
$expectedCapacity = if ($Mode -in @('AllOptIns', 'CapacityTagOnly')) { 1 } else { 0 }
if ($eligible.Count -ne $expectedEligible -or $capacity.Count -ne 1 -or $eligibleCapacity.Count -ne $expectedCapacity) {
    throw "Unexpected selection: eligible=$($eligible.Count) capacity=$($eligibleCapacity.Count) mode=$Mode"
}
if (@($discovery.Tests | Where-Object { $_.Executed }).Count -ne 0 -or $global:offlineUnexpectedCalls -ne 0) {
    throw 'Discovery-only selection executed a test or directory command.'
}
if ($Mode -in @('CapacityFlagAlone', 'AllOptIns', 'CapacityTagOnly', 'CapacityTagWithoutOptIn')) {
    "Integration selection verified: $Mode; base=12; tier1=15."
    exit 0
}
$include = $Mode -ne 'Excluded'
$global:offlineAllowInitialization = $include -and $env:DRUNKENAD_RUN_INTEGRATION -eq '1'
& (Join-Path $FixtureRoot 'tests/Invoke-DrunkenADTests.ps1') -PesterManifestPath $PesterPath -IncludeIntegration:$include -Output None
$expectedImports = if ($global:offlineAllowInitialization) { 2 } else { 0 }
$expectedReadiness = if ($global:offlineAllowInitialization) { 1 } else { 0 }
$expectedOu = if ($Mode -eq 'Tier1Integration') { 1 } else { 0 }
if ($global:offlineImportCalls -ne $expectedImports -or $global:offlineReadinessCalls -ne $expectedReadiness -or $global:offlineOuReads -ne $expectedOu -or $global:offlineUnexpectedCalls -ne 0) {
    throw "Unexpected initialization counts: imports=$global:offlineImportCalls readiness=$global:offlineReadinessCalls OU=$global:offlineOuReads directory=$global:offlineUnexpectedCalls"
}
"Integration selection verified: $Mode; base=12; tier1=15."
'@
        $pesterPath = (Get-Module Pester).Path -replace 'Pester\.psm1$', 'Pester.psd1'
        $processPath = (Get-Process -Id $PID).Path
        $savedErrorPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = & $processPath -NoLogo -NoProfile -File $probePath -PesterPath $pesterPath -FixtureRoot $fixtureRoot -Mode $Mode 2>&1
            $processExitCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $savedErrorPreference }
        $processExitCode | Should -Be 0 -Because ($output | Out-String)
        ($output | Out-String) | Should -Match "Integration selection verified: $Mode; base=12; tier1=15\."
    }
}

Describe 'Capacity target preflight isolation' {
    BeforeAll {
        $tokens = $null
        $errors = $null
        $script:capacityAst = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $PSScriptRoot 'DrunkenAD.Integration.Tests.ps1'), [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw 'Integration source must parse before extracting pure validation helpers.' }
        foreach ($name in @('Assert-CapacityNativeCommand', 'Assert-CapacityTarget')) {
            $definition = $script:capacityAst.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
            }, $true)
            if ($null -eq $definition) { throw "Missing capacity validation helper: $name" }
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }

    BeforeEach {
        # Synthetic metadata only: the actual validator is exercised without AD or fixtures.
        $script:capacityInput = @{
            Server = 'dc01.example.invalid'
            RootDse = [pscustomobject]@{
                dnsHostName = 'dc01.example.invalid'
                dsServiceName = 'CN=NTDS Settings,CN=DC01,CN=Servers,CN=Example,CN=Sites,CN=Configuration,DC=example,DC=invalid'
                defaultNamingContext = 'DC=example,DC=invalid'
            }
            Controller = [pscustomobject]@{
                HostName = 'dc01.example.invalid'
                NTDSSettingsObjectDN = 'CN=NTDS Settings,CN=DC01,CN=Servers,CN=Example,CN=Sites,CN=Configuration,DC=example,DC=invalid'
                DefaultPartition = 'DC=example,DC=invalid'
                Domain = 'example.invalid'
                IsReadOnly = $false
                Enabled = $true
            }
            OuPath = 'OU=Capacity,DC=example,DC=invalid'
            Ou = [pscustomobject]@{
                DistinguishedName = 'OU=Capacity,DC=example,DC=invalid'
                ObjectClass = 'organizationalUnit'
                ObjectGUID = [guid]'00000000-0000-0000-0000-000000000001'
            }
        }
    }

    It 'accepts matching synthetic writable-replica metadata with <Casing> hostname casing and <Shape> responses' -ForEach @(
        @{ Casing = 'lower'; Shape = 'scalar' }, @{ Casing = 'upper'; Shape = 'scalar' }
        @{ Casing = 'lower'; Shape = 'array' }, @{ Casing = 'upper'; Shape = 'array' }
    ) {
        if ($Casing -eq 'upper') { $script:capacityInput.Server = $script:capacityInput.Server.ToUpperInvariant() }
        if ($Shape -eq 'array') {
            foreach ($part in @('RootDse', 'Controller', 'Ou')) { $script:capacityInput[$part] = @($script:capacityInput[$part]) }
        }
        Assert-CapacityTarget @script:capacityInput | Should -BeExactly 'dc01.example.invalid'
    }

    It 'rejects noncanonical or non-replica endpoint <Server>' -ForEach @(
        @{ Server = '' }, @{ Server = ' ' }, @{ Server = 'EXAMPLE' }, @{ Server = 'localhost' }
        @{ Server = 'example.invalid' }, @{ Server = 'alias.example.invalid' }
        @{ Server = '192.0.2.10' }, @{ Server = '2001:db8::1' }, @{ Server = '[2001:db8::1]' }
        @{ Server = 'dc01.example.invalid:389' }, @{ Server = 'dc01.example.invalid.' }
        @{ Server = ' dc01.example.invalid' }, @{ Server = 'dc01.example.invalid ' }
        @{ Server = 'ldap://dc01.example.invalid' }, @{ Server = '*.example.invalid' }
        @{ Server = 'dc_01.example.invalid' }, @{ Server = '-dc01.example.invalid' }
        @{ Server = 'dc01-.example.invalid' }, @{ Server = 'dc01..example.invalid' }
        @{ Server = (('x' * 64) + '.example.invalid') }
        @{ Server = ((('x' * 63) + '.') * 4 + 'invalid') }
    ) {
        $script:capacityInput.Server = $Server
        { Assert-CapacityTarget @script:capacityInput } | Should -Throw '*Evidence Gap:*'
    }

    It 'rejects inconsistent or non-writable <Part>.<Field>' -ForEach @(
        @{ Part = 'RootDse'; Field = 'dnsHostName'; Value = 'dc02.example.invalid' }
        @{ Part = 'RootDse'; Field = 'dsServiceName'; Value = 'CN=Different' }
        @{ Part = 'RootDse'; Field = 'defaultNamingContext'; Value = 'DC=other,DC=invalid' }
        @{ Part = 'Controller'; Field = 'HostName'; Value = 'dc02.example.invalid' }
        @{ Part = 'Controller'; Field = 'NTDSSettingsObjectDN'; Value = 'CN=Different' }
        @{ Part = 'Controller'; Field = 'DefaultPartition'; Value = 'DC=other,DC=invalid' }
        @{ Part = 'Controller'; Field = 'Domain'; Value = 'dc01.example.invalid' }
        @{ Part = 'Controller'; Field = 'IsReadOnly'; Value = $true }
        @{ Part = 'Controller'; Field = 'IsReadOnly'; Value = 'False' }
        @{ Part = 'Controller'; Field = 'Enabled'; Value = $false }
        @{ Part = 'Controller'; Field = 'Enabled'; Value = 'True' }
        @{ Part = 'Ou'; Field = 'DistinguishedName'; Value = 'OU=Other,DC=example,DC=invalid' }
        @{ Part = 'Ou'; Field = 'ObjectClass'; Value = 'container' }
        @{ Part = 'Ou'; Field = 'ObjectGUID'; Value = [guid]::Empty }
        @{ Part = 'Ou'; Field = 'ObjectGUID'; Value = 'not-a-guid' }
    ) {
        $script:capacityInput[$Part].$Field = $Value
        { Assert-CapacityTarget @script:capacityInput } | Should -Throw '*Evidence Gap:*'
    }

    It 'rejects missing or ambiguous <Part> responses' -ForEach @(
        @{ Part = 'RootDse' }, @{ Part = 'Controller' }, @{ Part = 'Ou' }
    ) {
        $original = $script:capacityInput[$Part]
        foreach ($bad in @($null, @(), @($original, $original))) {
            $script:capacityInput[$Part] = $bad
            { Assert-CapacityTarget @script:capacityInput } | Should -Throw '*Evidence Gap:*'
        }
    }

    It 'requires scalar populated metadata for <Part>.<Field>' -ForEach @(
        @{ Part = 'RootDse'; Field = 'dnsHostName' }
        @{ Part = 'RootDse'; Field = 'dsServiceName' }
        @{ Part = 'RootDse'; Field = 'defaultNamingContext' }
        @{ Part = 'Controller'; Field = 'HostName' }
        @{ Part = 'Controller'; Field = 'NTDSSettingsObjectDN' }
        @{ Part = 'Controller'; Field = 'DefaultPartition' }
        @{ Part = 'Controller'; Field = 'Domain' }
        @{ Part = 'Controller'; Field = 'IsReadOnly' }
        @{ Part = 'Controller'; Field = 'Enabled' }
        @{ Part = 'Ou'; Field = 'DistinguishedName' }
        @{ Part = 'Ou'; Field = 'ObjectClass' }
        @{ Part = 'Ou'; Field = 'ObjectGUID' }
    ) {
        $original = $script:capacityInput[$Part].$Field
        foreach ($bad in @($null, ' ', @($original, $original))) {
            $script:capacityInput[$Part].$Field = $bad
            { Assert-CapacityTarget @script:capacityInput } | Should -Throw '*Evidence Gap:*'
        }
        $script:capacityInput[$Part].PSObject.Properties.Remove($Field)
        { Assert-CapacityTarget @script:capacityInput } | Should -Throw '*Evidence Gap:*'
    }

    It 'rejects a resolved OU outside the verified domain or a non-OU path' -ForEach @(
        @{ Path = 'OU=Capacity,DC=other,DC=invalid' }
        @{ Path = 'CN=Users,DC=example,DC=invalid' }
    ) {
        $script:capacityInput.OuPath = $Path
        $script:capacityInput.Ou.DistinguishedName = $Path
        { Assert-CapacityTarget @script:capacityInput } | Should -Throw '*exact pre-existing OU*'
    }

    It 'rejects untrusted command provenance without invoking any command' {
        $functionCommand = Get-Command Assert-CapacityTarget
        $aliasCommand = Get-Alias -Name where
        $wrongModuleCommand = Get-Command Microsoft.PowerShell.Management\Get-Item
        $forgedCommand = [pscustomobject]@{ CommandType = 'Cmdlet'; ModuleName = 'ActiveDirectory' }
        foreach ($command in @($null, $functionCommand, $aliasCommand, $wrongModuleCommand, $forgedCommand)) {
            { Assert-CapacityNativeCommand $command } | Should -Throw '*requires native ActiveDirectory commands*'
        }
    }

    It 'stops actual setup on a shadowed preflight command before directory calls or creation' {
        $setup = @($script:capacityAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'BeforeAll'
        }, $true))[0].CommandElements[-1].ScriptBlock.GetScriptBlock()
        $script:unsafeCapacityCalls = 0
        function Get-ADRootDSE { $script:unsafeCapacityCalls++; throw 'Directory access forbidden.' }
        function New-ADUser { $script:unsafeCapacityCalls++; throw 'Fixture creation forbidden.' }
        Mock Import-Module {}
        $environment = @{
            DRUNKENAD_RUN_INTEGRATION = '1'; DRUNKENAD_RUN_TIER1 = '1'; DRUNKENAD_RUN_CAPACITY = '1'
            DRUNKENAD_TEST_DC = 'dc01.example.invalid'; DRUNKENAD_TEST_DNS_SUFFIX = 'example.invalid'
            DRUNKENAD_TEST_USER_OU = 'OU=Capacity,DC=example,DC=invalid'
        }
        $saved = @{}
        try {
            foreach ($name in $environment.Keys) {
                $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
                [Environment]::SetEnvironmentVariable($name, $environment[$name], 'Process')
            }
            { & $setup } | Should -Throw '*requires native ActiveDirectory commands*'
            $script:unsafeCapacityCalls | Should -Be 0
            $script:createdUser | Should -BeFalse
            $script:capacityTargetServer | Should -BeNullOrEmpty
            Should -Invoke Import-Module -Times 2 -Exactly
        }
        finally {
            foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
        }
    }

    It 'places guarded native preflight and validation before readiness and fixture creation' {
        $preflight = $script:capacityAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
                $node.Clauses[0].Item1.Extent.Text -eq '$runCapacity'
        }, $true)
        $preflight | Should -Not -BeNullOrEmpty
        $commands = @($preflight.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        $provenance = @($commands | Where-Object { $_.GetCommandName() -eq 'Assert-CapacityNativeCommand' })
        $validation = @($commands | Where-Object { $_.GetCommandName() -eq 'Assert-CapacityTarget' })
        $reads = @($commands | Where-Object { $_.GetCommandName() -in @('Get-ADRootDSE', 'Get-ADDomainController', 'Get-ADOrganizationalUnit') })
        $reads.Count | Should -Be 3
        $provenance.Count | Should -Be 2
        $validation.Count | Should -Be 1
        $receipt = $preflight.Find({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -eq '$script:capacityTargetServer'
        }, $true)
        $receipt | Should -Not -BeNullOrEmpty
        $receipt.Extent.StartOffset | Should -BeGreaterThan $validation[0].Extent.EndOffset
        foreach ($read in $reads) {
            $read.Extent.StartOffset | Should -BeGreaterThan $provenance[-1].Extent.StartOffset
            $read.Extent.EndOffset | Should -BeLessThan $validation[0].Extent.StartOffset
            $read.Extent.Text | Should -Match '-Server \$script:domainController -ErrorAction Stop'
        }
        $following = @($script:capacityAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -in @('Test-ADDrinkAttributeReadyForUserWrite', 'New-ADUser')
        }, $true))
        $following.Count | Should -Be 2
        foreach ($command in $following) {
            $command.Extent.StartOffset | Should -BeGreaterThan $preflight.Extent.EndOffset
        }
        $script:capacityAst.Extent.Text | Should -Match '\$runCapacity = \$script:runTier1 -and \$env:DRUNKENAD_RUN_CAPACITY -eq ''1'''
        $script:capacityAst.Extent.Text | Should -Match 'IsNullOrWhiteSpace\(\$script:capacityTargetServer\)'
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
