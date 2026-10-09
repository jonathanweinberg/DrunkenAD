BeforeAll {
    . (Join-Path $PSScriptRoot '../DrunkenAD/Private/Core.ps1')
    . (Join-Path $PSScriptRoot '../DrunkenAD/Private/PrefixMap.ps1')
    . (Join-Path $PSScriptRoot '../DrunkenAD/Private/WriteOperation.ps1')

    function Set-ADUser {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param([string]$Identity, [string]$Server, [hashtable]$Add, [hashtable]$Remove)
        throw 'Unmocked directory write is forbidden.'
    }

    function Invoke-LogPreview {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param([string]$Path, [switch]$DirectDefault)

        if ($DirectDefault) {
            Write-DrunkenADDefaultLog -LogPath $Path -Message 'No drink attribute changes were required.'
        }
        else {
            Write-DrunkenADLog -LogPath $Path -Message 'No drink attribute changes were required.'
        }
    }
}

Describe 'Bounded default logging' {
    BeforeEach {
        $script:DrunkenADDefaultLogPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '/activity.log')
        $script:logPath = $script:DrunkenADDefaultLogPath
    }

    It 'reuses the default path and preserves an explicit path' {
        $first = Resolve-DrunkenADLogPath -EnableLogging
        Resolve-DrunkenADLogPath -EnableLogging | Should -Be $first
        Resolve-DrunkenADLogPath -LogPath 'caller.log' -EnableLogging | Should -Be 'caller.log'
        Resolve-DrunkenADLogPath | Should -BeNullOrEmpty
    }

    It 'disables automatic logging with a warning when the personal log root is unavailable' {
        Mock Get-DrunkenADLogRoot { '' }
        $warnings = @()
        $path = Resolve-DrunkenADLogPath -EnableLogging -WarningVariable warnings -WarningAction Stop

        $path | Should -BeNullOrEmpty
        $warnings.Count | Should -Be 1
        $warnings[0].ToString() | Should -Match 'Specify -LogPath'
        $warnings[0].ToString() | Should -Match 'does not change the directory operation outcome'
        Should -Invoke Get-DrunkenADLogRoot -Times 1 -Exactly
    }

    It 'honors explicit log paths without requiring a personal log root' {
        Mock Get-DrunkenADLogRoot { throw 'Personal log root lookup should not run.' }
        $explicit = Join-Path $TestDrive 'explicit-without-personal-root.log'

        Resolve-DrunkenADLogPath -LogPath $explicit -EnableLogging | Should -Be $explicit
        Should -Invoke Get-DrunkenADLogRoot -Times 0 -Exactly
    }

    It 'honors <Action> suppression when the default root is unavailable' -ForEach @(
        @{ Action = 'SilentlyContinue' }, @{ Action = 'Ignore' }
    ) {
        Mock Get-DrunkenADLogRoot { '' }
        Mock Write-Warning {}
        Resolve-DrunkenADLogPath -EnableLogging -WarningAction $Action | Should -BeNullOrEmpty
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $WarningAction -eq $Action }
    }

    It 'correlates repeated entries without logging user data' {
        Write-DrunkenADLog -LogPath $script:logPath -Message 'Added 2 values.'
        Write-DrunkenADLog -LogPath $script:logPath -Message 'Removed 1 values.'
        $lines = @(Get-Content $script:logPath)
        $lines.Count | Should -Be 3
        $lines[0] | Should -Be '# DrunkenAD bounded log v1'
        $firstSession = [regex]::Match($lines[1], 'session=([a-f0-9]{32})').Groups[1].Value
        $firstSession | Should -Not -BeNullOrEmpty
        $lines[2] | Should -Match ('session=' + $firstSession)
    }

    It 'retains only two size-bounded owned files across repeated rotations' {
        New-Item (Split-Path $script:logPath -Parent) -ItemType Directory -Force | Out-Null
        $unrelated = Join-Path (Split-Path $script:logPath -Parent) 'unrelated.txt'
        Set-Content $unrelated 'must survive'
        $payload = 'x' * 524200
        foreach ($number in 1..8) { Write-DrunkenADLog -LogPath $script:logPath -Message $payload }
        $files = @(Get-ChildItem (Split-Path $script:logPath -Parent) -Filter '*.log' -File)
        $files.Count | Should -Be 2
        Get-Content $unrelated | Should -Be 'must survive'
        foreach ($file in $files) {
            $file.Length | Should -BeLessOrEqual 1048576
            Get-Content $file.FullName -TotalCount 1 | Should -Be '# DrunkenAD bounded log v1'
        }
    }

    It 'refuses an unowned active file without changing it' {
        New-Item (Split-Path $script:logPath -Parent) -ItemType Directory -Force | Out-Null
        Set-Content $script:logPath 'unrelated file'
        { Write-DrunkenADDefaultLog -LogPath $script:logPath -Message 'Added 1 values.' } | Should -Throw '*not owned*'
        Get-Content $script:logPath | Should -Be 'unrelated file'
    }

    It 'preserves both default files when inherited WhatIf would otherwise require rotation' {
        New-Item (Split-Path $script:logPath -Parent) -ItemType Directory -Force | Out-Null
        $archive = Join-Path (Split-Path $script:logPath -Parent) 'activity.previous.log'
        $header = '# DrunkenAD bounded log v1' + [Environment]::NewLine
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($script:logPath, $header + ('x' * (1048576 - $encoding.GetByteCount($header))), $encoding)
        [IO.File]::WriteAllText($archive, $header + 'previous entries', $encoding)
        $activeBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:logPath))
        $archiveBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($archive))

        Invoke-LogPreview -Path $script:logPath -WhatIf
        Invoke-LogPreview -Path $script:logPath -DirectDefault -WhatIf

        [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:logPath)) | Should -BeExactly $activeBefore
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($archive)) | Should -BeExactly $archiveBefore
        @(Get-ChildItem (Split-Path $script:logPath -Parent) -File).Count | Should -Be 2
    }

    It 'preserves explicit log bytes under inherited WhatIf' {
        $explicit = Join-Path $TestDrive 'preview-explicit.log'
        $original = [byte[]]@(0, 1, 2, 127, 128, 255)
        [IO.File]::WriteAllBytes($explicit, $original)

        Invoke-LogPreview -Path $explicit -WhatIf

        [Convert]::ToBase64String([IO.File]::ReadAllBytes($explicit)) | Should -BeExactly ([Convert]::ToBase64String($original))
    }

    It 'does not create default or explicit logs during a preview' {
        $explicit = Join-Path $TestDrive 'absent-preview/explicit.log'
        Invoke-LogPreview -Path $script:logPath -WhatIf
        Invoke-LogPreview -Path $script:logPath -DirectDefault -WhatIf
        Invoke-LogPreview -Path $explicit -WhatIf

        Test-Path (Split-Path $script:logPath -Parent) | Should -BeFalse
        Test-Path (Split-Path $explicit -Parent) | Should -BeFalse
    }

    It 'performs no log filesystem inspection or writes during preview' {
        Mock Assert-DrunkenADLogNotLinked { throw 'Preview must not inspect paths.' }
        Mock Get-Item { throw 'Preview must not inspect files.' }
        Mock Add-Content { throw 'Preview must not write files.' }
        Invoke-LogPreview -Path $script:logPath -WhatIf
        Invoke-LogPreview -Path $script:logPath -DirectDefault -WhatIf
        Invoke-LogPreview -Path (Join-Path $TestDrive 'explicit.log') -WhatIf
        Should -Invoke Assert-DrunkenADLogNotLinked -Times 0 -Exactly
        Should -Invoke Get-Item -Times 0 -Exactly
        Should -Invoke Add-Content -Times 0 -Exactly
    }

    It 'refuses an unowned archive even before rotation' {
        New-Item (Split-Path $script:logPath -Parent) -ItemType Directory -Force | Out-Null
        $archive = Join-Path (Split-Path $script:logPath -Parent) 'activity.previous.log'
        Set-Content $archive 'unrelated archive'
        { Write-DrunkenADDefaultLog -LogPath $script:logPath -Message 'Added 1 values.' } | Should -Throw '*not owned*'
        Get-Content $archive | Should -Be 'unrelated archive'
        Test-Path $script:logPath | Should -BeFalse
    }

    It 'rejects oversized entries before creating any files' {
        { Write-DrunkenADDefaultLog -LogPath $script:logPath -Message ('x' * 1048576) } | Should -Throw '*size limit*'
        Test-Path $script:logPath | Should -BeFalse
    }

    It 'does not rotate or truncate explicit caller-managed logs' {
        $explicit = Join-Path $TestDrive 'explicit.log'
        Set-Content $explicit ('x' * 1048576)
        Write-DrunkenADLog -LogPath $explicit -Message 'Added 1 values.'
        (Get-Item $explicit).Length | Should -BeGreaterThan 1048576
        Get-Content $explicit -Tail 1 | Should -Match 'Added 1 values\.'
    }

    It 'rejects a linked ancestor without touching its target' {
        $target = Join-Path $TestDrive 'target'
        $link = Join-Path $TestDrive 'linked'
        New-Item $target -ItemType Directory -Force | Out-Null
        # A junction needs no elevation on Windows; Unix uses a symbolic link.
        $linkType = if ($env:OS -eq 'Windows_NT') { 'Junction' } else { 'SymbolicLink' }
        New-Item $link -ItemType $linkType -Target $target -ErrorAction Stop | Out-Null
        { Assert-DrunkenADLogNotLinked (Join-Path $link 'explicit.log') } | Should -Throw '*links*'
        @(Get-ChildItem $target).Count | Should -Be 0
    }

    It 'warns rather than invalidating a completed operation when logging fails' {
        Mock Write-DrunkenADDefaultLog { throw 'Synthetic disk failure containing private information' }
        $script:logWarnings = @()
        { Write-DrunkenADLog -LogPath $script:logPath -Message 'Added 1 values.' -WarningVariable script:logWarnings -WarningAction Stop } | Should -Not -Throw
        $script:logWarnings.Count | Should -Be 1
        $script:logWarnings[0].ToString() | Should -Match 'does not change the directory operation outcome'
        $script:logWarnings[0].ToString() | Should -Not -Match 'private information'
    }

    It 'honors <Action> suppression for failed <Kind> logging' -ForEach @(
        @{ Action = 'SilentlyContinue'; Kind = 'default' }
        @{ Action = 'Ignore'; Kind = 'default' }
        @{ Action = 'SilentlyContinue'; Kind = 'explicit' }
        @{ Action = 'Ignore'; Kind = 'explicit' }
    ) {
        Mock Write-DrunkenADDefaultLog { throw 'Private failure details' }
        Mock Assert-DrunkenADLogNotLinked { throw 'Private failure details' }
        Mock Write-Warning {}
        $path = if ($Kind -eq 'default') { $script:logPath } else { Join-Path $TestDrive 'caller.log' }
        { Write-DrunkenADLog -LogPath $path -Message 'Added 1 values.' -WarningAction $Action } | Should -Not -Throw
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter {
            $WarningAction -eq $Action -and $Message -notmatch 'Private failure details'
        }
    }

    It 'refuses the macOS var alias without creating fallback logs' -Skip:($env:OS -eq 'Windows_NT' -or -not (Test-Path '/private/var')) {
        { Assert-DrunkenADLogNotLinked '/var/tmp/DrunkenAD/logs-v1/activity.log' } | Should -Throw '*links*'
    }
}

