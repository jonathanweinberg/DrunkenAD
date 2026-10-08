Import-Module (Join-Path $PSScriptRoot '../DrunkenAD/DrunkenAD.psd1') -Force

BeforeAll {
    $script:originalSetADUser = Get-Item Function:\global:Set-ADUser -ErrorAction SilentlyContinue
    function global:Set-ADUser {
        param($Identity, $Server, $Remove, $Add, $Replace, $Clear, $Confirm, $ErrorAction)
        throw 'An unmocked directory write is not permitted in unit tests.'
    }
}

AfterAll {
    if ($script:originalSetADUser) {
        Set-Item Function:\global:Set-ADUser $script:originalSetADUser.ScriptBlock
    }
    else { Remove-Item Function:\global:Set-ADUser -ErrorAction SilentlyContinue }
}

Describe 'CSV confirmation state across rows' {
    BeforeAll {
        # A separate host exercises real ShouldProcess state without interactive input.
        if (-not ('DrunkenAD.Tests.CsvConfirmationHost' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;

namespace DrunkenAD.Tests {
    public sealed class CsvConfirmationHost : PSHost {
        private readonly Guid id = Guid.NewGuid();
        private readonly ChoiceUI ui;
        public CsvConfirmationHost(string choice) { ui = new ChoiceUI(choice); }
        public int PromptCount { get { return ui.PromptCount; } }
        public override Guid InstanceId { get { return id; } }
        public override string Name { get { return "CsvConfirmationTest"; } }
        public override Version Version { get { return new Version(1, 0); } }
        public override PSHostUserInterface UI { get { return ui; } }
        public override CultureInfo CurrentCulture { get { return CultureInfo.GetCultureInfo("en-US"); } }
        public override CultureInfo CurrentUICulture { get { return CurrentCulture; } }
        public override void EnterNestedPrompt() { throw new NotSupportedException(); }
        public override void ExitNestedPrompt() { throw new NotSupportedException(); }
        public override void SetShouldExit(int exitCode) { throw new NotSupportedException(); }
        public override void NotifyBeginApplication() { }
        public override void NotifyEndApplication() { }

        private sealed class ChoiceUI : PSHostUserInterface {
            private readonly string choice;
            public int PromptCount { get; private set; }
            public ChoiceUI(string choice) { this.choice = choice; }
            public override PSHostRawUserInterface RawUI { get { return null; } }
            public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) {
                PromptCount++;
                for (int i = 0; i < choices.Count; i++) {
                    if (String.Equals(choices[i].Label.Replace("&", ""), choice, StringComparison.OrdinalIgnoreCase)) { return i; }
                }
                throw new InvalidOperationException("Expected confirmation choice was not offered: " + choice);
            }
            public override string ReadLine() { throw new NotSupportedException(); }
            public override SecureString ReadLineAsSecureString() { throw new NotSupportedException(); }
            public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions) { throw new NotSupportedException(); }
            public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName) { throw new NotSupportedException(); }
            public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName, PSCredentialTypes types, PSCredentialUIOptions options) { throw new NotSupportedException(); }
            public override void Write(string value) { }
            public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value) { }
            public override void WriteLine(string value) { }
            public override void WriteErrorLine(string value) { }
            public override void WriteDebugLine(string value) { }
            public override void WriteProgress(long sourceId, ProgressRecord record) { }
            public override void WriteVerboseLine(string value) { }
            public override void WriteWarningLine(string value) { }
        }
    }
}
'@
        }
        $script:csvConfirmationModulePath = Join-Path $PSScriptRoot '../DrunkenAD/DrunkenAD.psd1'
        $script:csvConfirmationPath = Join-Path $TestDrive 'confirmation.csv'
        @(
            [pscustomobject]@{ SamAccountName = 'first'; Tier = 'Gold' }
            [pscustomobject]@{ SamAccountName = 'second'; Tier = 'Silver' }
        ) | Export-Csv -LiteralPath $script:csvConfirmationPath -NoTypeInformation
    }

    It 'honors <Choice> for both CSV rows with one prompt and <ExpectedWrites> writes' -TestCases @(
        @{ Choice = 'Yes to All'; ExpectedWrites = 2 }
        @{ Choice = 'No to All'; ExpectedWrites = 0 }
    ) {
        param($Choice, $ExpectedWrites)

        $confirmationHost = New-Object DrunkenAD.Tests.CsvConfirmationHost -ArgumentList $Choice
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($confirmationHost)
        $pipeline = [powershell]::Create()
        try {
            $runspace.Open()
            $pipeline.Runspace = $runspace
            $scenario = {
                param($ModulePath, $CsvPath)
                $ErrorActionPreference = 'Stop'
                $ConfirmPreference = 'High'
                $module = Import-Module $ModulePath -Force -PassThru
                $PSModuleAutoLoadingPreference = 'None'
                & $module {
                    $script:csvTestWrites = New-Object 'System.Collections.Generic.List[object]'
                    function script:Get-DrunkenADDrinkAttributeStatus {
                        param($Server)
                        [pscustomobject]@{ ReadyForUserWrite = $true; Server = 'dc01.example.test'; RangeUpper = 256 }
                    }
                    function script:Resolve-DrunkenADUser {
                        param($SamAccountName, $Server, $Properties)
                        [pscustomobject]@{
                            SamAccountName = $SamAccountName
                            DistinguishedName = "CN=$SamAccountName,DC=example,DC=test"
                            drink = @('Tier-old', 'Keep-stable')
                        }
                    }
                    function script:Set-ADUser {
                        param($Identity, $Server, $Remove, $Add, $Replace, $Clear, $Confirm, $ErrorAction)
                        $script:csvTestWrites.Add([pscustomobject]@{
                            Identity = $Identity; Server = $Server
                            Remove = @($Remove.drink); Add = @($Add.drink)
                            Confirm = [bool]$Confirm
                        })
                    }
                }
                $rows = @(Import-ADUserDrinkCsvData -CsvPath $CsvPath -NamespaceMap @{ 'Tier-' = @(@{ Column = 'Tier' }) } -Confirm)
                [pscustomobject]@{
                    Rows = $rows
                    Writes = @(& $module { $script:csvTestWrites.ToArray() })
                }
            }
            [void]$pipeline.AddScript($scenario.ToString()).AddArgument($script:csvConfirmationModulePath).AddArgument($script:csvConfirmationPath)
            $pending = $pipeline.BeginInvoke()
            $pending.AsyncWaitHandle.WaitOne(15000) | Should -BeTrue -Because 'the synthetic import must finish without interactive input'
            $output = @($pipeline.EndInvoke($pending))
            $pipeline.Streams.Error.Count | Should -Be 0 -Because ($pipeline.Streams.Error -join '; ')
            $output.Count | Should -Be 1
            $result = $output[0]

            $confirmationHost.PromptCount | Should -Be 1
            $result.Writes.Count | Should -Be $ExpectedWrites
            $result.Rows.Count | Should -Be 2
            $result.Rows[0].SamAccountName | Should -BeExactly 'first'
            $result.Rows[1].SamAccountName | Should -BeExactly 'second'
            $result.Rows[0].FinalDrinkValues | Should -Be @('Keep-stable', 'Tier-Gold')
            $result.Rows[1].FinalDrinkValues | Should -Be @('Keep-stable', 'Tier-Silver')
            if ($ExpectedWrites -gt 0) {
                $result.Writes[0].Identity | Should -BeExactly 'CN=first,DC=example,DC=test'
                $result.Writes[1].Identity | Should -BeExactly 'CN=second,DC=example,DC=test'
                $result.Writes[0].Add | Should -Be @('Tier-Gold')
                $result.Writes[1].Add | Should -Be @('Tier-Silver')
                foreach ($write in $result.Writes) {
                    $write.Server | Should -BeExactly 'dc01.example.test'
                    $write.Remove | Should -Be @('Tier-old')
                    $write.Confirm | Should -BeFalse
                }
            }
        }
        finally {
            $pipeline.Stop()
            $pipeline.Dispose()
            $runspace.Dispose()
        }
    }
}

