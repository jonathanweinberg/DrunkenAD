$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../DrunkenAD/DrunkenAD.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Describe 'DrunkenAD comment-based help contract' {
    BeforeAll {
        $script:projectRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:modulePath = Join-Path -Path $script:projectRoot -ChildPath 'DrunkenAD/DrunkenAD.psd1'
        $script:moduleRoot = Split-Path -Path $script:modulePath -Parent
        $script:publicRoot = Join-Path -Path $script:moduleRoot -ChildPath 'Public'
        $script:exportedCommands = @(Get-Command -Module DrunkenAD -CommandType Function | Sort-Object Name)

        function Assert-ExampleController {
            param([string]$Code)

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tokens, [ref]$errors)
            $errors | Should -BeNullOrEmpty
            $commands = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true))

            foreach ($invocation in $commands) {
                $command = $script:exportedCommands | Where-Object Name -eq $invocation.GetCommandName()
                if (-not $command) { continue }
                $parameterName = if ($command.Parameters.ContainsKey('DomainController')) {
                    'DomainController'
                } elseif ($command.Parameters.ContainsKey('Server')) {
                    'Server'
                } else { continue }

                $endpoints = @(
                    $elements = @($invocation.CommandElements)
                    for ($index = 1; $index -lt $elements.Count; $index++) {
                        $element = $elements[$index]
                        if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                            $element.ParameterName -eq $parameterName) {
                            $argument = if ($element.Argument) { $element.Argument } else { $elements[$index + 1] }
                            $argument.SafeGetValue()
                        } elseif ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) {
                            # Examples may use one literal, preceding splat; never execute example code.
                            $assignments = @($ast.EndBlock.Statements | Where-Object {
                                $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                                $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                                $_.Left.VariablePath.UserPath -eq $element.VariablePath.UserPath -and
                                $_.Extent.EndOffset -lt $invocation.Extent.StartOffset
                            })
                            $assignments.Count | Should -Be 1
                            $table = $assignments[0].Right.Expression
                            $table | Should -BeOfType ([System.Management.Automation.Language.HashtableAst])
                            foreach ($pair in $table.KeyValuePairs) {
                                if ($pair.Item1.SafeGetValue() -eq $parameterName) {
                                    $pair.Item2.PipelineElements.Count | Should -Be 1
                                    $value = $pair.Item2.PipelineElements[0].Expression
                                    $value | Should -BeOfType ([System.Management.Automation.Language.StringConstantExpressionAst])
                                    $value.Value
                                }
                            }
                        }
                    }
                )
                $endpoints.Count | Should -Be 1 -Because "'$($invocation.Extent.Text)' must name the common example DC"
                $endpoints[0] | Should -Be 'dc01.contoso.com'
            }
        }
    }

    It 'provides a module-level about topic for Get-Help discovery' {
        $aboutHelp = Get-Help about_DrunkenAD -ErrorAction Stop
        $aboutText = $aboutHelp | Out-String

        $aboutText | Should -Match 'DrunkenAD'
        $aboutText | Should -Match 'Get-Command -Module DrunkenAD'
        $aboutText | Should -Match 'Get-Help Set-ADUserDrinkData -Full'
        $aboutText | Should -Match 'CSV'
        $aboutText | Should -Match 'schema readiness'
    }

    It 'documents opt-in blank clearing and strict decoding in the about topic' {
        $aboutText = (Get-Help about_DrunkenAD -ErrorAction Stop | Out-String) -replace '\s+', ' '
        $aboutText | Should -Match 'Blank mapped namespaces are left unchanged by default'
        $aboutText | Should -Match 'ClearBlankNamespaces explicitly opts into clearing'
        $aboutText | Should -Match 'Invalid byte sequences fail before directory access'
        $aboutText | Should -Not -Match 'Every mapped namespace is replaced, including an empty replacement'
    }

    It 'keeps comment-based help directly attached to each public function' {
        $publicFiles = @(Get-ChildItem -LiteralPath $script:publicRoot -Filter '*.ps1' -File)

        foreach ($file in $publicFiles) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName,
                [ref]$tokens,
                [ref]$errors
            )
            $errors | Should -BeNullOrEmpty

            $functions = @($ast.FindAll(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                },
                $true
            ))
            $content = Get-Content -LiteralPath $file.FullName -Raw

            foreach ($function in $functions) {
                $pattern = '(?ms)<#(?<help>.*?)#>(\r?\n){{1,2}}function\s+{0}\b' -f [regex]::Escape($function.Name)
                $match = [regex]::Match($content, $pattern)
                $match.Success | Should -BeTrue

                $helpBlock = $match.Groups['help'].Value
                $helpBlock | Should -Match '\.SYNOPSIS'
                $helpBlock | Should -Match '\.DESCRIPTION'
                $helpBlock | Should -Match '\.INPUTS'
                $helpBlock | Should -Match '\.OUTPUTS'
                $helpBlock | Should -Match '\.LINK'
                $helpBlock | Should -Match '\.COMPONENT\s+DrunkenAD'
                $helpBlock | Should -Match '\.ROLE\s+'
                $helpBlock | Should -Match '\.FUNCTIONALITY\s+'
                $helpBlock | Should -Not -Match '\.EXTERNALHELP'
            }
        }
    }

    It 'provides complete Get-Help output for every exported command' {
        foreach ($command in $script:exportedCommands) {
            $help = Get-Help -Name $command.Name -Full -ErrorAction Stop
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Synopsis | Should -Not -Match '^Syntax|^Short description'
            @($help.Description.Text | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count | Should -BeGreaterThan 0
            $help.Component | Should -Be 'DrunkenAD'
            @($help.Role | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count | Should -BeGreaterThan 0
            $help.Functionality | Should -Not -BeNullOrEmpty

            $examples = @($help.Examples.Example)
            $examples.Count | Should -BeGreaterOrEqual 2
            $exampleCode = @($examples | ForEach-Object { [string]$_.Code }) -join [System.Environment]::NewLine
            $exampleCode | Should -Match ([regex]::Escape($command.Name))
            foreach ($example in $examples) {
                @($example.Remarks.Text | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count | Should -BeGreaterThan 0
            }

            $relatedLinkText = @($help.RelatedLinks.NavigationLink |
                ForEach-Object { $_.LinkText } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $relatedLinkText | Should -Contain 'about_DrunkenAD'
            $relatedLinkText.Count | Should -BeGreaterOrEqual 2
        }
    }

    It 'documents each explicit function parameter in Get-Help output' {
        foreach ($command in $script:exportedCommands) {
            $sourcePath = Join-Path -Path $script:publicRoot -ChildPath ('{0}.ps1' -f $command.Name)
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                $sourcePath = Get-ChildItem -LiteralPath $script:publicRoot -Filter '*.ps1' -File |
                    Where-Object {
                        (Get-Content -LiteralPath $_.FullName -Raw) -match ('function\s+{0}\b' -f [regex]::Escape($command.Name))
                    } |
                    Select-Object -First 1 -ExpandProperty FullName
            }

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $sourcePath,
                [ref]$tokens,
                [ref]$errors
            )
            $errors | Should -BeNullOrEmpty

            $function = $ast.Find(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                        $node.Name -eq $command.Name
                },
                $true
            )

            $explicitParameters = @($function.Body.ParamBlock.Parameters |
                ForEach-Object { $_.Name.VariablePath.UserPath } |
                Sort-Object -Unique)
            $help = Get-Help -Name $command.Name -Full -ErrorAction Stop

            foreach ($parameterName in $explicitParameters) {
                $helpParameter = @($help.Parameters.Parameter | Where-Object Name -eq $parameterName)
                $helpParameter.Count | Should -BeGreaterThan 0
                @($helpParameter.Description.Text | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count | Should -BeGreaterThan 0
            }
        }
    }

    It 'rejects examples whose DC is missing, implicit, or bound only to unrelated data' {
        foreach ($code in @(
            "Set-ADUserDrinkData -SamAccountName 'TesterAccount'",
            "Set-ADUserDrinkData -DomainController 'contoso.com'",
            "# -DomainController 'dc01.contoso.com'`nSet-ADUserDrinkData",
            "Set-ADUserDrinkData -DataMap @{ DomainController = 'dc01.contoso.com' }",
            '$other = @{ DomainController = ''dc01.contoso.com'' }; $params = @{ SamAccountName = ''TesterAccount'' }; Set-ADUserDrinkData @params',
            '$params = @{ DataMap = @{ DomainController = ''dc01.contoso.com'' } }; Set-ADUserDrinkData @params'
        )) {
            { Assert-ExampleController -Code $code } | Should -Throw
        }
    }

    It 'uses the same explicit DC hostname in every directory-command help example' {
        foreach ($command in $script:exportedCommands) {
            $help = Get-Help -Name $command.Name -Full -ErrorAction Stop
            foreach ($example in $help.Examples.Example) {
                Assert-ExampleController -Code $example.Code
            }
        }
    }

    It 'uses the same explicit DC hostname in the about workflows' {
        $aboutText = Get-Content -LiteralPath (Join-Path $script:moduleRoot 'en-US/about_DrunkenAD.help.txt') -Raw
        $lines = [regex]::Matches($aboutText, '(?m)^ {8}[^\r\n]*')
        $lines.Count | Should -BeGreaterThan 0
        Assert-ExampleController -Code (($lines | ForEach-Object Value) -join "`n")
    }

    It 'uses the same explicit DC hostname in current operator documentation' {
        foreach ($relativePath in @('README.md', 'docs/DATA-STORE.md', 'docs/OPERATIONS.md', 'docs/HOW-TO-INGEST-CSV.md')) {
            $content = Get-Content -LiteralPath (Join-Path $script:projectRoot $relativePath) -Raw
            $blocks = [regex]::Matches($content, '(?ms)^```powershell\r?\n(?<code>.*?)^```')
            $blocks.Count | Should -BeGreaterThan 0
            foreach ($block in $blocks) {
                Assert-ExampleController -Code $block.Groups['code'].Value
            }
        }
    }
}
