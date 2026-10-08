$script:runIntegration = $env:DRUNKENAD_RUN_INTEGRATION -eq '1'
$script:runTier1 = $script:runIntegration -and $env:DRUNKENAD_RUN_TIER1 -eq '1'
$script:domainController = $env:DRUNKENAD_TEST_DC
$script:dnsSuffix = $env:DRUNKENAD_TEST_DNS_SUFFIX
$script:testUserOu = $env:DRUNKENAD_TEST_USER_OU
$script:canRun = $script:runIntegration -and -not [string]::IsNullOrWhiteSpace($script:domainController) -and -not [string]::IsNullOrWhiteSpace($script:dnsSuffix)

Describe 'DrunkenAD integration tests' -Tag 'Integration' -Skip:(-not $script:canRun) {
    BeforeAll {
        $script:createdUser = $false
        $script:userGuid = $null
        # Re-read runtime inputs; Pester discovery state is not the execution contract.
        if ($env:DRUNKENAD_RUN_INTEGRATION -ne '1') {
            throw 'Integration execution requires DRUNKENAD_RUN_INTEGRATION=1.'
        }
        $script:runTier1 = $env:DRUNKENAD_RUN_TIER1 -eq '1'
        $script:domainController = $env:DRUNKENAD_TEST_DC
        $script:dnsSuffix = $env:DRUNKENAD_TEST_DNS_SUFFIX
        $script:testUserOu = $env:DRUNKENAD_TEST_USER_OU

        if ([string]::IsNullOrWhiteSpace($script:domainController) -or [string]::IsNullOrWhiteSpace($script:dnsSuffix)) {
            throw 'The integration environment variables were not available during test execution.'
        }

        if ($script:runTier1 -and [string]::IsNullOrWhiteSpace($script:testUserOu)) {
            throw 'Tier1 requires DRUNKENAD_TEST_USER_OU to identify a pre-existing test OU.'
        }

        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../DrunkenAD/DrunkenAD.psd1'
        Import-Module $modulePath -Force -ErrorAction Stop
        Import-Module ActiveDirectory -ErrorAction Stop
        $script:readinessStatus = Test-ADDrinkAttributeReadyForUserWrite -Server $script:domainController -PassThru

        if ($script:runTier1) {
            # Use the same validated DC for fixture creation, writes, reads, and cleanup.
            if ([string]::IsNullOrWhiteSpace($script:readinessStatus.Server)) {
                throw 'Evidence Gap: Tier1 readiness did not return a pinned server.'
            }
            $script:domainController = $script:readinessStatus.Server
            Get-ADOrganizationalUnit -Identity $script:testUserOu -Server $script:domainController -ErrorAction Stop | Out-Null
        }

        function New-IntegrationPassword {
            param(
                [int]$Length = 20
            )

            $lowercase = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
            $uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
            $numbers = '0123456789'.ToCharArray()
            $specialChars = '!@#$%^&*()-_=+[]{}|;:,.<>/?'.ToCharArray()
            $passwordChars = @(
                Get-Random -InputObject $lowercase
                Get-Random -InputObject $uppercase
                Get-Random -InputObject $numbers
                Get-Random -InputObject $specialChars
            )

            $allChars = $lowercase + $uppercase + $numbers + $specialChars
            for ($index = $passwordChars.Count; $index -lt $Length; $index++) {
                $passwordChars += Get-Random -InputObject $allChars
            }

            -join ($passwordChars | Get-Random -Count $Length)
        }

        if ($script:readinessStatus.ReadyForUserWrite) {
            $script:runId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
            $script:userName = "DrunkenAD_$($script:runId)"
            $script:userPrincipalName = '{0}@{1}' -f $script:userName, $script:dnsSuffix
            $script:mail = '{0}@{1}' -f $script:userName, $script:dnsSuffix
            $script:employeeId = [string](Get-Random -Minimum 100000 -Maximum 999999)

            $newUserParams = @{
                Name              = $script:userName
                SamAccountName    = $script:userName
                UserPrincipalName = $script:userPrincipalName
                AccountPassword   = (New-IntegrationPassword | ConvertTo-SecureString -AsPlainText -Force)
                Enabled           = $false
                EmployeeID        = $script:employeeId
                OtherAttributes   = @{
                    mail  = $script:mail
                    pager = $script:mail
                }
                Server            = $script:domainController
                ErrorAction       = 'Stop'
            }

            if (-not [string]::IsNullOrWhiteSpace($script:testUserOu)) {
                $newUserParams['Path'] = $script:testUserOu
            }

            $created = New-ADUser @newUserParams -PassThru
            $script:createdUser = $true
            $script:userGuid = [guid]$created.ObjectGUID
            if ($script:userGuid -eq [guid]::Empty) {
                throw 'The isolated integration account did not return an ObjectGUID.'
            }
        }
    }

    AfterAll {
        if (-not (Get-Variable -Name createdUser -Scope Script -ErrorAction SilentlyContinue)) {
            $script:createdUser = $false
        }

        if ($script:createdUser) {
            $cleanupIdentity = if ($null -ne $script:userGuid -and $script:userGuid -ne [guid]::Empty) { $script:userGuid } else { $script:userName }
            Remove-ADUser -Identity $cleanupIdentity -Server $script:domainController -Confirm:$false -ErrorAction Stop
            $remaining = @(Get-ADUser -Filter "SamAccountName -eq '$($script:userName)'" -Server $script:domainController -ErrorAction Stop)
            if ($remaining.Count -ne 0) {
                throw 'The isolated integration account was not removed.'
            }
            if ($null -ne $script:userGuid -and $script:userGuid -ne [guid]::Empty) {
                $remainingByGuid = @(Get-ADUser -Filter "ObjectGUID -eq '$($script:userGuid)'" -Server $script:domainController -ErrorAction Stop)
                if ($remainingByGuid.Count -ne 0) {
                    throw 'The isolated integration account ObjectGUID is still present.'
                }
            }
            $script:createdUser = $false
        }
    }

    It 'reports readiness or a blocking reason for user writes' {
        if ($script:readinessStatus.ReadyForUserWrite) {
            $script:readinessStatus.BlockingReason | Should -BeNullOrEmpty
        }
        else {
            $script:readinessStatus.BlockingReason | Should -Not -BeNullOrEmpty
        }
    }

    It 'writes and reads back a literal namespace value' {
        if (-not $script:readinessStatus.ReadyForUserWrite) {
            $because = if ([string]::IsNullOrWhiteSpace($script:readinessStatus.BlockingMessage)) {
                'The drink attribute is not ready for user writes in the target environment.'
            }
            else {
                $script:readinessStatus.BlockingMessage
            }

            Set-ItResult -Skipped -Because $because
            return
        }

        Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ 'Demo[01]-' = @('First') } -DomainController $script:domainController -Confirm:$false

        $values = Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Demo[01]-' -DomainController $script:domainController

        $values | Should -Be @('Demo[01]-First')
    }

    It 'replaces one namespace without disturbing other namespaces' {
        if (-not $script:readinessStatus.ReadyForUserWrite) {
            $because = if ([string]::IsNullOrWhiteSpace($script:readinessStatus.BlockingMessage)) {
                'The drink attribute is not ready for user writes in the target environment.'
            }
            else {
                $script:readinessStatus.BlockingMessage
            }

            Set-ItResult -Skipped -Because $because
            return
        }

        Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ 'Keep-' = @('Stable'); 'Demo[01]-' = @('Second') } -DomainController $script:domainController -Confirm:$false

        $demoValues = Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Demo[01]-' -DomainController $script:domainController
        $keepValues = Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Keep-' -DomainController $script:domainController

        $demoValues | Should -Be @('Demo[01]-Second')
        $keepValues | Should -Be @('Keep-Stable')
    }

    It 'removes a namespace without clearing unrelated stored values' {
        if (-not $script:readinessStatus.ReadyForUserWrite) {
            $because = if ([string]::IsNullOrWhiteSpace($script:readinessStatus.BlockingMessage)) {
                'The drink attribute is not ready for user writes in the target environment.'
            }
            else {
                $script:readinessStatus.BlockingMessage
            }

            Set-ItResult -Skipped -Because $because
            return
        }

        Remove-ADUserDrinkData -SamAccountName $script:userName -Prefixes 'Demo[01]-' -DomainController $script:domainController -Confirm:$false

        $allValues = Get-ADUserDrinkData -SamAccountName $script:userName -DomainController $script:domainController
        $removedValues = Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Demo[01]-' -DomainController $script:domainController

        $allValues | Should -Be @('Keep-Stable')
        $removedValues | Should -Be @()
    }

    It 'imports CSV drink data and reads back mapped namespaces' {
        if (-not $script:readinessStatus.ReadyForUserWrite) {
            $because = if ([string]::IsNullOrWhiteSpace($script:readinessStatus.BlockingMessage)) {
                'The drink attribute is not ready for user writes in the target environment.'
            }
            else {
                $script:readinessStatus.BlockingMessage
            }

            Set-ItResult -Skipped -Because $because
            return
        }

        $csvPath = Join-Path -Path TestDrive: -ChildPath 'integration-ingestion.csv'
        @(
            'SamAccountName,ProfileTier,Flags'
            ('{0},Gold,Enabled;Audited' -f $script:userName)
        ) | Set-Content -LiteralPath $csvPath -Encoding utf8

        Import-ADUserDrinkCsvData `
            -CsvPath $csvPath `
            -NamespaceMap @{
                'Profile-' = @(@{ Column = 'ProfileTier'; Label = 'Tier' })
                'Flags-'   = @(@{ Column = 'Flags'; SplitOn = ';' })
            } `
            -DomainController $script:domainController

        $profileValues = Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Profile-' -DomainController $script:domainController
        $flagValues = Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Flags-' -DomainController $script:domainController

        $profileValues | Should -Be @('Profile-Tier=Gold')
        ($flagValues | Sort-Object) | Should -Be @('Flags-Audited', 'Flags-Enabled')
    }

    It 'handles empty CSV namespaces with ClearBlankNamespaces=<ClearBlank> on a real directory' -TestCases @(
        @{ ClearBlank = $false },
        @{ ClearBlank = $true }
    ) {
        param($ClearBlank)
        if (-not $script:readinessStatus.ReadyForUserWrite) {
            Set-ItResult -Skipped -Because 'The attribute is not ready for user writes.'
            return
        }
        Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ 'CsvBlankTier-' = @('Old'); 'CsvBlankFlag-' = @('Retain') } -DomainController $script:domainController -Confirm:$false
        $csvPath = Join-Path $TestDrive 'blank-namespaces.csv'
        @('SamAccountName,Tier,Flag', ('{0},Gold,' -f $script:userName)) | Set-Content -LiteralPath $csvPath -Encoding utf8
        $result = Import-ADUserDrinkCsvData -CsvPath $csvPath -NamespaceMap @{ 'CsvBlankTier-' = @(@{ Column = 'Tier' }); 'CsvBlankFlag-' = @(@{ Column = 'Flag' }) } -DomainController $script:domainController -ClearBlankNamespaces:$ClearBlank -Confirm:$false
        $result.Status | Should -Be 'Written'
        @(Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'CsvBlankTier-' -DomainController $script:domainController) | Should -Be @('CsvBlankTier-Gold')
        $flagValues = @(Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'CsvBlankFlag-' -DomainController $script:domainController)
        if ($ClearBlank) { $flagValues.Count | Should -Be 0 }
        else { $flagValues | Should -Be @('CsvBlankFlag-Retain') }
        @(Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Keep-' -DomainController $script:domainController) | Should -Be @('Keep-Stable')
    }

    It 'projects AD attributes into drink namespaces' {
        if (-not $script:readinessStatus.ReadyForUserWrite) {
            $because = if ([string]::IsNullOrWhiteSpace($script:readinessStatus.BlockingMessage)) {
                'The drink attribute is not ready for user writes in the target environment.'
            }
            else {
                $script:readinessStatus.BlockingMessage
            }

            Set-ItResult -Skipped -Because $because
            return
        }

        Set-ADUserDrinkProjection -SamAccountName $script:userName -DomainController $script:domainController -Confirm:$false

        $expectedValues = @(
            'Profile-samAccountName={0}' -f $script:userName
            'Identity-userPrincipalName={0}' -f $script:userPrincipalName
            'Meta-employeeID={0}' -f $script:employeeId
            'Routing-mail={0}' -f $script:mail
            'Notify-pager={0}' -f $script:mail
        )
        $actualValues = Get-ADUserDrinkData -SamAccountName $script:userName -DomainController $script:domainController |
            Where-Object { $_ -match '^(Profile|Identity|Meta|Routing|Notify)-' } |
            Sort-Object

        $actualValues | Should -Be ($expectedValues | Sort-Object)
    }

    It 'preserves shipped CSV and default projection values in <Order> order' -ForEach @(
        @{ Order = 'CSV then projection' },
        @{ Order = 'projection then CSV' }
    ) {
        if (-not $script:readinessStatus.ReadyForUserWrite) {
            Set-ItResult -Skipped -Because 'The attribute is not ready for user writes.'
            return
        }

        $csvPath = Join-Path $TestDrive 'sample-coexistence.csv'
        @(
            'SamAccountName,ProfileTier,ProfileRegion,Flags,RoutingMailbox,TenantId,SyncState'
            ('{0},Gold,NA,Enabled;Audited,Queue,Example,Synced' -f $script:userName)
        ) | Set-Content -LiteralPath $csvPath -Encoding utf8
        $configPath = Join-Path $PSScriptRoot '../examples/data/drink-ingestion-config.json'
        Remove-ADUserDrinkData -SamAccountName $script:userName -Prefixes @('CsvProfile-', 'CsvRouting-', 'Flags-', 'Tenant-', 'Sync-', 'Profile-', 'Identity-', 'Meta-', 'Routing-', 'Notify-') -DomainController $script:domainController -Confirm:$false
        if ($Order -eq 'CSV then projection') {
            Import-ADUserDrinkCsvData -CsvPath $csvPath -ConfigPath $configPath -DomainController $script:domainController -Confirm:$false | Out-Null
            Set-ADUserDrinkProjection -SamAccountName $script:userName -DomainController $script:domainController -Confirm:$false
        }
        else {
            Set-ADUserDrinkProjection -SamAccountName $script:userName -DomainController $script:domainController -Confirm:$false
            Import-ADUserDrinkCsvData -CsvPath $csvPath -ConfigPath $configPath -DomainController $script:domainController -Confirm:$false | Out-Null
        }

        $values = @(Get-ADUserDrinkData -SamAccountName $script:userName -DomainController $script:domainController)
        $expected = @(
            'CsvProfile-Tier=Gold', 'CsvProfile-Region=NA', 'CsvRouting-Mailbox=Queue'
            'Flags-Enabled', 'Flags-Audited', 'Tenant-Id=Example', 'Sync-State=Synced'
            ('Profile-samAccountName={0}' -f $script:userName)
            ('Identity-userPrincipalName={0}' -f $script:userPrincipalName)
            ('Meta-employeeID={0}' -f $script:employeeId)
            ('Routing-mail={0}' -f $script:mail)
            ('Notify-pager={0}' -f $script:mail)
        )
        $owned = @($values | Where-Object { $_ -match '^(CsvProfile|CsvRouting|Flags|Tenant|Sync|Profile|Identity|Meta|Routing|Notify)-' } | Sort-Object)
        $owned | Should -Be ($expected | Sort-Object)
        $values | Should -Contain 'Keep-Stable'
    }

    It 'applies case-only replacements on a real directory' {
        if (-not $script:readinessStatus.ReadyForUserWrite) {
            Set-ItResult -Skipped -Because 'The attribute is not ready for user writes.'
            return
        }

        Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ 'Case-' = @('first') } -DomainController $script:domainController -Confirm:$false
        Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ 'Case-' = @('FIRST') } -DomainController $script:domainController -Confirm:$false
        $values = Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Case-' -DomainController $script:domainController
        $values | Should -BeExactly @('Case-FIRST')
    }

    It 'preserves an unrelated value added after the writer reads its snapshot' {
        if (-not $script:readinessStatus.ReadyForUserWrite) {
            Set-ItResult -Skipped -Because 'The attribute is not ready for user writes.'
            return
        }

        Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ 'Stale-' = @('Old') } -DomainController $script:domainController -Confirm:$false
        $snapshot = Get-ADUser -Identity $script:userName -Properties drink -Server $script:domainController -ErrorAction Stop
        Set-ADUser -Identity $script:userName -Add @{ drink = @('Concurrent-Preserved') } -Server $script:domainController -ErrorAction Stop

        & (Get-Module DrunkenAD) {
            param($User, $Server)
            $context = New-DrunkenADWriteContext -Server $Server
            Invoke-DrunkenADPrefixWrite -User $User -PrefixMap @{ 'Stale-' = @('New') } -Context $context -Confirm:$false
        } $snapshot $script:domainController

        Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Concurrent-' -DomainController $script:domainController | Should -Be @('Concurrent-Preserved')
        Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Stale-' -DomainController $script:domainController | Should -Be @('Stale-New')
    }

    # These seven areas are unverified live contracts until an approved Tier1 run.
    # Select with -Tag Tier1; both environment opt-ins are also mandatory.
    Context 'Bounded Tier1 live regressions' -Tag 'Tier1' -Skip:(-not $script:runTier1) {
        BeforeAll {
            $script:tier1NeedsReset = $false

            function Assert-Tier1OptIn {
                if ($env:DRUNKENAD_RUN_INTEGRATION -ne '1' -or $env:DRUNKENAD_RUN_TIER1 -ne '1') {
                    throw 'Tier1 requires both DRUNKENAD_RUN_INTEGRATION=1 and DRUNKENAD_RUN_TIER1=1.'
                }
            }

            function Get-Tier1OwnedUser {
                Assert-Tier1OptIn
                if (-not $script:createdUser -or $null -eq $script:userGuid -or $script:userGuid -eq [guid]::Empty) {
                    throw 'Tier1 has no owned integration account GUID.'
                }
                $user = Get-ADUser -Identity $script:userGuid -Properties drink, Enabled -Server $script:domainController -ErrorAction Stop
                if ([guid]$user.ObjectGUID -ne $script:userGuid -or $user.Enabled -ne $false -or
                    -not [string]::Equals($user.SamAccountName, $script:userName, [StringComparison]::Ordinal)) {
                    throw 'Tier1 fixture ownership or disabled-account verification failed.'
                }
                $user
            }

            function Assert-Tier1OrdinalSet {
                param([AllowEmptyCollection()][string[]]$Actual, [AllowEmptyCollection()][string[]]$Expected)
                $actualSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                $expectedSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                foreach ($value in $Actual) { [void]$actualSet.Add($value) }
                foreach ($value in $Expected) { [void]$expectedSet.Add($value) }
                @($Actual).Count | Should -Be $actualSet.Count -Because 'duplicate values must not be hidden by set comparison'
                @($Expected).Count | Should -Be $expectedSet.Count
                $actualSet.SetEquals($expectedSet) | Should -BeTrue -Because 'fresh AD values must match ordinally, independently of ordering'
            }

            function Assert-Tier1StoredValues {
                param([AllowEmptyCollection()][string[]]$Expected)
                $actual = Get-Tier1OwnedUser
                Assert-Tier1OrdinalSet -Actual @($actual.drink) -Expected $Expected
            }

            function Assert-Tier1DirectoryFailure {
                param($Failure, [int[]]$ExpectedCodes)
                $Failure | Should -Not -BeNullOrEmpty
                # Require a server-side Set-ADUser error, not a binding, authentication, or transport failure.
                # These are AD DS Win32 error codes, not assumed LDAP wire result codes.
                $match = [regex]::Match($Failure.FullyQualifiedErrorId, '^ActiveDirectoryServer:([0-9]+),.*SetADUser$')
                $match.Success | Should -BeTrue -Because 'an unrecognized error is an evidence gap, not proof of atomic directory rejection'
                [int]$match.Groups[1].Value | Should -BeIn $ExpectedCodes
            }

            function Reset-Tier1Drink {
                param([string[]]$Values = @('T1Keep-Stable'))
                $owned = Get-Tier1OwnedUser
                Set-ADUser -Identity $owned.ObjectGUID -Replace @{ drink = [string[]]$Values } -Server $script:domainController -Confirm:$false -ErrorAction Stop
                Assert-Tier1StoredValues -Expected $Values
            }

            function Initialize-Tier1Case {
                Assert-Tier1OptIn
                if (-not $script:readinessStatus.ReadyForUserWrite) {
                    Set-ItResult -Skipped -Because 'Evidence Gap: drink is not ready for live Tier1 user writes.'
                    return $false
                }
                $script:tier1NeedsReset = $true
                Reset-Tier1Drink
                return $true
            }

            function Get-Tier1WriteContext {
                $context = & (Get-Module DrunkenAD) {
                    param($Server)
                    New-DrunkenADWriteContext -Server $Server
                } $script:domainController
                $context.Server | Should -BeExactly $script:domainController
                $context
            }

            function Get-Tier1Plan {
                param($Snapshot, [hashtable]$Map, $WriteContext)
                & (Get-Module DrunkenAD) {
                    param($User, $PrefixMap, $Context)
                    Get-DrunkenADPrefixWritePlan -CurrentValues $User.drink -PrefixMap $PrefixMap -RangeUpper $Context.RangeUpper
                } $Snapshot $Map $WriteContext
            }

            function Invoke-Tier1SnapshotWrite {
                param($Snapshot, [hashtable]$Map, $WriteContext)
                # Invoke the actual writer with the retained snapshot, never a synthetic AD object.
                & (Get-Module DrunkenAD) {
                    param($User, $PrefixMap, $Context)
                    Invoke-DrunkenADPrefixWrite -User $User -PrefixMap $PrefixMap -Context $Context -Confirm:$false -ErrorAction Stop
                } $Snapshot $Map $WriteContext
            }

            function Get-Tier1DrinkVersion {
                $owned = Get-Tier1OwnedUser
                $metadata = @(Get-ADReplicationAttributeMetadata -Object $owned.DistinguishedName -Server $script:domainController -Properties drink -ErrorAction Stop |
                    Where-Object { $_.AttributeName -eq 'drink' })
                if ($metadata.Count -ne 1 -or $null -eq $metadata[0].Version -or [long]$metadata[0].Version -lt 1) {
                    throw 'Evidence Gap: expected one readable drink replication metadata version on the pinned DC.'
                }
                [long]$metadata[0].Version
            }

            Assert-Tier1OptIn
            # Validate the installed AD parameter surface; never replace it with test stubs.
            $requiredParameters = @{
                'Get-ADUser' = @('Identity', 'Server', 'Properties')
                'Set-ADUser' = @('Identity', 'Server', 'Add', 'Remove', 'Replace', 'Confirm')
                'Get-ADReplicationAttributeMetadata' = @('Object', 'Server', 'Properties')
            }
            foreach ($name in $requiredParameters.Keys) {
                $command = Get-Command $name -Module ActiveDirectory -ErrorAction Stop
                foreach ($parameter in $requiredParameters[$name]) {
                    if (-not $command.Parameters.ContainsKey($parameter)) {
                        throw "Evidence Gap: installed ActiveDirectory command $name lacks -$parameter."
                    }
                }
            }
        }

        AfterEach {
            if ($script:tier1NeedsReset) {
                Reset-Tier1Drink
                $script:tier1NeedsReset = $false
            }
        }

        It 'observes stale Remove behavior without a half-applied write' {
            if (-not (Initialize-Tier1Case)) { return }
            Reset-Tier1Drink -Values @('T1Keep-Stable', 'T1Race-Missing', 'T1Race-Remaining')
            $snapshot = Get-Tier1OwnedUser
            $context = Get-Tier1WriteContext
            $map = @{ 'T1Race-' = @('New', 'Peer') }
            $plan = Get-Tier1Plan $snapshot $map $context
            Assert-Tier1OrdinalSet $plan.Remove @('T1Race-Missing', 'T1Race-Remaining')
            Assert-Tier1OrdinalSet $plan.Add @('T1Race-New', 'T1Race-Peer')
            Set-ADUser -Identity $script:userGuid -Remove @{ drink = @('T1Race-Missing') } -Server $script:domainController -Confirm:$false -ErrorAction Stop
            $before = Get-Tier1OwnedUser
            Assert-Tier1OrdinalSet @($before.drink) @('T1Keep-Stable', 'T1Race-Remaining')

            $failure = $null
            try { Invoke-Tier1SnapshotWrite $snapshot $map $context }
            catch { $failure = $_ }
            # AD permissive modify can ignore a missing value. Prove the whole
            # observed outcome instead of treating a stale snapshot as a lock.
            if ($null -ne $failure) {
                Assert-Tier1StoredValues -Expected @($before.drink)
                Assert-Tier1DirectoryFailure $failure @(8202)
                Write-Information 'Tier1 stale Remove: terminating error with unchanged state.' -InformationAction Continue
            }
            else {
                Assert-Tier1StoredValues @('T1Keep-Stable', 'T1Race-New', 'T1Race-Peer')
                Write-Information 'Tier1 stale Remove: missing value ignored, complete Remove/Add applied.' -InformationAction Continue
            }
        }

        It 'observes duplicate Add behavior without duplicates or a half-applied write' {
            if (-not (Initialize-Tier1Case)) { return }
            Reset-Tier1Drink -Values @('T1Keep-Stable', 'T1Race-Old')
            $snapshot = Get-Tier1OwnedUser
            $context = Get-Tier1WriteContext
            $map = @{ 'T1Race-' = @('New', 'Peer') }
            $plan = Get-Tier1Plan $snapshot $map $context
            Assert-Tier1OrdinalSet $plan.Remove @('T1Race-Old')
            Assert-Tier1OrdinalSet $plan.Add @('T1Race-New', 'T1Race-Peer')
            Set-ADUser -Identity $script:userGuid -Add @{ drink = @('T1Race-New') } -Server $script:domainController -Confirm:$false -ErrorAction Stop
            Assert-Tier1StoredValues @('T1Keep-Stable', 'T1Race-Old', 'T1Race-New')

            $failure = $null
            try { Invoke-Tier1SnapshotWrite $snapshot $map $context }
            catch { $failure = $_ }
            # AD permissive modify may ignore the duplicate; either outcome must be atomic.
            if ($null -ne $failure) {
                Assert-Tier1StoredValues @('T1Keep-Stable', 'T1Race-Old', 'T1Race-New')
                Assert-Tier1DirectoryFailure $failure @(8205)
                Write-Information 'Tier1 duplicate Add: terminating error with unchanged state.' -InformationAction Continue
            }
            else {
                Assert-Tier1StoredValues @('T1Keep-Stable', 'T1Race-New', 'T1Race-Peer')
                Write-Information 'Tier1 duplicate Add: duplicate ignored, complete Remove/Add applied.' -InformationAction Continue
            }
        }

        It 'keeps a case-variant collision atomic and preserves the existing spelling' {
            if (-not (Initialize-Tier1Case)) { return }
            Reset-Tier1Drink -Values @('T1Keep-Stable', 'T1Race-Old')
            $snapshot = Get-Tier1OwnedUser
            $context = Get-Tier1WriteContext
            $map = @{ 'T1Race-' = @('new', 'Peer') }
            $plan = Get-Tier1Plan $snapshot $map $context
            Assert-Tier1OrdinalSet $plan.Remove @('T1Race-Old')
            Assert-Tier1OrdinalSet $plan.Add @('T1Race-new', 'T1Race-Peer')
            Set-ADUser -Identity $script:userGuid -Add @{ drink = @('T1Race-NEW') } -Server $script:domainController -Confirm:$false -ErrorAction Stop
            Assert-Tier1StoredValues @('T1Keep-Stable', 'T1Race-Old', 'T1Race-NEW')

            $failure = $null
            try { Invoke-Tier1SnapshotWrite $snapshot $map $context }
            catch { $failure = $_ }
            if ($null -ne $failure) {
                Assert-Tier1StoredValues @('T1Keep-Stable', 'T1Race-Old', 'T1Race-NEW')
                Assert-Tier1DirectoryFailure $failure @(8205)
                Write-Information 'Tier1 case collision: terminating error with unchanged ordinal state.' -InformationAction Continue
            }
            else {
                Assert-Tier1StoredValues @('T1Keep-Stable', 'T1Race-NEW', 'T1Race-Peer')
                Write-Information 'Tier1 case collision: duplicate ignored, complete update with existing spelling retained.' -InformationAction Continue
            }
        }

        It 'checks live rangeUpper exact, overlong, and supplementary-character boundaries' {
            if (-not (Initialize-Tier1Case)) { return }
            $context = Get-Tier1WriteContext
            # Bound allocation and directory payload; missing/unusual schema limits are evidence gaps.
            if ($null -eq $context.RangeUpper -or $context.RangeUpper -lt 16 -or $context.RangeUpper -gt 4096) {
                Set-ItResult -Skipped -Because 'Evidence Gap: rangeUpper must be present and between 16 and 4096 for this bounded probe.'
                return
            }
            $limit = [int]$context.RangeUpper
            $prefix = 'T1Limit-'
            $pair = [char]::ConvertFromUtf32(0x1F642)
            foreach ($kind in @('BMP', 'SurrogatePair')) {
                Reset-Tier1Drink -Values @('T1Keep-Stable', 'T1Limit-Old', 'T1Peer-Old')
                $suffix = if ($kind -eq 'BMP') { 'x' * ($limit - $prefix.Length) } else { ('x' * ($limit - $prefix.Length - 2)) + $pair }
                $exact = $prefix + $suffix
                $exact.Length | Should -Be $limit
                Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ $prefix = @($suffix) } -DomainController $script:domainController -Confirm:$false -ErrorAction Stop
                Assert-Tier1StoredValues @('T1Keep-Stable', 'T1Peer-Old', $exact)

                # In the second iteration the pair straddles the UTF-16 limit, without an unpaired surrogate.
                $overSuffix = if ($kind -eq 'BMP') { $suffix + 'x' } else { ('x' * ($limit - $prefix.Length - 1)) + $pair }
                $overlong = $prefix + $overSuffix
                $overlong.Length | Should -Be ($limit + 1)
                { Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ $prefix = @($overSuffix); 'T1Peer-' = @('New') } -DomainController $script:domainController -Confirm:$false -ErrorAction Stop } |
                    Should -Throw '*target schema allows at most*'
                Assert-Tier1StoredValues @('T1Keep-Stable', 'T1Peer-Old', $exact)

                # Probe the server too: the module's preflight alone cannot prove the live limit.
                $failure = $null
                try {
                    Set-ADUser -Identity $script:userGuid -Remove @{ drink = @($exact, 'T1Peer-Old') } -Add @{ drink = @($overlong, 'T1Peer-New') } -Server $script:domainController -Confirm:$false -ErrorAction Stop
                }
                catch { $failure = $_ }
                Assert-Tier1StoredValues @('T1Keep-Stable', 'T1Peer-Old', $exact)
                $failure | Should -Not -BeNullOrEmpty -Because "live $kind overlong rejection must agree with the module's UTF-16 contract"
                Assert-Tier1DirectoryFailure $failure @(8239, 8322)
            }
        }

        It 'roundtrips Unicode ordinally through generic, prefixed, legacy, CSV, and projection writers' {
            if (-not (Initialize-Tier1Case)) { return }
            # Distinct leading tokens avoid asking AD to store canonically equivalent duplicates.
            $payloads = @(
                ('Composed-caf' + [char]0x00E9)
                ('Combining-cafe' + [char]0x0301)
                ('CJK-' + [char]0x6C34 + [char]0x8336)
                ('Supplementary-' + [char]::ConvertFromUtf32(0x1F642))
            )
            foreach ($writer in @('Generic', 'Prefixed', 'Legacy', 'CSV', 'Projection')) {
                Reset-Tier1Drink
                $expected = @('T1Keep-Stable') + @($payloads | ForEach-Object { 'T1Unicode-' + $_ })
                switch ($writer) {
                    'Generic' { Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ 'T1Unicode-' = $payloads } -DomainController $script:domainController -Confirm:$false -ErrorAction Stop }
                    'Prefixed' { Set-ADUserDrinkPrefixedData -SamAccountName $script:userName -PrefixMap @{ 'T1Unicode-' = $payloads } -DomainController $script:domainController -Confirm:$false -ErrorAction Stop }
                    'Legacy' { Update-ADUserDrinkAttribute -SamAccountName $script:userName -Prefixes 'T1Unicode-' -DrinkValues $payloads -DomainController $script:domainController -AutoConfirm -ErrorAction Stop }
                    'CSV' {
                        $path = Join-Path $TestDrive 'tier1-unicode.csv'
                        [pscustomobject]@{ SamAccountName = $script:userName; Payload = $payloads -join ';' } | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
                        $result = Import-ADUserDrinkCsvData -CsvPath $path -NamespaceMap @{ 'T1Unicode-' = @(@{ Column = 'Payload'; SplitOn = ';' }) } -DomainController $script:domainController -Confirm:$false -ErrorAction Stop
                        $result.Status | Should -Be 'Written'
                    }
                    'Projection' {
                        $seed = @('T1Keep-Stable') + @($payloads | ForEach-Object { 'T1Source-' + $_ })
                        Reset-Tier1Drink -Values $seed
                        # A single self-projection exercises Unicode source attributes without changing anything except drink.
                        Set-ADUserDrinkProjection -SamAccountName $script:userName -AttributeMap @{ 'T1Unicode-' = @('drink') } -DomainController $script:domainController -Confirm:$false -ErrorAction Stop
                        $expected = $seed + @($seed | ForEach-Object { 'T1Unicode-drink=' + $_ })
                    }
                }
                Assert-Tier1StoredValues -Expected $expected
                Assert-Tier1OrdinalSet -Actual @(Get-ADUserDrinkData -SamAccountName $script:userName -DomainController $script:domainController -ErrorAction Stop) -Expected $expected
            }
        }

        It 'reads all 1600-plus values and preserves a large unrelated prefix during replacement' {
            if (-not (Initialize-Tier1Case)) { return }
            # Fixed 1602-value bound; no domain searches, extra accounts, or unbounded growth.
            $bulk = @(1..1600 | ForEach-Object { 'T1Bulk-{0:D4}' -f $_ })
            $seed = @('T1Keep-Stable', 'T1Small-Old') + $bulk
            try { Reset-Tier1Drink -Values $seed }
            catch {
                if ($_.FullyQualifiedErrorId -notmatch '^ActiveDirectoryServer:8659,.*SetADUser$') { throw }
                Assert-Tier1StoredValues @('T1Keep-Stable')
                Set-ItResult -Skipped -Because 'Evidence Gap: the server rejected the 1602-value fixture at its JET page-size limit before range retrieval could be tested. No directory limits were changed.'
                return
            }
            Assert-Tier1OrdinalSet -Actual @(Get-ADUserDrinkData -SamAccountName $script:userName -DomainController $script:domainController -ErrorAction Stop) -Expected $seed
            Assert-Tier1OrdinalSet -Actual @(Get-AdUserDrinkPrefixedData -SamAccountName $script:userName -DrinkValuePrefix 'T1Bulk-' -DomainController $script:domainController -ErrorAction Stop) -Expected $bulk

            Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ 'T1Small-' = @('New') } -DomainController $script:domainController -Confirm:$false -ErrorAction Stop
            $expected = @('T1Keep-Stable', 'T1Small-New') + $bulk
            Assert-Tier1StoredValues $expected
            Assert-Tier1OrdinalSet -Actual @(Get-ADUserDrinkData -SamAccountName $script:userName -DomainController $script:domainController -ErrorAction Stop) -Expected $expected

            # Replacing the large slice also detects an incomplete writer snapshot.
            Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ 'T1Bulk-' = @('Replacement') } -DomainController $script:domainController -Confirm:$false -ErrorAction Stop
            Assert-Tier1StoredValues @('T1Keep-Stable', 'T1Small-New', 'T1Bulk-Replacement')
        }

        It 'leaves the drink replication metadata version unchanged for no-op CSV and projection' {
            if (-not (Initialize-Tier1Case)) { return }
            foreach ($writer in @('CSV', 'Projection')) {
                Reset-Tier1Drink
                $baselineVersion = Get-Tier1DrinkVersion
                if ($writer -eq 'CSV') {
                    $path = Join-Path $TestDrive 'tier1-noop.csv'
                    [pscustomobject]@{ SamAccountName = $script:userName; Payload = 'Stable' } | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
                    $parameters = @{ CsvPath = $path; NamespaceMap = @{ 'T1Noop-' = @(@{ Column = 'Payload' }) }; DomainController = $script:domainController; Confirm = $false; ErrorAction = 'Stop' }
                    $first = Import-ADUserDrinkCsvData @parameters
                    $expected = @('T1Keep-Stable', 'T1Noop-Stable')
                }
                else {
                    $parameters = @{ SamAccountName = $script:userName; AttributeMap = @{ 'T1Noop-' = @('samAccountName') }; DomainController = $script:domainController; Confirm = $false; PassThru = $true; ErrorAction = 'Stop' }
                    $first = Set-ADUserDrinkProjection @parameters
                    $expected = @('T1Keep-Stable', ('T1Noop-samAccountName=' + $script:userName))
                }
                $first.Status | Should -Be 'Written'
                Assert-Tier1StoredValues $expected
                $beforeVersion = Get-Tier1DrinkVersion
                $beforeVersion | Should -BeGreaterThan $baselineVersion -Because 'a real write must first demonstrate that metadata is observable'
                $second = if ($writer -eq 'CSV') { Import-ADUserDrinkCsvData @parameters } else { Set-ADUserDrinkProjection @parameters }
                $second.Status | Should -Be 'NoChange'
                Assert-Tier1StoredValues $expected
                Get-Tier1DrinkVersion | Should -Be $beforeVersion -Because 'no-op writes must not advance drink replication metadata on the same DC'
            }
        }
    }
}
