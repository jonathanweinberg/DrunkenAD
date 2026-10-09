Describe 'Integration fixture lifecycle offline fault injection' {
    BeforeAll {
        $script:lifecycleTestsRoot = $PSScriptRoot
        $script:lifecycleSourcePath = Join-Path $PSScriptRoot 'DrunkenAD.Integration.Tests.ps1'
        $script:lifecycleSourceHash = (Get-FileHash -LiteralPath $script:lifecycleSourcePath -Algorithm SHA256).Hash
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:lifecycleSourcePath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw 'Integration source did not parse.' }

        # Select immediate children only: never execute discovery or native It bodies.
        $describe = @($ast.EndBlock.Statements | Where-Object {
            $_ -is [System.Management.Automation.Language.PipelineAst] -and
            $_.PipelineElements.Count -eq 1 -and $_.PipelineElements[0].GetCommandName() -eq 'Describe'
        })
        if ($describe.Count -ne 1) { throw 'Expected one top-level integration Describe.' }
        $describeBody = @($describe[0].PipelineElements[0].CommandElements | Where-Object {
            $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
        })
        if ($describeBody.Count -ne 1) { throw 'Expected one integration Describe body.' }
        $script:lifecycleHooks = @{}
        foreach ($name in @('BeforeAll', 'AfterAll')) {
            $hook = @($describeBody[0].ScriptBlock.EndBlock.Statements | Where-Object {
                $_ -is [System.Management.Automation.Language.PipelineAst] -and
                $_.PipelineElements.Count -eq 1 -and $_.PipelineElements[0].GetCommandName() -eq $name
            })
            if ($hook.Count -ne 1) { throw "Expected one immediate $name hook." }
            $body = @($hook[0].PipelineElements[0].CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst]
            })
            if ($body.Count -ne 1) { throw "Expected one $name body." }
            $text = $body[0].ScriptBlock.Extent.Text
            $script:lifecycleHooks[$name] = $text.Substring(1, $text.Length - 2)
        }

        function Invoke-LifecycleHook {
            param([ValidateSet('BeforeAll', 'AfterAll')][string]$Name)
            $script:fixture.Phase = $Name
            # Dot-invoke the module so functions sourced by BeforeAll persist for AfterAll.
            . $script:lifecycleModule {
                param($Text, $TestsRoot)
                $tokens = $null
                $errors = $null
                $hookAst = [System.Management.Automation.Language.Parser]::ParseInput(
                    $Text, (Join-Path $TestsRoot 'DrunkenAD.Integration.Tests.ps1'), [ref]$tokens, [ref]$errors
                )
                if ($errors.Count -gt 0) { throw 'The extracted lifecycle body did not parse.' }
                . $hookAst.GetScriptBlock()
            } $script:lifecycleHooks[$Name] $script:lifecycleTestsRoot
        }

        function Get-LifecycleState {
            & $script:lifecycleModule {
                [pscustomobject]@{
                    Ready = $script:createdUser
                    Attempted = $script:creationAttempted
                    Recorded = $script:ownershipRecorded
                    Guid = $script:userGuid
                }
            }
        }

        function Get-LifecycleReceipt {
            param([string]$Name)
            Get-Content -LiteralPath (Join-Path $script:journalDirectory $Name) -Raw | ConvertFrom-Json
        }

        function Assert-LifecycleCleanupUnknown {
            param([int]$RemoveCount = 0)
            { Invoke-LifecycleHook AfterAll } | Should -Throw
            $script:fixture.CreateCount | Should -Be 1
            $script:fixture.RemoveCount | Should -Be $RemoveCount
            (Get-LifecycleReceipt '04-cleanup-unknown.json').State | Should -BeExactly 'CleanupUnknown'
            Test-Path -LiteralPath (Join-Path $script:journalDirectory '04-absence-verified.json') | Should -BeFalse
        }
    }

    BeforeEach {
        $script:lifecycleModule = $null
        $script:journalDirectory = $null
        $script:savedLifecycleEnvironment = @{}
        $environment = @{
            DRUNKENAD_RUN_INTEGRATION = '1'
            DRUNKENAD_RUN_TIER1 = '0'
            DRUNKENAD_RUN_CAPACITY = '0'
            DRUNKENAD_TEST_DC = 'dc01.example.invalid'
            DRUNKENAD_TEST_DNS_SUFFIX = 'example.invalid'
            DRUNKENAD_TEST_USER_OU = 'OU=LifecycleTests,DC=example,DC=invalid'
            DRUNKENAD_TEST_JOURNAL_DIRECTORY = ''
        }
        foreach ($name in $environment.Keys) {
            $script:savedLifecycleEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        $script:lifecycleGlobalFunctions = @{}
        foreach ($name in @('New-ADUser', 'Get-ADUser', 'Remove-ADUser', 'Get-ADOrganizationalUnit',
            'Get-ADRootDSE', 'Get-ADDomainController', 'Test-ADDrinkAttributeReadyForUserWrite')) {
            $script:lifecycleGlobalFunctions[$name] = Get-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue
        }

        # /tmp and /var are symlink aliases on macOS; the real helper rejects them.
        $scratchRoot = if (Test-Path -LiteralPath '/private/tmp' -PathType Container) { '/private/tmp' } else { [IO.Path]::GetTempPath() }
        $script:journalDirectory = Join-Path $scratchRoot ('drunkenad-lifecycle-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($script:journalDirectory)
        if ([IO.File].GetMethods().Name -contains 'SetUnixFileMode' -and [Environment]::OSVersion.Platform -eq 'Unix') {
            [IO.File]::SetUnixFileMode($script:journalDirectory, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
        }
        $environment.DRUNKENAD_TEST_JOURNAL_DIRECTORY = $script:journalDirectory
        foreach ($name in $environment.Keys) { [Environment]::SetEnvironmentVariable($name, $environment[$name], 'Process') }

        $script:fixture = @{
            Phase = 'BeforeAll'; CreateMode = 'Normal'; RemoveMode = 'Normal'; FailAt = ''
            CreateCount = 0; RemoveCount = 0; UserCleanupReads = 0; ParentCleanupReads = 0
            UserGuid = [guid]'11111111-2222-4333-8444-555555555555'
            ReplacementGuid = [guid]'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
            ParentGuid = [guid]'12345678-1234-4234-8234-123456789abc'
            ParentDn = $environment.DRUNKENAD_TEST_USER_OU; Server = $environment.DRUNKENAD_TEST_DC
            RequestedServer = $environment.DRUNKENAD_TEST_DC; SelectedServer = $environment.DRUNKENAD_TEST_DC
            CanonicalFault = ''; ParentObjectClass = 'organizationalUnit'
            Calls = New-Object 'System.Collections.Generic.List[object]'
            CurrentUser = $null; InParent = $true; WrongMembershipGuid = $false
            ResponseGuid = $null; ParentFault = ''; ReadbackFault = ''; Imports = @(); CorruptOnReadFailure = $false
        }
        $script:lifecycleModule = New-Module -Name ('DrunkenADLifecycle_' + [guid]::NewGuid().ToString('N')) -ArgumentList $script:fixture -ScriptBlock {
            param($Fixture)
            $script:fake = $Fixture

            function Import-Module {
                param($Name, [switch]$Force, $ErrorAction)
                if ($Name -ne 'ActiveDirectory' -and [IO.Path]::GetFileName($Name) -ne 'DrunkenAD.psd1') {
                    throw 'Only the two stubbed lifecycle imports are permitted.'
                }
                $script:fake.Imports += [string]$Name
            }

            function Add-LifecycleCall {
                param($Name, $Stage, $Server, $Identity, $Filter, $SearchBase, $SearchScope)
                $script:fake.Calls.Add([pscustomobject]@{
                    Name = $Name; Stage = $Stage; Server = $Server; Identity = $Identity
                    Filter = $Filter; SearchBase = $SearchBase; SearchScope = $SearchScope
                })
                $expectedServer = if ($Stage -eq 'Readiness') { $script:fake.RequestedServer } else { $script:fake.SelectedServer }
                if ($Server -cne $expectedServer) { throw 'Synthetic lifecycle target changed.' }
                if ($script:fake.FailAt -eq $Stage) {
                    if ($script:fake.CorruptOnReadFailure) {
                        [IO.File]::WriteAllText((Join-Path $env:DRUNKENAD_TEST_JOURNAL_DIRECTORY '04-cleanup-unknown.json'), '{partial')
                    }
                    throw "Synthetic read failure: $Stage"
                }
            }

            function Test-ADDrinkAttributeReadyForUserWrite {
                param($Server, [switch]$PassThru)
                Add-LifecycleCall 'Readiness' 'Readiness' $Server
                [pscustomobject]@{ ReadyForUserWrite = $true; Server = $script:fake.SelectedServer; BlockingReason = $null }
            }

            function Get-ADRootDSE {
                param($Server, $ErrorAction)
                Add-LifecycleCall 'Get-ADRootDSE' 'TargetRootRead' $Server
                $rootDse = [pscustomobject]@{
                    dnsHostName = $script:fake.SelectedServer
                    dsServiceName = 'CN=NTDS Settings,CN=DC01,CN=Servers,CN=Example,CN=Sites,CN=Configuration,DC=example,DC=invalid'
                    defaultNamingContext = 'DC=example,DC=invalid'
                }
                if ($script:fake.CanonicalFault -eq 'RootHost') { $rootDse.dnsHostName = 'dc02.example.invalid' }
                $rootDse
            }

            function Get-ADDomainController {
                param($Identity, $Server, $ErrorAction)
                Add-LifecycleCall 'Get-ADDomainController' 'TargetControllerRead' $Server $Identity
                if ($Identity -cne $script:fake.SelectedServer) { throw 'Controller identity must use the selected DC.' }
                $controller = [pscustomobject]@{
                    HostName = $script:fake.SelectedServer
                    NTDSSettingsObjectDN = 'CN=NTDS Settings,CN=DC01,CN=Servers,CN=Example,CN=Sites,CN=Configuration,DC=example,DC=invalid'
                    DefaultPartition = 'DC=example,DC=invalid'; Domain = 'example.invalid'
                    IsReadOnly = $false; Enabled = $true
                }
                if ($script:fake.CanonicalFault -eq 'ControllerNtds') { $controller.NTDSSettingsObjectDN = 'CN=Different' }
                if ($script:fake.CanonicalFault -eq 'ControllerPartition') { $controller.DefaultPartition = 'DC=other,DC=invalid' }
                $controller
            }

            function Get-ADOrganizationalUnit {
                param($Identity, $Server, $ErrorAction)
                $stage = 'ParentCreateRead'
                if ($script:fake.Phase -eq 'AfterAll') {
                    $script:fake.ParentCleanupReads++
                    $stage = if ($script:fake.ParentCleanupReads -eq 1) { 'ParentBeforeRead' } else { 'ParentAfterRead' }
                }
                elseif ($Identity -is [guid]) { $stage = 'CreatedParentRead' }
                Add-LifecycleCall 'Get-ADOrganizationalUnit' $stage $Server $Identity
                $parent = [pscustomobject]@{
                    ObjectGUID = $script:fake.ParentGuid; DistinguishedName = $script:fake.ParentDn; ObjectClass = $script:fake.ParentObjectClass
                }
                if ($script:fake.ParentFault -eq ($stage + 'Guid')) { $parent.ObjectGUID = $script:fake.ReplacementGuid }
                if ($script:fake.ParentFault -eq ($stage + 'Dn')) { $parent.DistinguishedName = 'OU=Other,DC=example,DC=invalid' }
                $parent
            }

            function New-ADUser {
                param($Name, $SamAccountName, $UserPrincipalName, $AccountPassword, $Enabled, $Description,
                    $EmployeeID, $OtherAttributes, $Server, $Path, $ErrorAction, [switch]$PassThru)
                $script:fake.CreateCount++
                Add-LifecycleCall 'New-ADUser' 'Create' $Server $SamAccountName
                if ($script:fake.CreateCount -ne 1) { throw 'An implicit creation retry is forbidden.' }
                $script:fake.IntentAtCreate = Get-Content -LiteralPath (Join-Path $env:DRUNKENAD_TEST_JOURNAL_DIRECTORY '00-intent.json') -Raw | ConvertFrom-Json
                $script:fake.IssuedAtCreate = Get-Content -LiteralPath (Join-Path $env:DRUNKENAD_TEST_JOURNAL_DIRECTORY '01-create-issued.json') -Raw | ConvertFrom-Json
                $script:fake.CurrentUser = [pscustomobject]@{
                    ObjectGUID = $script:fake.UserGuid; Name = $Name; SamAccountName = $SamAccountName
                    DistinguishedName = "CN=$Name,$Path"; Description = $Description
                    Enabled = $Enabled; ObjectClass = 'user'
                }
                switch ($script:fake.CreateMode) {
                    'CommitThenThrow' { throw 'Synthetic constructor response lost after commit.' }
                    'CommitThenThrowJournalFault' {
                        [IO.File]::WriteAllText((Join-Path $env:DRUNKENAD_TEST_JOURNAL_DIRECTORY '02-creation-unknown.json'), '{partial')
                        throw 'Synthetic constructor response lost after commit.'
                    }
                    'MissingGuid' { return [pscustomobject]@{ Name = $Name } }
                    'InvalidGuid' { return [pscustomobject]@{ ObjectGUID = 'not-a-guid' } }
                    'EmptyGuid' { return [pscustomobject]@{ ObjectGUID = [guid]::Empty } }
                    'PartialCreated' {
                        [IO.File]::WriteAllText((Join-Path $env:DRUNKENAD_TEST_JOURNAL_DIRECTORY '02-created.json'), '{partial')
                    }
                }
                [pscustomobject]@{ ObjectGUID = $script:fake.UserGuid }
            }

            function Get-ADUser {
                param($Filter, $Properties, $Server, $SearchBase, $SearchScope, $ErrorAction)
                $stage = 'CreatedReadback'
                if ($script:fake.Phase -eq 'AfterAll') {
                    if ($SearchBase) { $stage = 'MembershipRead' }
                    else {
                        $script:fake.UserCleanupReads++
                        $stage = if ($script:fake.UserCleanupReads -eq 1) { 'OwnedRead' } else { 'AbsenceRead' }
                    }
                }
                elseif ($SearchBase) { $stage = 'CreatedMembershipRead' }
                Add-LifecycleCall 'Get-ADUser' $stage $Server $null $Filter $SearchBase $SearchScope
                if ($stage -eq 'CreatedReadback') {
                    $script:fake.CreatedReceiptAtReadback = Get-Content -LiteralPath (Join-Path $env:DRUNKENAD_TEST_JOURNAL_DIRECTORY '02-created.json') -Raw
                }
                if ($Filter -cne "ObjectGUID -eq '$($script:fake.UserGuid)'") { throw 'Only the created GUID may be queried.' }
                if ($SearchBase -and ($SearchBase -cne $script:fake.ParentDn -or $SearchScope -cne 'OneLevel')) {
                    throw 'Cleanup must prove one-level membership in the recorded parent.'
                }
                if ($null -eq $script:fake.CurrentUser -or $script:fake.CurrentUser.ObjectGUID -ne $script:fake.UserGuid) { return }
                if ($stage -in @('MembershipRead', 'CreatedMembershipRead') -and -not $script:fake.InParent) { return }
                $user = $script:fake.CurrentUser.PSObject.Copy()
                if ($script:fake.ResponseGuid) { $user.ObjectGUID = $script:fake.ResponseGuid }
                if ($stage -in @('MembershipRead', 'CreatedMembershipRead') -and $script:fake.WrongMembershipGuid) { $user.ObjectGUID = $script:fake.ReplacementGuid }
                if ($stage -eq 'CreatedReadback' -and $script:fake.ReadbackFault -eq 'Description') { $user.Description = 'unowned' }
                if ($stage -eq 'CreatedReadback' -and $script:fake.ReadbackFault -eq 'Enabled') { $user.Enabled = $true }
                $user
            }

            function Remove-ADUser {
                param($Identity, $Server, $Confirm, $ErrorAction)
                $script:fake.RemoveCount++
                Add-LifecycleCall 'Remove-ADUser' 'Remove' $Server $Identity
                if ($Identity -isnot [guid] -or $Identity -ne $script:fake.UserGuid -or $script:fake.RemoveCount -ne 1) {
                    throw 'Only one deletion by the captured GUID is permitted.'
                }
                $script:fake.DeleteIssuedAtRemove = Get-Content -LiteralPath (Join-Path $env:DRUNKENAD_TEST_JOURNAL_DIRECTORY '03-delete-issued.json') -Raw | ConvertFrom-Json
                if ($script:fake.RemoveMode -eq 'NoCommit') { throw 'Synthetic removal denied before commit.' }
                $script:fake.CurrentUser = $null
                if ($script:fake.RemoveMode -eq 'CommitThenThrow') { throw 'Synthetic removal response lost after commit.' }
            }

            Export-ModuleMember -Function @() -Cmdlet @() -Alias @()
        }
    }

    AfterEach {
        try {
            if ($null -ne $script:lifecycleModule) { Remove-Module -ModuleInfo $script:lifecycleModule -Force -ErrorAction Stop }
        }
        finally {
            foreach ($name in $script:savedLifecycleEnvironment.Keys) {
                if ($null -eq $script:savedLifecycleEnvironment[$name]) {
                    Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
                }
                else {
                    [Environment]::SetEnvironmentVariable($name, $script:savedLifecycleEnvironment[$name], 'Process')
                }
            }
            if ($script:journalDirectory -and (Test-Path -LiteralPath $script:journalDirectory)) {
                Remove-Item -LiteralPath $script:journalDirectory -Recurse -Force
            }
        }
        foreach ($name in $script:lifecycleGlobalFunctions.Keys) {
            $current = Get-Item -LiteralPath "Function:\$name" -ErrorAction SilentlyContinue
            $original = $script:lifecycleGlobalFunctions[$name]
            if ($null -eq $original) {
                $current | Should -BeNullOrEmpty
            }
            else {
                $current | Should -Not -BeNullOrEmpty
                if ($null -ne $current) {
                    [object]::ReferenceEquals($current.ScriptBlock, $original.ScriptBlock) | Should -BeTrue
                }
            }
        }
        foreach ($name in $script:savedLifecycleEnvironment.Keys) {
            [object]::Equals([Environment]::GetEnvironmentVariable($name, 'Process'), $script:savedLifecycleEnvironment[$name]) | Should -BeTrue
        }
    }

    It 'creates once with durable intent, then deletes by GUID and verifies absence and parent preservation' {
        Invoke-LifecycleHook BeforeAll
        (Get-LifecycleState).Ready | Should -BeTrue
        (Get-LifecycleState).Recorded | Should -BeTrue
        & $script:lifecycleModule { (Get-Command New-DrunkenADIntegrationJournal).ScriptBlock.File } |
            Should -BeExactly (Join-Path $script:lifecycleTestsRoot 'Support/IntegrationOwnership.ps1')
        $script:fixture.Imports.Count | Should -Be 2
        $script:fixture.IntentAtCreate.TestSourceSHA256 | Should -BeExactly $script:lifecycleSourceHash
        $script:fixture.IntentAtCreate.ParentGuid | Should -Be ([string]$script:fixture.ParentGuid)
        $script:fixture.IntentAtCreate.Server | Should -BeExactly $script:fixture.Server
        $script:fixture.IntentAtCreate.OwnershipToken | Should -BeExactly $script:fixture.CurrentUser.Description
        $script:fixture.CurrentUser.Enabled | Should -BeFalse
        $script:fixture.IssuedAtCreate.State | Should -BeExactly 'CreateIssued'
        (Get-LifecycleReceipt '02-created.json').ObjectGuid | Should -Be ([string]$script:fixture.UserGuid)
        Invoke-LifecycleHook AfterAll
        $script:fixture.CreateCount | Should -Be 1
        $script:fixture.RemoveCount | Should -Be 1
        $script:fixture.DeleteIssuedAtRemove.State | Should -BeExactly 'DeleteIssued'
        $script:fixture.DeleteIssuedAtRemove.ObjectGuid | Should -Be ([string]$script:fixture.UserGuid)
        $receipt = Get-LifecycleReceipt '04-absence-verified.json'
        $receipt.State | Should -BeExactly 'AbsenceVerified'
        $receipt.ObjectGuid | Should -Be ([string]$script:fixture.UserGuid)
        $receipt.OperationErrorObserved | Should -BeFalse
        @($script:fixture.Calls | ForEach-Object { $_.Stage }) | Should -Be @(
            'Readiness', 'ParentCreateRead', 'TargetRootRead', 'TargetControllerRead', 'Create',
            'CreatedReadback', 'CreatedParentRead', 'CreatedMembershipRead', 'ParentBeforeRead',
            'OwnedRead', 'MembershipRead', 'Remove', 'AbsenceRead', 'ParentAfterRead'
        )
        @($script:fixture.Calls | Where-Object { $_.Stage -in @('ParentBeforeRead', 'ParentAfterRead') } | ForEach-Object { $_.Identity }) |
            Should -Be @($script:fixture.ParentGuid, $script:fixture.ParentGuid)
        (Get-LifecycleState).Ready | Should -BeFalse
    }

    It 'pins an ordinary domain-selector run and every later call to the readiness-selected DC' {
        $env:DRUNKENAD_TEST_DC = 'example.invalid'
        $script:fixture.RequestedServer = 'example.invalid'
        $script:fixture.SelectedServer = 'dc01.example.invalid'
        Invoke-LifecycleHook BeforeAll
        (Get-LifecycleState).Ready | Should -BeTrue
        $script:fixture.Calls[0].Server | Should -BeExactly 'example.invalid'
        (Get-LifecycleReceipt '00-intent.json').Server | Should -BeExactly $script:fixture.SelectedServer
        Invoke-LifecycleHook AfterAll
        foreach ($call in @($script:fixture.Calls | Where-Object Stage -ne 'Readiness')) {
            $call.Server | Should -BeExactly $script:fixture.SelectedServer
        }
        $script:fixture.RemoveCount | Should -Be 1
        (Get-LifecycleReceipt '04-absence-verified.json').State | Should -BeExactly 'AbsenceVerified'
    }

    It 'rejects inconsistent <Fault> canonical metadata before journaling or creating' -ForEach @(
        @{ Fault = 'RootHost' }, @{ Fault = 'ControllerNtds' }, @{ Fault = 'ControllerPartition' }
    ) {
        $script:fixture.CanonicalFault = $Fault
        { Invoke-LifecycleHook BeforeAll } | Should -Throw '*Evidence Gap:*'
        (Get-LifecycleState).Ready | Should -BeFalse
        (Get-LifecycleState).Attempted | Should -BeFalse
        $script:fixture.CreateCount | Should -Be 0
        Invoke-LifecycleHook AfterAll
        $script:fixture.RemoveCount | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:journalDirectory -Force).Count | Should -Be 0
    }

    It 'blocks test readiness for post-create <Fault> and retains the exact Created receipt' -ForEach @(
        @{ Fault = 'ParentGuid' }, @{ Fault = 'ParentDn' }, @{ Fault = 'MembershipAbsent' }
        @{ Fault = 'MembershipGuid' }, @{ Fault = 'ParentReadFailure' }, @{ Fault = 'MembershipReadFailure' }
    ) {
        switch ($Fault) {
            'ParentGuid' { $script:fixture.ParentFault = 'CreatedParentReadGuid' }
            'ParentDn' { $script:fixture.ParentFault = 'CreatedParentReadDn' }
            'MembershipAbsent' { $script:fixture.InParent = $false }
            'MembershipGuid' { $script:fixture.WrongMembershipGuid = $true }
            'ParentReadFailure' { $script:fixture.FailAt = 'CreatedParentRead' }
            'MembershipReadFailure' { $script:fixture.FailAt = 'CreatedMembershipRead' }
        }
        { Invoke-LifecycleHook BeforeAll } | Should -Throw
        (Get-LifecycleState).Ready | Should -BeFalse
        (Get-LifecycleState).Recorded | Should -BeTrue
        $script:fixture.CreateCount | Should -Be 1
        $script:fixture.RemoveCount | Should -Be 0
        $script:fixture.CurrentUser.ObjectGUID | Should -Be $script:fixture.UserGuid
        $script:fixture.CurrentUser.Description | Should -BeExactly $script:fixture.IntentAtCreate.OwnershipToken
        $script:fixture.CurrentUser.Enabled | Should -BeFalse
        @((Get-ChildItem -LiteralPath $script:journalDirectory -File).Name | Sort-Object) |
            Should -Be @('00-intent.json', '01-create-issued.json', '02-created.json')
        (Get-LifecycleReceipt '02-created.json').ObjectGuid | Should -Be ([string]$script:fixture.UserGuid)
        Get-Content -LiteralPath (Join-Path $script:journalDirectory '02-created.json') -Raw |
            Should -BeExactly $script:fixture.CreatedReceiptAtReadback
        switch ($Fault) {
            'ParentGuid' { $script:fixture.ParentFault = 'ParentBeforeReadGuid' }
            'ParentDn' { $script:fixture.ParentFault = 'ParentBeforeReadDn' }
            'ParentReadFailure' { $script:fixture.FailAt = 'ParentBeforeRead' }
            'MembershipReadFailure' { $script:fixture.FailAt = 'MembershipRead' }
        }
        Assert-LifecycleCleanupUnknown
        Get-Content -LiteralPath (Join-Path $script:journalDirectory '02-created.json') -Raw |
            Should -BeExactly $script:fixture.CreatedReceiptAtReadback
    }

    It 'preserves durable intent when creation commits then throws without retry or implicit deletion' {
        $script:fixture.CreateMode = 'CommitThenThrow'
        { Invoke-LifecycleHook BeforeAll } | Should -Throw '*constructor response lost*'
        (Get-LifecycleState).Ready | Should -BeFalse
        (Get-LifecycleState).Attempted | Should -BeTrue
        (Get-LifecycleReceipt '02-creation-unknown.json').State | Should -BeExactly 'CreationOutcomeUnknown'
        (Get-LifecycleReceipt '00-intent.json').RunId | Should -BeExactly $script:fixture.IntentAtCreate.RunId
        { Invoke-LifecycleHook AfterAll } | Should -Throw '*CleanupUnknown*'
        $script:fixture.CurrentUser | Should -Not -BeNullOrEmpty
        $script:fixture.CreateCount | Should -Be 1
        $script:fixture.RemoveCount | Should -Be 0
        @($script:fixture.Calls | Where-Object { $_.Name -eq 'Get-ADUser' }).Count | Should -Be 0
    }

    It 'rejects <Mode> creation output and never deletes an unreceipted identity' -ForEach @(
        @{ Mode = 'MissingGuid' }, @{ Mode = 'InvalidGuid' }, @{ Mode = 'EmptyGuid' }
    ) {
        $script:fixture.CreateMode = $Mode
        { Invoke-LifecycleHook BeforeAll } | Should -Throw '*valid ObjectGUID*'
        (Get-LifecycleState).Ready | Should -BeFalse
        (Get-LifecycleState).Recorded | Should -BeFalse
        (Get-LifecycleReceipt '02-creation-unknown.json').State | Should -BeExactly 'CreationOutcomeUnknown'
        { Invoke-LifecycleHook AfterAll } | Should -Throw '*CleanupUnknown*'
        $script:fixture.CreateCount | Should -Be 1
        $script:fixture.RemoveCount | Should -Be 0
    }

    It 'keeps a partial Created receipt and blocks test readiness and deletion after a real journal failure' {
        $script:fixture.CreateMode = 'PartialCreated'
        { Invoke-LifecycleHook BeforeAll } | Should -Throw '*journal*'
        (Get-LifecycleState).Guid | Should -Be $script:fixture.UserGuid
        (Get-LifecycleState).Ready | Should -BeFalse
        (Get-LifecycleState).Recorded | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $script:journalDirectory '02-created.json') -Raw | Should -BeExactly '{partial'
        (Get-LifecycleReceipt '01-create-issued.json').State | Should -BeExactly 'CreateIssued'
        { Invoke-LifecycleHook AfterAll } | Should -Throw '*CleanupUnknown*'
        $script:fixture.CreateCount | Should -Be 1
        $script:fixture.RemoveCount | Should -Be 0
        @($script:fixture.Calls | Where-Object Stage -eq 'CreatedReadback').Count | Should -Be 0
    }

    It 'refuses cleanup for <Fault> ownership metadata' -ForEach @(
        @{ Fault = 'Description' }, @{ Fault = 'Token' }, @{ Fault = 'Guid' }, @{ Fault = 'Enabled' }
    ) {
        Invoke-LifecycleHook BeforeAll
        switch ($Fault) {
            'Description' { $script:fixture.CurrentUser.Description = '' }
            'Token' { $script:fixture.CurrentUser.Description = 'DrunkenAD integration aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' }
            'Guid' { $script:fixture.ResponseGuid = $script:fixture.ReplacementGuid }
            'Enabled' { $script:fixture.CurrentUser.Enabled = $true }
        }
        Assert-LifecycleCleanupUnknown
        Test-Path -LiteralPath (Join-Path $script:journalDirectory '03-delete-issued.json') | Should -BeFalse
    }

    It 'refuses cleanup when one-level membership is <Fault>' -ForEach @(
        @{ Fault = 'Absent' }, @{ Fault = 'WrongGuid' }
    ) {
        Invoke-LifecycleHook BeforeAll
        if ($Fault -eq 'Absent') { $script:fixture.InParent = $false }
        else { $script:fixture.WrongMembershipGuid = $true }
        Assert-LifecycleCleanupUnknown
    }

    It 'allows a renamed owned GUID with its exact marker still directly inside the parent' {
        Invoke-LifecycleHook BeforeAll
        $script:fixture.CurrentUser.Name = 'RenamedSyntheticFixture'
        $script:fixture.CurrentUser.SamAccountName = 'RenamedSyntheticFixture'
        $script:fixture.CurrentUser.DistinguishedName = 'CN=RenamedSyntheticFixture,' + $script:fixture.ParentDn
        Invoke-LifecycleHook AfterAll
        $script:fixture.RemoveCount | Should -Be 1
        @($script:fixture.Calls | Where-Object Name -eq 'Remove-ADUser')[0].Identity | Should -Be $script:fixture.UserGuid
        (Get-LifecycleReceipt '04-absence-verified.json').State | Should -BeExactly 'AbsenceVerified'
    }

    It 'never deletes a same-name replacement with a different GUID' {
        Invoke-LifecycleHook BeforeAll
        $originalName = $script:fixture.CurrentUser.SamAccountName
        $script:fixture.CurrentUser.ObjectGUID = $script:fixture.ReplacementGuid
        Invoke-LifecycleHook AfterAll
        $script:fixture.CurrentUser.SamAccountName | Should -BeExactly $originalName
        $script:fixture.CurrentUser.ObjectGUID | Should -Be $script:fixture.ReplacementGuid
        $script:fixture.RemoveCount | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:journalDirectory '03-delete-issued.json') | Should -BeFalse
        (Get-LifecycleReceipt '04-absence-verified.json').ObjectGuid | Should -Be ([string]$script:fixture.UserGuid)
        @($script:fixture.Calls | Where-Object Stage -eq 'AbsenceRead').Count | Should -Be 1
    }

    It 'reconciles a removal that commits then throws only after explicit absence and parent reads' {
        Invoke-LifecycleHook BeforeAll
        $script:fixture.RemoveMode = 'CommitThenThrow'
        Invoke-LifecycleHook AfterAll
        $script:fixture.RemoveCount | Should -Be 1
        $receipt = Get-LifecycleReceipt '04-absence-verified.json'
        $receipt.State | Should -BeExactly 'AbsenceVerified'
        $receipt.OperationErrorObserved | Should -BeTrue
        @($script:fixture.Calls | Select-Object -Last 3 | ForEach-Object { $_.Stage }) |
            Should -Be @('Remove', 'AbsenceRead', 'ParentAfterRead')
    }

    It 'records unknown cleanup when a failed removal leaves the GUID present without retrying' {
        Invoke-LifecycleHook BeforeAll
        $script:fixture.RemoveMode = 'NoCommit'
        Assert-LifecycleCleanupUnknown -RemoveCount 1
        $script:fixture.CurrentUser.ObjectGUID | Should -Be $script:fixture.UserGuid
    }

    It 'records CleanupUnknown, never absence, after <Stage> fails' -ForEach @(
        @{ Stage = 'ParentBeforeRead'; Removes = 0 }
        @{ Stage = 'OwnedRead'; Removes = 0 }
        @{ Stage = 'MembershipRead'; Removes = 0 }
        @{ Stage = 'AbsenceRead'; Removes = 1 }
        @{ Stage = 'ParentAfterRead'; Removes = 1 }
    ) {
        Invoke-LifecycleHook BeforeAll
        $script:fixture.FailAt = $Stage
        Assert-LifecycleCleanupUnknown -RemoveCount $Removes
        @($script:fixture.Calls | Where-Object Stage -eq $Stage).Count | Should -Be 1
    }

    It 'records CleanupUnknown for changed <Fault> parent identity' -ForEach @(
        @{ Fault = 'ParentBeforeReadGuid'; Removes = 0 }, @{ Fault = 'ParentBeforeReadDn'; Removes = 0 }
        @{ Fault = 'ParentAfterReadGuid'; Removes = 1 }, @{ Fault = 'ParentAfterReadDn'; Removes = 1 }
    ) {
        Invoke-LifecycleHook BeforeAll
        $script:fixture.ParentFault = $Fault
        Assert-LifecycleCleanupUnknown -RemoveCount $Removes
    }

    It 'refuses cleanup when the runtime target differs from its durable intent' {
        Invoke-LifecycleHook BeforeAll
        & $script:lifecycleModule { $script:domainController = 'dc02.example.invalid' }
        Assert-LifecycleCleanupUnknown
        $script:fixture.ParentCleanupReads | Should -Be 0
    }

    It 'requires the immediate created-user <Fault> readback before admitting test writes' -ForEach @(
        @{ Fault = 'Description' }, @{ Fault = 'Enabled' }, @{ Fault = 'ReadFailure' }
    ) {
        if ($Fault -eq 'ReadFailure') { $script:fixture.FailAt = 'CreatedReadback' }
        else { $script:fixture.ReadbackFault = $Fault }
        { Invoke-LifecycleHook BeforeAll } | Should -Throw
        (Get-LifecycleState).Recorded | Should -BeTrue
        (Get-LifecycleState).Ready | Should -BeFalse
        $script:fixture.RemoveCount | Should -Be 0
        (Get-LifecycleReceipt '02-created.json').ObjectGuid | Should -Be ([string]$script:fixture.UserGuid)
        # A failed readiness read does not discard durable ownership for safe cleanup.
        Invoke-LifecycleHook AfterAll
        (Get-LifecycleReceipt '04-absence-verified.json').State | Should -BeExactly 'AbsenceVerified'
    }

    It 'denies a reused journal approval before issuing a second create' {
        Invoke-LifecycleHook BeforeAll
        Invoke-LifecycleHook AfterAll
        $originalIntent = Get-Content -LiteralPath (Join-Path $script:journalDirectory '00-intent.json') -Raw
        { Invoke-LifecycleHook BeforeAll } | Should -Throw '*reuse is prohibited*'
        Invoke-LifecycleHook AfterAll
        $script:fixture.CreateCount | Should -Be 1
        $script:fixture.RemoveCount | Should -Be 1
        (Get-LifecycleState).Attempted | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $script:journalDirectory '00-intent.json') -Raw | Should -BeExactly $originalIntent
    }

    It 'preserves the primary creation failure when recording its unknown outcome also fails' {
        $script:fixture.CreateMode = 'CommitThenThrowJournalFault'
        $failure = $null
        try { Invoke-LifecycleHook BeforeAll } catch { $failure = $_ }
        $failure.Exception.Message | Should -BeExactly 'Synthetic constructor response lost after commit.'
        $failure.Exception.Data['OwnershipJournalFailure'] | Should -BeTrue
        (Get-LifecycleState).Ready | Should -BeFalse
        { Invoke-LifecycleHook AfterAll } | Should -Throw '*CleanupUnknown*'
        $script:fixture.CreateCount | Should -Be 1
        $script:fixture.RemoveCount | Should -Be 0
        Get-Content -LiteralPath (Join-Path $script:journalDirectory '02-creation-unknown.json') -Raw | Should -BeExactly '{partial'
    }

    It 'preserves the primary cleanup read failure when recording CleanupUnknown also fails' {
        Invoke-LifecycleHook BeforeAll
        $script:fixture.FailAt = 'OwnedRead'
        $script:fixture.CorruptOnReadFailure = $true
        $failure = $null
        try { Invoke-LifecycleHook AfterAll } catch { $failure = $_ }
        $failure.Exception.Message | Should -BeExactly 'Synthetic read failure: OwnedRead'
        $failure.Exception.Data['OwnershipJournalFailure'] | Should -BeTrue
        $script:fixture.RemoveCount | Should -Be 0
        Get-Content -LiteralPath (Join-Path $script:journalDirectory '04-cleanup-unknown.json') -Raw | Should -BeExactly '{partial'
        Test-Path -LiteralPath (Join-Path $script:journalDirectory '04-absence-verified.json') | Should -BeFalse
    }
}
