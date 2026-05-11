$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../DrunkenAD/DrunkenAD.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Describe 'DrunkenAD comment-based help contract' {
    BeforeAll {
        $script:projectRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:modulePath = Join-Path -Path $script:projectRoot -ChildPath 'DrunkenAD/DrunkenAD.psd1'
        $script:moduleRoot = Split-Path -Path $script:modulePath -Parent
        $script:publicRoot = Join-Path -Path $script:moduleRoot -ChildPath 'Public'
        $script:exportedCommands = @(Get-Command -Module DrunkenAD -CommandType Function | Sort-Object Name)
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
            foreach ($example in $examples) {
                $example.Code | Should -Match $command.Name
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
}
