BeforeAll {
    . (Join-Path $PSScriptRoot '../DrunkenAD/Private/Core.ps1')

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

    It 'refuses the macOS var alias without creating fallback logs' -Skip:($env:OS -eq 'Windows_NT' -or -not (Test-Path '/private/var')) {
        { Assert-DrunkenADLogNotLinked '/var/tmp/DrunkenAD/logs-v1/activity.log' } | Should -Throw '*links*'
    }
}
