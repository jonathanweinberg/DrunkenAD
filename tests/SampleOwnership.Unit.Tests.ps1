BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:sampleModule = Import-Module (Join-Path $script:root 'DrunkenAD/DrunkenAD.psd1') -Force -PassThru
    $script:configPath = Join-Path $script:root 'examples/data/drink-ingestion-config.json'
    $script:projectionPrefixes = @(& $script:sampleModule { (Get-DrunkenADDefaultProjectionAttributeMap).Keys })
    $script:genericRecordPattern = '(?m)^(?<prefix>[^\s\r\n]+?-)[^\r\n]+\r?$'

    function Get-DocumentedGenericPrefixes {
        param([string]$Code)

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw 'A documented example could not be parsed.' }
        $commands = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true)
        foreach ($command in $commands) {
            $namespaceParameter = switch ($command.GetCommandName()) {
                'Set-ADUserDrinkData' { 'DataMap' }
                'Set-ADUserDrinkPrefixedData' { 'PrefixMap' }
                'Update-ADUserDrinkAttribute' { 'Prefixes' }
                'Get-ADUserDrinkData' { 'Prefix' }
                'Get-AdUserDrinkPrefixedData' { 'DrinkValuePrefix' }
                'Remove-ADUserDrinkData' { 'Prefixes' }
            }
            if (-not $namespaceParameter) { continue }
            $elements = $command.CommandElements
            for ($index = 1; $index -lt $elements.Count; $index++) {
                $element = $elements[$index]
                if ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) {
                    throw 'Generic examples must expose literal namespace arguments for the ownership guard.'
                }
                if ($element -isnot [System.Management.Automation.Language.CommandParameterAst] -or
                    $element.ParameterName -ne $namespaceParameter) { continue }
                $value = if ($element.Argument) { $element.Argument } else { $elements[$index + 1] }
                if ($namespaceParameter -in @('DataMap', 'PrefixMap')) {
                    if ($value -isnot [System.Management.Automation.Language.HashtableAst]) {
                        throw 'Generic example maps must have literal keys for the ownership guard.'
                    }
                    foreach ($pair in $value.KeyValuePairs) { [string]$pair.Item1.SafeGetValue() }
                }
                else {
                    foreach ($prefix in @($value.SafeGetValue())) { [string]$prefix }
                }
            }
        }
    }
}

Describe 'Shipped CSV and projection namespace ownership' {
    It 'retains both maps when planning <Order>' -ForEach @(
        @{ Order = 'CSV then projection' },
        @{ Order = 'projection then CSV' }
    ) {
        & $script:sampleModule {
            param($ConfigPath, $Order)
            $config = Resolve-DrunkenADCsvNamespaceMap -ConfigPath $ConfigPath
            $row = [pscustomobject]@{ ProfileTier = 'Gold'; ProfileRegion = 'NA'; Flags = 'Enabled;Audited'; RoutingMailbox = 'Queue'; TenantId = 'Example'; SyncState = 'Synced' }
            $csv = ConvertTo-DrunkenADCsvDataMap -Row $row -Mappings @(Get-DrunkenADCsvMappings -NamespaceMap $config)
            $user = [pscustomobject]@{ samAccountName = 'sample'; userPrincipalName = 'sample@example.test'; employeeID = 'Example'; mail = 'sample@example.test'; pager = 'sample@example.test' }
            $projection = ConvertTo-DrunkenADProjectionDataMap -User $user -AttributeMap (Get-DrunkenADDefaultProjectionAttributeMap)
            $first = if ($Order -eq 'CSV then projection') { $csv } else { $projection }
            $second = if ($Order -eq 'CSV then projection') { $projection } else { $csv }
            $initial = Get-DrunkenADPrefixWritePlan -CurrentValues @('Keep-Stable') -PrefixMap $first -RangeUpper 256
            $final = Get-DrunkenADPrefixWritePlan -CurrentValues $initial.FinalDrinkValues -PrefixMap $second -RangeUpper 256
            $expected = @('Keep-Stable', 'CsvProfile-Tier=Gold', 'CsvProfile-Region=NA', 'CsvRouting-Mailbox=Queue', 'Flags-Enabled', 'Flags-Audited', 'Tenant-Id=Example', 'Sync-State=Synced', 'Profile-samAccountName=sample', 'Identity-userPrincipalName=sample@example.test', 'Meta-employeeID=Example', 'Routing-mail=sample@example.test', 'Notify-pager=sample@example.test')
            @($final.FinalDrinkValues | Sort-Object) | Should -Be ($expected | Sort-Object)
        } $script:configPath $Order
    }

    It 'has no literal prefix overlap across the shipped maps' {
        & $script:sampleModule {
            param($ConfigPath)
            $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
            $defaults = Get-DrunkenADDefaultProjectionAttributeMap
            $config.PSObject.Properties.Name | Should -Contain 'CsvProfile-'
            $config.PSObject.Properties.Name | Should -Contain 'CsvRouting-'
            $config.PSObject.Properties.Name | Should -Contain 'Flags-'
            foreach ($csvPrefix in $config.PSObject.Properties.Name) {
                foreach ($projectionPrefix in $defaults.Keys) {
                    $csvPrefix.StartsWith($projectionPrefix, [StringComparison]::OrdinalIgnoreCase) | Should -BeFalse
                    $projectionPrefix.StartsWith($csvPrefix, [StringComparison]::OrdinalIgnoreCase) | Should -BeFalse
                }
            }
        } $script:configPath
    }
}

