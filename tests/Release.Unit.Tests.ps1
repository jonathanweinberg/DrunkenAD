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
$env:DRUNKENAD_RUN_INTEGRATION = if ($Mode -eq 'MissingPrimaryOptIn') { '0' } else { '1' }
$env:DRUNKENAD_RUN_TIER1 = if ($Mode -eq 'BaseIntegration') { '0' } else { '1' }
$env:DRUNKENAD_TEST_DC = 'dc.offline.invalid'
$env:DRUNKENAD_TEST_DNS_SUFFIX = 'offline.invalid'
$env:DRUNKENAD_TEST_USER_OU = 'OU=Offline,DC=offline,DC=invalid'
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $FixtureRoot 'tests/DrunkenAD.Integration.Tests.ps1'
$configuration.Run.SkipRun = $true
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'None'
$discovery = Invoke-Pester -Configuration $configuration
if ($discovery.TotalCount -ne 27 -or @($discovery.Tests | Where-Object { $_.Path -contains 'Bounded Tier1 live regressions' }).Count -ne 15) {
    throw 'Expected coverage of 12 base and 15 Tier1 integration cases.'
}
if ($global:offlineImportCalls -ne 0 -or $global:offlineReadinessCalls -ne 0) { throw 'Integration discovery attempted directory initialization.' }
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