Describe 'DrunkenAD write operation contracts' {
    InModuleScope DrunkenAD {
        BeforeEach {
            $script:directoryValues = @('Alpha-old', 'Keep-stable')
            Mock Get-DrunkenADDrinkAttributeStatus {
                [pscustomobject]@{ ReadyForUserWrite = $true; Server = 'dc01.example.test'; RangeUpper = 256 }
            }
            Mock Resolve-DrunkenADUser {
                param($SamAccountName)
                [pscustomobject]@{
                    SamAccountName = $SamAccountName
                    DistinguishedName = "CN=$SamAccountName,DC=example,DC=test"
                    drink = @($script:directoryValues)
                    department = 'Engineering'
                }
            }
            Mock Set-ADUser {
                param($Remove, $Add)
                if ($Remove) { $script:directoryValues = @($script:directoryValues | Where-Object { $Remove.drink -cnotcontains $_ }) }
                if ($Add) { $script:directoryValues += @($Add.drink) }
            }
        }

        It 'preserves another namespace added between the read and write' {
            Mock Set-ADUser {
                param($Remove, $Add)
                $script:directoryValues += 'Concurrent-new'
                $script:directoryValues = @($script:directoryValues | Where-Object { $Remove.drink -cnotcontains $_ }) + @($Add.drink)
            }
            Set-ADUserDrinkData -SamAccountName 'demo' -DataMap @{ 'Alpha-' = @('new') } -Confirm:$false
            $script:directoryValues | Should -Contain 'Concurrent-new'
            $script:directoryValues | Should -Contain 'Keep-stable'
            $script:directoryValues | Should -Contain 'Alpha-new'
            $script:directoryValues | Should -Not -Contain 'Alpha-old'
            Assert-MockCalled Set-ADUser -Times 1 -Exactly -ParameterFilter {
                $Server -eq 'dc01.example.test' -and -not $Replace -and -not $Clear -and
                @($Remove.drink).Count -eq 1 -and @($Add.drink).Count -eq 1
            }
        }

        It 'removes the last observed value without clearing a concurrent addition' {
            $script:directoryValues = @('Alpha-old')
            Mock Set-ADUser {
                param($Remove)
                $script:directoryValues += 'Concurrent-new'
                $script:directoryValues = @($script:directoryValues | Where-Object { $Remove.drink -cnotcontains $_ })
            }
            Remove-ADUserDrinkData -SamAccountName 'demo' -Prefixes 'Alpha-' -Confirm:$false
            $script:directoryValues | Should -Be @('Concurrent-new')
            Assert-MockCalled Set-ADUser -Times 1 -Exactly -ParameterFilter { -not $Clear -and -not $Replace -and -not $Add }
        }

        It 'writes a requested case-only payload change' {
            $script:directoryValues = @('Alpha-VALUE')
            Set-ADUserDrinkData -SamAccountName 'demo' -DataMap @{ 'Alpha-' = @('Value') } -Confirm:$false
            Assert-MockCalled Set-ADUser -Times 1 -Exactly -ParameterFilter {
                $Remove.drink[0] -ceq 'Alpha-VALUE' -and $Add.drink[0] -ceq 'Alpha-Value'
            }
        }

        It 'deduplicates desired values with ordinal case-insensitive semantics' {
            $plan = Get-DrunkenADPrefixWritePlan -CurrentValues @() -PrefixMap @{ 'Alpha-' = @('Same', 'same') } -RangeUpper 256
            @($plan.Add).Count | Should -Be 1
            $plan.Add[0] | Should -BeExactly 'Alpha-Same'
        }

        It 'does not write an unchanged value set' {
            Set-ADUserDrinkData -SamAccountName 'demo' -DataMap @{ 'Alpha-' = @('old') } -Confirm:$false
            Assert-MockCalled Set-ADUser -Times 0
        }

        It 'checks readiness only once through the generic and legacy wrapper chains' {
            Set-ADUserDrinkData -SamAccountName 'demo' -DataMap @{ 'Alpha-' = @('first') } -Confirm:$false
            Assert-MockCalled Get-DrunkenADDrinkAttributeStatus -Times 1 -Exactly
            Remove-ADUserDrinkData -SamAccountName 'demo' -Prefixes 'Alpha-' -Confirm:$false
            Assert-MockCalled Get-DrunkenADDrinkAttributeStatus -Times 2 -Exactly
            Update-ADUserDrinkAttribute -SamAccountName 'demo' -Prefixes 'Alpha-' -DrinkValues 'last' -AutoConfirm
            Assert-MockCalled Get-DrunkenADDrinkAttributeStatus -Times 3 -Exactly
        }

        It 'pins the discovered controller for user lookup and write' {
            Set-ADUserDrinkData -SamAccountName 'demo' -DataMap @{ 'Alpha-' = @('new') } -Confirm:$false
            Assert-MockCalled Resolve-DrunkenADUser -Times 1 -Exactly -ParameterFilter { $Server -eq 'dc01.example.test' }
            Assert-MockCalled Set-ADUser -Times 1 -Exactly -ParameterFilter { $Server -eq 'dc01.example.test' }
        }

        It 'rejects a value above the schema limit including its prefix before writing' {
            Mock Get-DrunkenADDrinkAttributeStatus {
                [pscustomobject]@{ ReadyForUserWrite = $true; Server = 'dc01.example.test'; RangeUpper = 8 }
            }
            { Set-ADUserDrinkData -SamAccountName 'demo' -DataMap @{ 'Alpha-' = @('new') } -Confirm:$false } | Should -Throw '*at most 8*including the prefix*'
            Assert-MockCalled Set-ADUser -Times 0
            Set-ADUserDrinkData -SamAccountName 'demo' -DataMap @{ 'Alpha-' = @('ok') } -Confirm:$false
            Assert-MockCalled Set-ADUser -Times 1 -Exactly
        }

        It 'returns a projection preview without writes and resolves the user only once' {
            $result = Set-ADUserDrinkProjection -SamAccountName 'demo' -AttributeMap @{ 'Org-' = @('department') } -WhatIf -PassThru
            $result.DataMap['Org-'] | Should -Be @('department=Engineering')
            $result.FinalDrinkValues | Should -Contain 'Org-department=Engineering'
            Assert-MockCalled Resolve-DrunkenADUser -Times 1 -Exactly
            Assert-MockCalled Get-DrunkenADDrinkAttributeStatus -Times 1 -Exactly
            Assert-MockCalled Set-ADUser -Times 0
        }

        It 'uses the resolved object for a projection write' {
            Set-ADUserDrinkProjection -SamAccountName 'demo' -AttributeMap @{ 'Org-' = @('department') } -Confirm:$false
            Assert-MockCalled Resolve-DrunkenADUser -Times 1 -Exactly
            Assert-MockCalled Get-DrunkenADDrinkAttributeStatus -Times 1 -Exactly
            Assert-MockCalled Set-ADUser -Times 1 -Exactly -ParameterFilter { $Identity -eq 'CN=demo,DC=example,DC=test' }
        }

        It 'honors WhatIf through every write wrapper including AutoConfirm' {
            Set-ADUserDrinkData -SamAccountName 'demo' -DataMap @{ 'Alpha-' = @('new') } -WhatIf
            Remove-ADUserDrinkData -SamAccountName 'demo' -Prefixes 'Alpha-' -WhatIf
            Update-ADUserDrinkAttribute -SamAccountName 'demo' -Prefixes 'Alpha-' -DrinkValues 'new' -AutoConfirm -WhatIf
            Assert-MockCalled Set-ADUser -Times 0
        }

        It 'logs counts without attribute payloads or account identity' {
            $logPath = Join-Path $TestDrive 'activity.log'
            Set-ADUserDrinkData -SamAccountName 'sensitive-account' -DataMap @{ 'Alpha-' = @('private-payload') } -LogPath $logPath -Confirm:$false
            $log = Get-Content -LiteralPath $logPath -Raw
            $log | Should -Match 'removed 1, added 1'
            $log | Should -Not -Match 'sensitive-account|private-payload|Keep-stable'
            (Resolve-DrunkenADLogPath -EnableLogging) | Should -Not -Be (Resolve-DrunkenADLogPath -EnableLogging)
        }

        Context 'CSV preflight and failure progress' {
            BeforeEach {
                Mock Test-Path { $true }
                Mock Import-Csv {
                    @(
                        [pscustomobject]@{ SamAccountName = 'first'; Tier = 'Gold' }
                        [pscustomobject]@{ SamAccountName = 'second'; Tier = 'Silver' }
                    )
                }
            }

            It 'makes no writes when a later input row cannot resolve uniquely' {
                Mock Resolve-DrunkenADUser { throw 'The lookup matched 2 users.' } -ParameterFilter { $SamAccountName -eq 'second' }
                { Import-ADUserDrinkCsvData -CsvPath 'users.csv' -NamespaceMap @{ 'Tier-' = @(@{ Column = 'Tier' }) } -Confirm:$false } | Should -Throw '*matched 2 users*'
                Assert-MockCalled Set-ADUser -Times 0
            }

            It 'validates every row length before any write' {
                Mock Import-Csv {
                    @(
                        [pscustomobject]@{ SamAccountName = 'first'; Tier = 'Gold' }
                        [pscustomobject]@{ SamAccountName = 'second'; Tier = ('x' * 256) }
                    )
                }
                { Import-ADUserDrinkCsvData -CsvPath 'users.csv' -NamespaceMap @{ 'Tier-' = @(@{ Column = 'Tier' }) } -Confirm:$false } | Should -Throw '*at most 256*'
                Assert-MockCalled Set-ADUser -Times 0
            }

            It 'uses one schema check and one user lookup per CSV row' {
                $result = @(Import-ADUserDrinkCsvData -CsvPath 'users.csv' -NamespaceMap @{ 'Tier-' = @(@{ Column = 'Tier' }) } -Confirm:$false)
                $result.Count | Should -Be 2
                Assert-MockCalled Get-DrunkenADDrinkAttributeStatus -Times 1 -Exactly
                Assert-MockCalled Resolve-DrunkenADUser -Times 2 -Exactly
                Assert-MockCalled Set-ADUser -Times 2 -Exactly
            }

            It 'attaches completed and pending row counts when a write fails' {
                Mock Set-ADUser { throw 'Synthetic write failure' } -ParameterFilter { $Identity -eq 'CN=second,DC=example,DC=test' }
                $failure = $null
                try {
                    Import-ADUserDrinkCsvData -CsvPath 'users.csv' -NamespaceMap @{ 'Tier-' = @(@{ Column = 'Tier' }) } -Confirm:$false | Out-Null
                }
                catch { $failure = $_ }
                $failure | Should -Not -BeNullOrEmpty
                $failure.FullyQualifiedErrorId | Should -Match 'DrunkenADCsvWriteFailed'
                $failure.TargetObject.CompletedRowCount | Should -Be 1
                $failure.TargetObject.FailedRowNumber | Should -Be 3
                $failure.TargetObject.PendingRowCount | Should -Be 0
            }
        }
    }
}