Describe 'Account-correlated count-only write logging' {
    BeforeEach {
        $script:DrunkenADDefaultLogPath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '/activity.log')
        $script:writeLogPath = $script:DrunkenADDefaultLogPath
        $script:accountGuid = [guid]'11111111-2222-3333-4444-555555555555'
        $script:logUser = [pscustomobject]@{
            ObjectGUID = $script:accountGuid
            SamAccountName = 'synthetic-private-account'
            DistinguishedName = 'CN=synthetic-private-account,DC=example,DC=invalid'
            drink = @('Example-old-private-payload', 'Other-preserved-private-payload')
        }
        $script:logContext = [pscustomobject]@{ ReadyForUserWrite = $true; Server = 'dc.example.invalid'; RangeUpper = 1024 }
        Mock Set-ADUser {}
    }

    It 'logs only the canonical account GUID and counts for completed writes' {
        $result = Invoke-DrunkenADPrefixWrite -User $script:logUser -PrefixMap @{ 'Example-' = @('new-private-payload') } -Context $script:logContext -LogPath $script:writeLogPath -ResultObject -Confirm:$false
        $result.Status | Should -Be 'Written'
        $line = Get-Content $script:writeLogPath -Tail 1
        $line | Should -Match ('objectGUID=' + [regex]::Escape($script:accountGuid.ToString('D')))
        $line | Should -Match 'removed 1, added 1'
        $line | Should -Not -Match 'private-account|private-payload|example\.invalid|DC=|Example-'
        Should -Invoke Set-ADUser -Times 1 -Exactly
    }

    It 'correlates a no-change outcome with zero counts without writing AD' {
        $result = Invoke-DrunkenADPrefixWrite -User $script:logUser -PrefixMap @{ 'Example-' = @('old-private-payload') } -Context $script:logContext -LogPath $script:writeLogPath -ResultObject -Confirm:$false
        $result.Status | Should -Be 'NoChange'
        $line = Get-Content $script:writeLogPath -Tail 1
        $line | Should -Match ('objectGUID=' + [regex]::Escape($script:accountGuid.ToString('D')))
        $line | Should -Match 'removed 0, added 0'
        $line | Should -Not -Match 'private-account|private-payload'
        Should -Invoke Set-ADUser -Times 0 -Exactly
    }

    It 'uses an honest unavailable marker for <Kind> GUIDs without leaking their content' -ForEach @(
        @{ Kind = 'missing' }, @{ Kind = 'invalid' }, @{ Kind = 'empty' }
    ) {
        switch ($Kind) {
            'missing' { $script:logUser.PSObject.Properties.Remove('ObjectGUID') }
            'invalid' { $script:logUser.ObjectGUID = "invalid-private-payload`r`nforged log entry" }
            'empty' { $script:logUser.ObjectGUID = [guid]::Empty }
        }
        Invoke-DrunkenADPrefixWrite -User $script:logUser -PrefixMap @{ 'Example-' = @('new-private-payload') } -Context $script:logContext -LogPath $script:writeLogPath -Confirm:$false
        $lines = @(Get-Content $script:writeLogPath)
        $lines.Count | Should -Be 2
        $lines[1] | Should -Match 'objectGUID=unavailable'
        $lines[1] | Should -Not -Match 'private-payload|forged log entry|private-account'
    }

    It 'keeps the Written outcome after a log failure under <Action>' -ForEach @(
        @{ Action = 'Stop' }, @{ Action = 'SilentlyContinue' }, @{ Action = 'Ignore' }
    ) {
        Mock Write-DrunkenADDefaultLog { throw 'Synthetic private disk failure' }
        Mock Write-Warning {}
        $result = Invoke-DrunkenADPrefixWrite -User $script:logUser -PrefixMap @{ 'Example-' = @('new-private-payload') } -Context $script:logContext -LogPath $script:writeLogPath -ResultObject -Confirm:$false -WarningAction $Action
        $result.Status | Should -Be 'Written'
        Should -Invoke Set-ADUser -Times 1 -Exactly
        $expectedAction = if ($Action -eq 'Stop') { 'Continue' } else { $Action }
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $WarningAction -eq $expectedAction }
    }

    It 'does not log previews or failed directory writes' {
        Mock Write-DrunkenADLog {}
        Invoke-DrunkenADPrefixWrite -User $script:logUser -PrefixMap @{ 'Example-' = @('new-private-payload') } -Context $script:logContext -LogPath $script:writeLogPath -WhatIf
        Should -Invoke Set-ADUser -Times 0 -Exactly
        Should -Invoke Write-DrunkenADLog -Times 0 -Exactly
        Mock Set-ADUser { throw 'Synthetic directory failure' }
        { Invoke-DrunkenADPrefixWrite -User $script:logUser -PrefixMap @{ 'Example-' = @('new-private-payload') } -Context $script:logContext -LogPath $script:writeLogPath -Confirm:$false } | Should -Throw '*Synthetic directory failure*'
        Should -Invoke Write-DrunkenADLog -Times 0 -Exactly
    }
}

