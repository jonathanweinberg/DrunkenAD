$script:runIntegration = $env:DRUNKENAD_RUN_INTEGRATION -eq '1'
$script:runTier1 = $script:runIntegration -and $env:DRUNKENAD_RUN_TIER1 -eq '1'
$script:domainController = $env:DRUNKENAD_TEST_DC
$script:dnsSuffix = $env:DRUNKENAD_TEST_DNS_SUFFIX
$script:testUserOu = $env:DRUNKENAD_TEST_USER_OU
$script:canRun = $script:runIntegration -and -not [string]::IsNullOrWhiteSpace($script:domainController) -and -not [string]::IsNullOrWhiteSpace($script:dnsSuffix)

Describe 'DrunkenAD integration tests' -Tag 'Integration' -Skip:(-not $script:canRun) {
    BeforeAll {
        $script:createdUser = $false
        $script:creationAttempted = $false
        $script:ownershipJournal = $null
        $script:ownershipRecorded = $false
        $script:testParent = $null
        $script:userGuid = $null
        $script:capacityTargetServer = $null
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

        function Assert-CapacityNativeCommand {
            param($Command)
            if ($Command -isnot [System.Management.Automation.CmdletInfo] -or
                $Command.ModuleName -ne 'ActiveDirectory' -or
                $Command.ImplementingType.Assembly.GetName().Name -ne 'Microsoft.ActiveDirectory.Management') {
                throw 'Evidence Gap: capacity preflight requires native ActiveDirectory commands before any directory access.'
            }
        }

        function Assert-CapacityTarget {
            param([string]$Server, $RootDse, $Controller, [string]$OuPath, $Ou)
            $address = $null
            $dnsLabel = '[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?'
            if ([string]::IsNullOrWhiteSpace($Server) -or $Server.Length -gt 253 -or
                $Server -notmatch "^(?i:$dnsLabel(?:\.$dnsLabel)+)$" -or
                [System.Net.IPAddress]::TryParse($Server, [ref]$address)) {
                throw 'Evidence Gap: capacity requires a canonical DC DNS hostname without an address, port, or trailing dot.'
            }
            if ($null -eq $RootDse -or @($RootDse).Count -ne 1 -or
                $null -eq $Controller -or @($Controller).Count -ne 1 -or $null -eq $Ou -or @($Ou).Count -ne 1) {
                throw 'Evidence Gap: capacity preflight requires one resolved RootDSE, controller, and OU.'
            }
            $RootDse = @($RootDse)[0]
            $Controller = @($Controller)[0]
            $Ou = @($Ou)[0]
            foreach ($required in @(
                @{ Object = $RootDse; Fields = @('dnsHostName', 'dsServiceName', 'defaultNamingContext') }
                @{ Object = $Controller; Fields = @('HostName', 'NTDSSettingsObjectDN', 'DefaultPartition', 'Domain', 'IsReadOnly', 'Enabled') }
                @{ Object = $Ou; Fields = @('DistinguishedName', 'ObjectClass', 'ObjectGUID') }
            )) {
                foreach ($field in $required.Fields) {
                    $property = $required.Object.PSObject.Properties[$field]
                    if ($null -eq $property -or @($property.Value).Count -ne 1 -or
                        [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                        throw 'Evidence Gap: capacity preflight metadata is missing or ambiguous.'
                    }
                }
            }
            $comparison = [StringComparison]::OrdinalIgnoreCase
            if (-not [string]::Equals($Server, [string]$RootDse.dnsHostName, $comparison) -or
                -not [string]::Equals($Server, [string]$Controller.HostName, $comparison) -or
                [string]::Equals($Server, [string]$Controller.Domain, $comparison) -or
                -not [string]::Equals([string]$RootDse.dsServiceName, [string]$Controller.NTDSSettingsObjectDN, $comparison) -or
                -not [string]::Equals([string]$RootDse.defaultNamingContext, [string]$Controller.DefaultPartition, $comparison)) {
                throw 'Evidence Gap: capacity target is an alias, domain selector, or inconsistent replica.'
            }
            if ($Controller.IsReadOnly -isnot [bool] -or $Controller.IsReadOnly -ne $false -or
                $Controller.Enabled -isnot [bool] -or $Controller.Enabled -ne $true) {
                throw 'Evidence Gap: capacity requires an enabled, positively identified writable DC.'
            }
            $ouGuid = [guid]::Empty
            if (-not [string]::Equals($OuPath, [string]$Ou.DistinguishedName, $comparison) -or
                -not ([string]$Ou.DistinguishedName).StartsWith('OU=', $comparison) -or
                -not ([string]$Ou.DistinguishedName).EndsWith(',' + [string]$RootDse.defaultNamingContext, $comparison) -or
                -not [string]::Equals([string]$Ou.ObjectClass, 'organizationalUnit', $comparison) -or
                -not [guid]::TryParse([string]$Ou.ObjectGUID, [ref]$ouGuid) -or $ouGuid -eq [guid]::Empty) {
                throw 'Evidence Gap: capacity requires the exact pre-existing OU in the verified DC domain.'
            }
            ([string]$RootDse.dnsHostName).ToLowerInvariant()
        }

        $runCapacity = $script:runTier1 -and $env:DRUNKENAD_RUN_CAPACITY -eq '1'
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../DrunkenAD/DrunkenAD.psd1'
        Import-Module $modulePath -Force -ErrorAction Stop
        Import-Module ActiveDirectory -ErrorAction Stop
        if ($runCapacity) {
            # Establish native provenance before readiness, preflight reads, or fixture creation.
            foreach ($commandName in @('Get-ADRootDSE', 'Get-ADDomainController', 'Get-ADOrganizationalUnit',
                'New-ADUser', 'Remove-ADUser', 'Get-ADUser', 'Set-ADUser', 'Get-ADReplicationAttributeMetadata')) {
                Assert-CapacityNativeCommand (Get-Command $commandName -ErrorAction Stop)
            }
            $moduleCommands = & (Get-Module DrunkenAD) {
                foreach ($commandName in @('Get-ADRootDSE', 'Get-ADObject', 'Get-ADUser', 'Set-ADUser')) {
                    Get-Command $commandName -ErrorAction Stop
                }
            }
            foreach ($command in $moduleCommands) { Assert-CapacityNativeCommand $command }
            $capacityRootDse = @(Get-ADRootDSE -Server $script:domainController -ErrorAction Stop)
            $capacityController = @(Get-ADDomainController -Identity $script:domainController -Server $script:domainController -ErrorAction Stop)
            $capacityOu = @(Get-ADOrganizationalUnit -Identity $script:testUserOu -Server $script:domainController -ErrorAction Stop)
            $script:domainController = Assert-CapacityTarget -Server $script:domainController -RootDse $capacityRootDse -Controller $capacityController -OuPath $script:testUserOu -Ou $capacityOu
            $script:testParent = @($capacityOu)[0]
            $script:capacityTargetServer = $script:domainController
        }
        $script:readinessStatus = Test-ADDrinkAttributeReadyForUserWrite -Server $script:domainController -PassThru

        if ($script:runTier1) {
            # Use the same validated DC for fixture creation, writes, reads, and cleanup.
            if ([string]::IsNullOrWhiteSpace($script:readinessStatus.Server)) {
                throw 'Evidence Gap: Tier1 readiness did not return a pinned server.'
            }
            if ($runCapacity -and -not [string]::Equals($script:readinessStatus.Server, $script:domainController, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Evidence Gap: readiness changed the verified capacity DC.'
            }
            $script:domainController = $script:readinessStatus.Server
            if (-not $runCapacity) {
                $script:testParent = Get-ADOrganizationalUnit -Identity $script:testUserOu -Server $script:domainController -ErrorAction Stop
            }
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
            if ([string]::IsNullOrWhiteSpace($script:testUserOu) -or
                [string]::IsNullOrWhiteSpace($env:DRUNKENAD_TEST_JOURNAL_DIRECTORY)) {
                throw 'Fixture creation requires a pre-existing test OU and a private DRUNKENAD_TEST_JOURNAL_DIRECTORY outside the checkout.'
            }
            if (-not $runCapacity) {
                $fixtureServer = [string]$script:readinessStatus.Server
                if ([string]::IsNullOrWhiteSpace($fixtureServer)) {
                    throw 'Fixture creation requires a concrete readiness-selected DC.'
                }
                if (-not [string]::Equals($script:domainController, $fixtureServer, [StringComparison]::OrdinalIgnoreCase)) {
                    $script:testParent = $null
                }
                $script:domainController = $fixtureServer
            }
            if ($null -eq $script:testParent) {
                $script:testParent = Get-ADOrganizationalUnit -Identity $script:testUserOu -Server $script:domainController -ErrorAction Stop
            }
            if (@($script:testParent).Count -ne 1 -or
                -not [string]::Equals([string]$script:testParent.DistinguishedName, $script:testUserOu, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Fixture creation requires the exact pre-existing test OU.'
            }
            if (-not $runCapacity) {
                $fixtureRootDse = @(Get-ADRootDSE -Server $script:domainController -ErrorAction Stop)
                $fixtureController = @(Get-ADDomainController -Identity $script:domainController -Server $script:domainController -ErrorAction Stop)
                $script:domainController = Assert-CapacityTarget -Server $script:domainController -RootDse $fixtureRootDse -Controller $fixtureController -OuPath $script:testUserOu -Ou @($script:testParent)
            }
            . (Join-Path $PSScriptRoot 'Support/IntegrationOwnership.ps1')
            $ownershipRunId = [Guid]::NewGuid()
            $script:runId = $ownershipRunId.ToString('N').Substring(0, 8)
            $script:userName = "DrunkenAD_$($script:runId)"
            $script:userPrincipalName = '{0}@{1}' -f $script:userName, $script:dnsSuffix
            $script:mail = '{0}@{1}' -f $script:userName, $script:dnsSuffix
            $script:employeeId = [string](Get-Random -Minimum 100000 -Maximum 999999)
            $script:ownershipJournal = New-DrunkenADIntegrationJournal -Directory $env:DRUNKENAD_TEST_JOURNAL_DIRECTORY `
                -ForbiddenRoot (Split-Path $PSScriptRoot -Parent) -Server $script:domainController `
                -ParentDn $script:testParent.DistinguishedName -ParentGuid ([guid]$script:testParent.ObjectGUID) `
                -UserName $script:userName -RunId $ownershipRunId `
                -TestSourceSHA256 (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'DrunkenAD.Integration.Tests.ps1')).Hash

            $newUserParams = @{
                Name              = $script:userName
                SamAccountName    = $script:userName
                UserPrincipalName = $script:userPrincipalName
                AccountPassword   = (New-IntegrationPassword | ConvertTo-SecureString -AsPlainText -Force)
                Enabled           = $false
                Description       = $script:ownershipJournal.Intent.OwnershipToken
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

            Write-DrunkenADIntegrationJournalEvent -Journal $script:ownershipJournal -State CreateIssued
            $script:creationAttempted = $true
            try {
                $created = New-ADUser @newUserParams -PassThru
                $createdGuid = [guid]::Empty
                if (@($created).Count -ne 1 -or -not [guid]::TryParse([string]$created.ObjectGUID, [ref]$createdGuid) -or $createdGuid -eq [guid]::Empty) {
                    throw 'The isolated integration account did not return one valid ObjectGUID.'
                }
                $script:userGuid = $createdGuid
                Write-DrunkenADIntegrationJournalEvent -Journal $script:ownershipJournal -State Created -ObjectGuid $createdGuid
                $script:ownershipRecorded = $true
                $createdReadback = @(Get-ADUser -Filter "ObjectGUID -eq '$createdGuid'" -Properties Description,Enabled -Server $script:domainController -ErrorAction Stop)
                Assert-DrunkenADIntegrationOwnedUser -Journal $script:ownershipJournal -User $createdReadback -ExpectedGuid $createdGuid
                $createdParent = Get-ADOrganizationalUnit -Identity ([guid]$script:ownershipJournal.Intent.ParentGuid) -Server $script:domainController -ErrorAction Stop
                $createdWithinParent = @(Get-ADUser -Filter "ObjectGUID -eq '$createdGuid'" -SearchBase $script:ownershipJournal.Intent.ParentDn -SearchScope OneLevel -Server $script:domainController -ErrorAction Stop)
                if ([guid]$createdParent.ObjectGUID -ne [guid]$script:ownershipJournal.Intent.ParentGuid -or
                    -not [string]::Equals([string]$createdParent.DistinguishedName, [string]$script:ownershipJournal.Intent.ParentDn, [StringComparison]::OrdinalIgnoreCase) -or
                    $createdWithinParent.Count -ne 1 -or [guid]$createdWithinParent[0].ObjectGUID -ne $createdGuid) {
                    throw 'The created fixture and its recorded parent were not confirmed before test writes.'
                }
                $script:createdUser = $true
            }
            catch {
                $creationFailure = $_
                # An error does not prove that the server did not create the account.
                if ($null -eq $script:userGuid) {
                    try { Write-DrunkenADIntegrationJournalEvent -Journal $script:ownershipJournal -State CreationOutcomeUnknown }
                    catch { $creationFailure.Exception.Data['OwnershipJournalFailure'] = $true }
                }
                throw $creationFailure
            }
        }
    }

    AfterAll {
        if (-not (Get-Variable -Name createdUser -Scope Script -ErrorAction SilentlyContinue)) {
            $script:createdUser = $false
        }

        if ($script:creationAttempted) {
            if (-not $script:ownershipRecorded -or $null -eq $script:userGuid -or $script:userGuid -eq [guid]::Empty) {
                throw 'CleanupUnknown: creation may have committed without a durable GUID receipt. Independently reconcile the private intent; do not retry creation or delete by name.'
            }
            try {
                $intent = $script:ownershipJournal.Intent
                if (-not [string]::Equals([string]$intent.Server, $script:domainController, [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'The cleanup target differs from the recorded creation target.'
                }
                $parentBeforeCleanup = Get-ADOrganizationalUnit -Identity ([guid]$intent.ParentGuid) -Server $script:domainController -ErrorAction Stop
                if ([guid]$parentBeforeCleanup.ObjectGUID -ne [guid]$intent.ParentGuid -or
                    -not [string]::Equals([string]$parentBeforeCleanup.DistinguishedName, [string]$intent.ParentDn, [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'The recorded integration parent changed; cleanup ownership is uncertain.'
                }
                $owned = @(Get-ADUser -Filter "ObjectGUID -eq '$($script:userGuid)'" -Properties Description,Enabled -Server $script:domainController -ErrorAction Stop)
                $removeErrorObserved = $false
                if ($owned.Count -gt 0) {
                    Assert-DrunkenADIntegrationOwnedUser -Journal $script:ownershipJournal -User $owned -ExpectedGuid $script:userGuid
                    $withinParent = @(Get-ADUser -Filter "ObjectGUID -eq '$($script:userGuid)'" -SearchBase $intent.ParentDn -SearchScope OneLevel -Server $script:domainController -ErrorAction Stop)
                    if ($withinParent.Count -ne 1 -or [guid]$withinParent[0].ObjectGUID -ne $script:userGuid) {
                        throw 'The owned fixture is no longer directly inside its recorded parent.'
                    }
                    Write-DrunkenADIntegrationJournalEvent -Journal $script:ownershipJournal -State DeleteIssued -ObjectGuid $script:userGuid
                    try { Remove-ADUser -Identity $script:userGuid -Server $script:domainController -Confirm:$false -ErrorAction Stop }
                    catch { $removeErrorObserved = $true }
                }
                $remainingByGuid = @(Get-ADUser -Filter "ObjectGUID -eq '$($script:userGuid)'" -Server $script:domainController -ErrorAction Stop)
                $parentAfterCleanup = Get-ADOrganizationalUnit -Identity ([guid]$intent.ParentGuid) -Server $script:domainController -ErrorAction Stop
                if ($remainingByGuid.Count -ne 0 -or [guid]$parentAfterCleanup.ObjectGUID -ne [guid]$intent.ParentGuid -or
                    -not [string]::Equals([string]$parentAfterCleanup.DistinguishedName, [string]$intent.ParentDn, [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'Owned fixture absence and parent preservation were not confirmed.'
                }
                Write-DrunkenADIntegrationJournalEvent -Journal $script:ownershipJournal -State AbsenceVerified -ObjectGuid $script:userGuid -OperationErrorObserved:$removeErrorObserved
                $script:createdUser = $false
            }
            catch {
                $cleanupFailure = $_
                try { Write-DrunkenADIntegrationJournalEvent -Journal $script:ownershipJournal -State CleanupUnknown -ObjectGuid $script:userGuid }
                catch { $cleanupFailure.Exception.Data['OwnershipJournalFailure'] = $true }
                throw $cleanupFailure
            }
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

    # These cases are unverified live contracts until an approved Tier1 run.
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

            function Get-Tier1CapacityMetadata {
                $owned = Get-Tier1OwnedUser
                $metadata = @(Get-ADReplicationAttributeMetadata -Object $owned.DistinguishedName -Server $script:domainController -Properties drink -ErrorAction Stop |
                    Where-Object { $_.AttributeName -eq 'drink' })
                if ($metadata.Count -ne 1 -or $metadata[0].IsLinkValue -ne $false) {
                    throw 'Evidence Gap: capacity requires one nonlinked drink metadata record.'
                }
                $record = $metadata[0]
                $fields = @('Version', 'LastOriginatingChangeTime', 'LastOriginatingChangeDirectoryServerInvocationId',
                    'LastOriginatingChangeDirectoryServerIdentity', 'LastOriginatingChangeUsn', 'LocalChangeUsn')
                foreach ($fieldName in $fields) {
                    if ($null -eq $record.PSObject.Properties[$fieldName] -or [string]::IsNullOrWhiteSpace([string]$record.$fieldName)) {
                        throw "Evidence Gap: capacity metadata lacks $fieldName."
                    }
                }
                if ([long]$record.Version -lt 1 -or [long]$record.LastOriginatingChangeUsn -lt 1 -or
                    [long]$record.LocalChangeUsn -lt 1 -or [guid]$record.LastOriginatingChangeDirectoryServerInvocationId -eq [guid]::Empty) {
                    throw 'Evidence Gap: capacity metadata is not observable.'
                }
                # Copy scalar replication fields; AD value collections are compared independently.
                [pscustomobject]@{
                    Version = [long]$record.Version
                    OriginatingTimeTicks = ([datetime]$record.LastOriginatingChangeTime).Ticks
                    OriginatingInvocationId = [guid]$record.LastOriginatingChangeDirectoryServerInvocationId
                    OriginatingServerIdentity = [string]$record.LastOriginatingChangeDirectoryServerIdentity
                    OriginatingUsn = [long]$record.LastOriginatingChangeUsn
                    LocalUsn = [long]$record.LocalChangeUsn
                }
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

        It 'measures bounded scoped-write capacity and preserves whole state on a rejected request' -Tag 'Capacity' -Skip:($env:DRUNKENAD_RUN_CAPACITY -ne '1') {
            $capacityClock = [System.Diagnostics.Stopwatch]::StartNew()
            $capacityMaxSeconds = 120
            function Assert-CapacityTimeBudget {
                # A synchronous native call still requires the approved launcher's external watchdog.
                if ($capacityClock.Elapsed.TotalSeconds -ge $capacityMaxSeconds) {
                    throw 'Evidence Gap: CapacityTimeBoundReached; no further probe writes or capacity pass are permitted.'
                }
            }
            Assert-Tier1OptIn
            if ($env:DRUNKENAD_RUN_CAPACITY -ne '1') {
                throw 'Capacity requires the separate DRUNKENAD_RUN_CAPACITY=1 opt-in at execution time.'
            }
            if ([string]::IsNullOrWhiteSpace($script:capacityTargetServer) -or
                -not [string]::Equals($script:capacityTargetServer, $script:domainController, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Evidence Gap: capacity target was not verified before fixture creation or the pinned server changed.'
            }
            if (-not $script:readinessStatus.ReadyForUserWrite) {
                throw 'Evidence Gap: capacity was opted in but drink is not ready for user writes.'
            }
            # Native-only evidence: reject shadow functions and compatibility proxy commands.
            $capacityCommands = @(
                foreach ($capacityCommandName in @('Get-ADUser', 'Set-ADUser', 'Get-ADReplicationAttributeMetadata')) {
                    Get-Command $capacityCommandName -ErrorAction Stop
                }
                & (Get-Module DrunkenAD) { Get-Command Set-ADUser -ErrorAction Stop }
            )
            foreach ($capacityCommand in $capacityCommands) {
                if ($capacityCommand.CommandType -ne 'Cmdlet' -or $capacityCommand.ModuleName -ne 'ActiveDirectory' -or
                    $capacityCommand.ImplementingType.Assembly.GetName().Name -ne 'Microsoft.ActiveDirectory.Management') {
                    throw "Evidence Gap: capacity requires native ActiveDirectory provenance for $($capacityCommand.Name), including the production writer scope."
                }
            }

            # Fixed safety limits, not configurable targets or claims about a forest-wide ceiling.
            $capacityMaxPayloadValues = 1600
            $capacityStep = 128
            $capacityValueLength = 32
            $capacityMaxAttempts = 13
            $capacityPrefix = 'T1Capacity-'
            if ($null -eq $script:readinessStatus.RangeUpper -or $script:readinessStatus.RangeUpper -lt $capacityValueLength) {
                throw 'Evidence Gap: live rangeUpper must accommodate the fixed 32-code-unit capacity values.'
            }
            # Readiness is already the validated write-context shape from this run, on this pinned DC.
            $capacityContext = $script:readinessStatus
            $capacityContext.Server | Should -BeExactly $script:domainController
            Assert-CapacityTimeBudget
            if (-not (Initialize-Tier1Case)) { return }
            $capacityBaselineMetadata = Get-Tier1CapacityMetadata
            $capacityKeep = 'T1Keep-Stable'
            $capacityMarker = ('T1Capacity-M{0:D4}' -f 0).PadRight($capacityValueLength, 'x')
            $capacityExpected = @($capacityKeep, $capacityMarker)
            Assert-CapacityTimeBudget
            Reset-Tier1Drink -Values $capacityExpected
            $capacitySeedMetadata = Get-Tier1CapacityMetadata
            $capacitySeedMetadata.Version | Should -BeGreaterThan $capacityBaselineMetadata.Version -Because 'the seed must demonstrate observable replication metadata'
            $capacityPayload = @(1..$capacityMaxPayloadValues | ForEach-Object {
                ('T1Capacity-V{0:D4}' -f $_).PadRight($capacityValueLength, 'x')
            })
            $capacityAccepted = 0
            $capacityLastAcceptedWriteKind = 'SeedReplace'
            $capacityRejected = $null
            $capacityVerified = $false
            $capacityAttempts = 0

            while ($capacityAttempts -lt $capacityMaxAttempts) {
                Assert-CapacityTimeBudget
                Assert-Tier1OptIn
                if ($env:DRUNKENAD_RUN_CAPACITY -ne '1') { throw 'Capacity opt-in was withdrawn; no further probe writes are permitted.' }
                # Stop at the first recognized rejection; do not assume monotonic capacity under changing record history.
                $capacityNext = [Math]::Min($capacityMaxPayloadValues, $capacityAccepted + $capacityStep)
                if ($capacityNext -le $capacityAccepted -or $capacityNext -gt $capacityMaxPayloadValues) {
                    throw 'Evidence Gap: capacity search exceeded its fixed value bounds.'
                }
                $capacityAttempts++
                $capacityBefore = Get-Tier1OwnedUser
                Assert-Tier1OrdinalSet -Actual @($capacityBefore.drink) -Expected $capacityExpected
                $capacityBeforeMetadata = Get-Tier1CapacityMetadata
                $capacityNewMarker = ('T1Capacity-M{0:D4}' -f $capacityAttempts).PadRight($capacityValueLength, 'x')
                $capacityAdd = @($capacityNewMarker) + @($capacityPayload[$capacityAccepted..($capacityNext - 1)])
                $capacityProposed = @($capacityKeep, $capacityNewMarker) + @($capacityPayload[0..($capacityNext - 1)])
                $capacityProposed.Count | Should -Be ($capacityNext + 2)
                $capacityProposed.Count | Should -BeLessOrEqual ($capacityMaxPayloadValues + 2)
                foreach ($capacityValue in @($capacityMarker) + $capacityAdd) {
                    $capacityValue.Length | Should -Be $capacityValueLength
                }
                $capacitySuffixes = @($capacityProposed | Where-Object { $_.StartsWith($capacityPrefix, [StringComparison]::Ordinal) } |
                    ForEach-Object { $_.Substring($capacityPrefix.Length) })
                $capacityMap = @{ $capacityPrefix = $capacitySuffixes }
                $capacityPlan = Get-Tier1Plan $capacityBefore $capacityMap $capacityContext
                Assert-Tier1OrdinalSet -Actual $capacityPlan.Remove -Expected @($capacityMarker)
                Assert-Tier1OrdinalSet -Actual $capacityPlan.Add -Expected $capacityAdd
                Assert-Tier1OrdinalSet -Actual $capacityPlan.FinalDrinkValues -Expected $capacityProposed

                # A real Remove/Add tests rollback of an existing value as well as absence of partial additions.
                Assert-CapacityTimeBudget
                $capacityFailure = $null
                try {
                    Invoke-Tier1SnapshotWrite $capacityBefore $capacityMap $capacityContext
                }
                catch { $capacityFailure = $_ }
                $capacityAfter = Get-Tier1OwnedUser
                $capacityAfterMetadata = Get-Tier1CapacityMetadata
                if ($null -ne $capacityFailure) {
                    Assert-Tier1OrdinalSet -Actual @($capacityAfter.drink) -Expected @($capacityBefore.drink)
                    foreach ($capacityProperty in $capacityBeforeMetadata.PSObject.Properties) {
                        $capacityAfterMetadata.($capacityProperty.Name) | Should -BeExactly $capacityProperty.Value -Because 'a rejected request must preserve every captured replication field'
                    }
                    # 8659 = JET record too big; 8304 = maximum object size exceeded.
                    # Generic admin, constraint, permission, transport, and binding errors are not capacity proof.
                    Assert-Tier1DirectoryFailure $capacityFailure @(8659, 8304)
                    $capacityRejected = $capacityNext
                    Assert-CapacityTimeBudget
                    $capacityVerified = $true
                    break
                }
                else {
                    Assert-Tier1OrdinalSet -Actual @($capacityAfter.drink) -Expected $capacityProposed
                    $capacityAfterMetadata.Version | Should -BeGreaterThan $capacityBeforeMetadata.Version
                    Assert-CapacityTimeBudget
                    $capacityAccepted = $capacityNext
                    $capacityLastAcceptedWriteKind = 'ScopedRemoveAdd'
                    $capacityMarker = $capacityNewMarker
                    $capacityExpected = $capacityProposed
                    if ($capacityAccepted -eq $capacityMaxPayloadValues) {
                        throw "Evidence Gap: BoundReachedWithoutRejection; accepted $($capacityAccepted + 2) total drink values, including $($capacityAccepted + 1) values of $capacityValueLength UTF-16 code units. This is a lower bound, not a discovered ceiling or a passed rejection test."
                    }
                }
            }
            if (-not $capacityVerified) {
                throw "Evidence Gap: OperationBoundReached after $capacityAttempts requests; no verified capacity rejection."
            }
            Assert-CapacityTimeBudget
            Write-Information ("Capacity RejectionVerified: lastAcceptedTotal={0}; firstRejectedTotal={1}; namespaceValueUtf16Units={2}; unrelatedValues=1; unrelatedValueUtf16Units={3}; scopedProbeRequests={4}; elapsedSeconds={5:F1}; lastAcceptedWriteKind={6}; wholeDrinkAndMetadataUnchanged=True. Observed bracket for this fixture, history, and request shape only; not an exact or general AD ceiling. Large-range retrieval remains unverified." -f
                ($capacityAccepted + 2), ($capacityRejected + 2), $capacityValueLength, $capacityKeep.Length, $capacityAttempts, $capacityClock.Elapsed.TotalSeconds, $capacityLastAcceptedWriteKind) -InformationAction Continue
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

        It 'checks native <AttributeName> projection boundaries through <CommandName> under <CultureName>' -TestCases @(
            @{ CommandName = 'Set-ADUserDrinkProjection'; CultureName = 'en-US'; AttributeName = 'whenCreated' }
            @{ CommandName = 'Set-ADUserDrinkProjection'; CultureName = 'de-DE'; AttributeName = 'whenCreated' }
            @{ CommandName = 'Invoke-ADUserDrinkDataDemo'; CultureName = 'en-US'; AttributeName = 'whenCreated' }
            @{ CommandName = 'Invoke-ADUserDrinkDataDemo'; CultureName = 'de-DE'; AttributeName = 'whenCreated' }
            @{ CommandName = 'Set-ADUserDrinkProjection'; CultureName = 'en-US'; AttributeName = 'DistinguishedName' }
            @{ CommandName = 'Set-ADUserDrinkProjection'; CultureName = 'de-DE'; AttributeName = 'DistinguishedName' }
            @{ CommandName = 'Invoke-ADUserDrinkDataDemo'; CultureName = 'en-US'; AttributeName = 'DistinguishedName' }
            @{ CommandName = 'Invoke-ADUserDrinkDataDemo'; CultureName = 'de-DE'; AttributeName = 'DistinguishedName' }
        ) {
            param($CommandName, $CultureName, $AttributeName)
            if (-not (Initialize-Tier1Case)) { return }
            $context = Get-Tier1WriteContext
            if ($null -eq $context.RangeUpper -or $context.RangeUpper -lt 16 -or $context.RangeUpper -gt 4096) {
                Set-ItResult -Skipped -Because 'Evidence Gap: rangeUpper must be present and between 16 and 4096 for this bounded projection probe.'
                return
            }
            $limit = [int]$context.RangeUpper
            $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            $originalUICulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]::GetCultureInfo($CultureName)
                [System.Threading.Thread]::CurrentThread.CurrentUICulture = [cultureinfo]::GetCultureInfo($CultureName)
                [cultureinfo]::CurrentCulture.Name | Should -BeExactly $CultureName
                [cultureinfo]::CurrentUICulture.Name | Should -BeExactly $CultureName

                $owned = Get-Tier1OwnedUser
                $source = Get-ADUser -Identity $owned.ObjectGUID -Properties $AttributeName -Server $script:domainController -ErrorAction Stop
                [guid]$source.ObjectGUID | Should -Be $script:userGuid
                $sourceValue = $source.$AttributeName
                $prefixStem = 'T1Projection[01]-'
                if ($AttributeName -eq 'whenCreated') {
                    ($sourceValue -is [datetime]) | Should -BeTrue -Because 'whenCreated must remain a native scalar DateTime'
                    $rendered = $sourceValue.ToString('MM/dd/yyyy HH:mm:ss', [cultureinfo]::InvariantCulture)
                }
                else {
                    ($sourceValue -is [string]) | Should -BeTrue -Because 'DistinguishedName must remain a native scalar string'
                    $sourceValue | Should -Match ','
                    $sourceValue | Should -Match '='
                    $rendered = $sourceValue
                    $prefixStem += [char]0x00E9 + [char]::ConvertFromUtf32(0x1F642) + '-'
                }
                $record = $AttributeName + '=' + $rendered
                $peerExpected = 'T1Peer-samAccountName=' + $owned.SamAccountName
                $paddingLength = $limit - $prefixStem.Length - $record.Length
                if ($paddingLength -lt 0 -or $peerExpected.Length -gt $limit) {
                    Set-ItResult -Skipped -Because 'Evidence Gap: live rangeUpper is too small for the prefixed native source or companion projection. No schema or source attributes were changed.'
                    return
                }

                # Vary only the literal prefix; count the complete value in UTF-16 code units.
                $exactPrefix = $prefixStem + ('x' * $paddingLength)
                $negativePrefix = $exactPrefix + 'x'
                $exact = $exactPrefix + $record
                $overlong = $negativePrefix + $record
                $exact.Length | Should -Be $limit
                $overlong.Length | Should -Be ($limit + 1)
                $negativeSeed = @('T1Keep-Stable', 'T1Peer-Old', ($negativePrefix + 'Old'))
                Reset-Tier1Drink -Values $negativeSeed
                $beforeVersion = Get-Tier1DrinkVersion
                $parameters = @{
                    SamAccountName = $script:userName
                    AttributeMap = @{ $negativePrefix = @($AttributeName); 'T1Peer-' = @('samAccountName') }
                    DomainController = $script:domainController
                    Confirm = $false
                    PassThru = $true
                    ErrorAction = 'Stop'
                }
                $failure = $null
                try { & $CommandName @parameters | Out-Null }
                catch { $failure = $_ }
                $failure | Should -Not -BeNullOrEmpty
                $failure.Exception.Message | Should -BeExactly "A drink value has $($limit + 1) characters; the target schema allows at most $limit, including the prefix."
                $failure.FullyQualifiedErrorId | Should -Not -Match '^ActiveDirectoryServer:'
                Assert-Tier1StoredValues -Expected $negativeSeed
                Get-Tier1DrinkVersion | Should -Be $beforeVersion -Because 'local length rejection must not advance drink metadata or partially replace either namespace'

                Reset-Tier1Drink -Values @('T1Keep-Stable', 'T1Peer-Old', ($exactPrefix + 'Old'))
                $beforeVersion = Get-Tier1DrinkVersion
                $parameters.AttributeMap = @{ $exactPrefix = @($AttributeName); 'T1Peer-' = @('samAccountName') }
                $result = & $CommandName @parameters
                $result.Status | Should -Be 'Written'
                $expected = @('T1Keep-Stable', $peerExpected, $exact)
                Assert-Tier1OrdinalSet -Actual @($result.FinalDrinkValues) -Expected $expected
                Assert-Tier1StoredValues -Expected $expected
                Get-Tier1DrinkVersion | Should -BeGreaterThan $beforeVersion -Because 'the exact-limit replacement must advance drink metadata on the pinned DC'
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
                [System.Threading.Thread]::CurrentThread.CurrentUICulture = $originalUICulture
            }
        }
    }
}