Describe 'Documented generic namespace ownership' {
    It 'keeps generic examples in <Document> separate from the default projection' -ForEach @(
        @{ Document = 'README.md' }
        @{ Document = 'docs/DATA-STORE.md' }
        @{ Document = 'docs/USE-CASES.md' }
        @{ Document = 'docs/OPERATIONS.md' }
        @{ Document = 'docs/diagrams/use-case-map.mmd' }
        @{ Document = 'docs/DIAGRAMS.md' }
        @{ Document = 'DrunkenAD/en-US/about_DrunkenAD.help.txt' }
        @{ Document = 'DrunkenAD/Public/Set-ADUserDrinkData.ps1' }
        @{ Document = 'DrunkenAD/Public/Set-ADUserDrinkPrefixedData.ps1' }
        @{ Document = 'DrunkenAD/Public/Update-ADUserDrinkAttribute.ps1' }
        @{ Document = 'DrunkenAD/Public/Get-ADUserDrinkData.ps1' }
        @{ Document = 'DrunkenAD/Public/Get-AdUserDrinkPrefixedData.ps1' }
        @{ Document = 'DrunkenAD/Public/Remove-ADUserDrinkData.ps1' }
    ) {
        $path = Join-Path $script:root $Document
        $content = Get-Content -LiteralPath $path -Raw
        $recordPrefixes = @()
        # Audit generic record sections, not intentional default-projection lists.
        $recordSections = switch ($Document) {
            'README.md' { 'Data Store Model' }
            'docs/DATA-STORE.md' { 'Core Idea'; 'Namespace Rules'; 'Removal Semantics'; 'Common Namespace Patterns' }
            'docs/USE-CASES.md' { 'Feature Flags'; 'Tenant And Environment Markers'; 'Application Routing Hints'; 'Lightweight Sync Metadata' }
        }
        foreach ($sectionName in $recordSections) {
            $pattern = '(?ms)^#{{2,3}} {0}\r?\n(?<body>.*?)(?=^#{{1,3}} |\z)' -f [regex]::Escape($sectionName)
            $section = [regex]::Match($content, $pattern)
            $section.Success | Should -BeTrue -Because "$Document must expose the generic section '$sectionName'"
            $body = $section.Groups['body'].Value
            $prefixCountBefore = $recordPrefixes.Count
            $inlinePattern = if ($sectionName -in @('Namespace Rules', 'Removal Semantics')) {
                '`(?<value>[^`\r\n]+)`'
            }
            else { '(?m)^- `(?<value>[^`\r\n]+)`' }
            foreach ($record in [regex]::Matches($body, $inlinePattern)) {
                $value = $record.Groups['value'].Value
                if ($value -match '^(Get|Set|Remove|Update)-ADUserDrink') { continue }
                if ($value.EndsWith('-') -or $value.EndsWith('+')) { $recordPrefixes += $value }
                elseif ($value.Contains('-')) { $recordPrefixes += $value.Substring(0, $value.IndexOf('-') + 1) }
            }
            foreach ($block in [regex]::Matches($body, '(?ms)^```text\r?\n(?<records>.*?)^```')) {
                foreach ($record in [regex]::Matches($block.Groups['records'].Value, $script:genericRecordPattern)) {
                    $recordPrefixes += $record.Groups['prefix'].Value
                }
            }
            $recordPrefixes.Count | Should -BeGreaterThan $prefixCountBefore -Because "$Document section '$sectionName' must have auditable generic records"
        }
        if ($Document -eq 'docs/USE-CASES.md') {
            $applicationRow = [regex]::Match($content, '(?m)^\| Application metadata \|(?<prefixes>[^|\r\n]+)\|')
            $applicationRow.Success | Should -BeTrue
            foreach ($prefix in [regex]::Matches($applicationRow.Groups['prefixes'].Value, '`(?<prefix>[^`]+)`')) {
                $recordPrefixes += $prefix.Groups['prefix'].Value
            }
        }
        if ($Document -in @('docs/diagrams/use-case-map.mmd', 'docs/DIAGRAMS.md')) {
            $diagram = $content
            if ($Document -eq 'docs/DIAGRAMS.md') {
                $useCaseSection = [regex]::Match($content, '(?ms)^## Use-Case Map\r?\n(?<body>.*?)(?=^## |\z)')
                $useCaseSection.Success | Should -BeTrue
                $diagram = $useCaseSection.Groups['body'].Value
            }
            foreach ($label in [regex]::Matches($diagram, '\["(?<prefix>[^"\r\n]+-)"\]')) {
                $recordPrefixes += $label.Groups['prefix'].Value
            }
        }
        $exampleCode = switch ([System.IO.Path]::GetExtension($path)) {
            '.md' {
                foreach ($match in [regex]::Matches($content, '(?ms)^```powershell\r?\n(?<code>.*?)^```')) {
                    $match.Groups['code'].Value
                }
            }
            '.txt' {
                foreach ($paragraph in [regex]::Split($content, '\r?\n[ \t]*\r?\n')) {
                    if ($paragraph.TrimStart() -match '^(Get|Set|Remove|Update)-ADUserDrink') { $paragraph }
                }
            }
            '.ps1' {
                $commandName = [System.IO.Path]::GetFileNameWithoutExtension($path)
                foreach ($example in (Get-Help $commandName -Examples -ErrorAction Stop).Examples.Example) {
                    [string]$example.Code
                }
            }
        }
        $prefixes = @($exampleCode | ForEach-Object { Get-DocumentedGenericPrefixes -Code $_ })
        $prefixes = @($prefixes + $recordPrefixes | Sort-Object -Unique)
        $prefixes.Count | Should -BeGreaterThan 0 -Because "$Document must have auditable generic namespace examples"
        foreach ($prefix in $prefixes) {
            foreach ($projectionPrefix in $script:projectionPrefixes) {
                $prefix.StartsWith($projectionPrefix, [StringComparison]::OrdinalIgnoreCase) |
                    Should -BeFalse -Because "$Document must not let '$prefix' overwrite projection namespace '$projectionPrefix'"
                $projectionPrefix.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) |
                    Should -BeFalse -Because "$Document must not let projection namespace '$projectionPrefix' overwrite '$prefix'"
            }
        }
    }

    It 'reads generic text records using <Format> line endings' -TestCases @(
        @{ Format = 'LF'; Newline = "`n" }
        @{ Format = 'CRLF'; Newline = "`r`n" }
    ) {
        param($Format, $Newline)
        $records = @('Flags-Enabled', 'AppRouting-Queue=review', '') -join $Newline
        @([regex]::Matches($records, $script:genericRecordPattern) | ForEach-Object { $_.Groups['prefix'].Value }) |
            Should -Be @('Flags-', 'AppRouting-')
    }

    It 'reads actual generic arguments without treating intentional projection maps as generic examples' {
        $code = @'
Set-ADUserDrinkData -SamAccountName TesterAccount -DataMap @{ 'Profile-' = @('Tier=Gold') }
Set-ADUserDrinkProjection -SamAccountName TesterAccount -AttributeMap @{ 'Meta-' = @('description') }
Remove-ADUserDrinkData -SamAccountName TesterAccount -Prefixes 'AppProfile-', 'Flags-'
'@
        $prefixes = @(Get-DocumentedGenericPrefixes -Code $code)
        $prefixes | Should -Be @('Profile-', 'AppProfile-', 'Flags-')
        @($script:projectionPrefixes | Where-Object { $_ -eq $prefixes[0] }).Count | Should -Be 1
    }

    It 'rejects a generic map hidden behind a variable rather than silently skipping its prefixes' {
        { Get-DocumentedGenericPrefixes -Code 'Set-ADUserDrinkData -SamAccountName TesterAccount -DataMap $map' } |
            Should -Throw '*literal keys*'
    }

    It 'keeps the use-case fence synchronized with its Mermaid source without inspecting other diagrams' {
        $source = Get-Content -LiteralPath (Join-Path $script:root 'docs/diagrams/use-case-map.mmd') -Raw
        $page = Get-Content -LiteralPath (Join-Path $script:root 'docs/DIAGRAMS.md') -Raw
        $section = [regex]::Match($page, '(?ms)^## Use-Case Map\r?\n(?<body>.*?)(?=^## |\z)')
        $section.Success | Should -BeTrue
        $fences = [regex]::Matches($section.Groups['body'].Value, '(?ms)^```mermaid\r?\n(?<diagram>.*?)^```')
        $fences.Count | Should -Be 1
        $fences[0].Groups['diagram'].Value.Trim() | Should -Be $source.Trim()
    }
}