Describe 'Public write warning preferences' {
    BeforeAll {
        $script:loggingPublicModule = Import-Module (Join-Path $PSScriptRoot '../DrunkenAD/DrunkenAD.psd1') -Force -Global -PassThru -ErrorAction Stop
        & $script:loggingPublicModule {
            function script:Set-ADUser {
                [CmdletBinding(SupportsShouldProcess = $true)]
                param([string]$Identity, [string]$Server, [hashtable]$Add, [hashtable]$Remove)
                throw 'Unmocked directory write is forbidden.'
            }
        }
    }

    AfterAll {
        & $script:loggingPublicModule { Remove-Item Function:Set-ADUser -ErrorAction Stop }
    }

    BeforeEach {
        Mock New-DrunkenADWriteContext -ModuleName DrunkenAD {
            [pscustomobject]@{ ReadyForUserWrite = $true; Server = 'dc.example.invalid'; RangeUpper = 1024 }
        }
        Mock Resolve-DrunkenADUser -ModuleName DrunkenAD {
            [pscustomobject]@{
                ObjectGUID = [guid]'11111111-2222-3333-4444-555555555555'
                SamAccountName = 'synthetic-account'
                DistinguishedName = 'CN=synthetic-account,DC=example,DC=invalid'
                drink = @('Example-old')
            }
        }
        Mock Set-ADUser -ModuleName DrunkenAD {}
        Mock Assert-DrunkenADLogNotLinked -ModuleName DrunkenAD { throw 'Synthetic private logging failure' }
    }

    It 'preserves public PassThru and <Action> after a completed write with failed logging' -ForEach @(
        @{ Action = 'Stop' }, @{ Action = 'SilentlyContinue' }, @{ Action = 'Ignore' }
    ) {
        Mock Write-Warning -ModuleName DrunkenAD {}
        $values = @(Set-ADUserDrinkPrefixedData -SamAccountName 'synthetic-account' -PrefixMap @{ 'Example-' = @('new') } -LogPath (Join-Path $TestDrive 'caller.log') -PassThru -Confirm:$false -WarningAction $Action)
        $values | Should -Contain 'Example-new'
        Should -Invoke Set-ADUser -ModuleName DrunkenAD -Times 1 -Exactly
        $expectedAction = if ($Action -eq 'Stop') { 'Continue' } else { $Action }
        Should -Invoke Write-Warning -ModuleName DrunkenAD -Times 1 -Exactly -ParameterFilter { $WarningAction -eq $expectedAction }
    }

    It 'does not throw after a completed public write when the real warning stream is set to Stop' {
        $script:publicWrittenValues = @()
        {
            $script:publicWrittenValues = @(Set-ADUserDrinkPrefixedData -SamAccountName 'synthetic-account' -PrefixMap @{ 'Example-' = @('new') } -LogPath (Join-Path $TestDrive 'caller.log') -PassThru -Confirm:$false -WarningAction Stop)
        } | Should -Not -Throw
        $script:publicWrittenValues | Should -Contain 'Example-new'
        Should -Invoke Set-ADUser -ModuleName DrunkenAD -Times 1 -Exactly
    }

    It 'inherits <Action> suppression through the SetData public wrapper' -ForEach @(
        @{ Action = 'SilentlyContinue' }, @{ Action = 'Ignore' }
    ) {
        Mock Write-Warning -ModuleName DrunkenAD {}
        $values = @(Set-ADUserDrinkData -SamAccountName 'synthetic-account' -DataMap @{ 'Example-' = @('new') } -LogPath (Join-Path $TestDrive 'caller.log') -PassThru -Confirm:$false -WarningAction $Action)
        $values | Should -Contain 'Example-new'
        Should -Invoke Set-ADUser -ModuleName DrunkenAD -Times 1 -Exactly
        Should -Invoke Write-Warning -ModuleName DrunkenAD -Times 1 -Exactly -ParameterFilter { $WarningAction -eq $Action }
    }
}
