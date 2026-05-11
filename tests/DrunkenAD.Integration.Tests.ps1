$script:runIntegration = $env:DRUNKENAD_RUN_INTEGRATION -eq '1'
$script:domainController = $env:DRUNKENAD_TEST_DC
$script:dnsSuffix = $env:DRUNKENAD_TEST_DNS_SUFFIX
$script:testUserOu = $env:DRUNKENAD_TEST_USER_OU
$script:canRun = $script:runIntegration -and -not [string]::IsNullOrWhiteSpace($script:domainController) -and -not [string]::IsNullOrWhiteSpace($script:dnsSuffix)
$script:integrationSetupError = $null
$script:createdUser = $false
$script:readinessStatus = [pscustomobject]@{
    ReadyForUserWrite = $false
    BlockingReason    = 'IntegrationNotInitialized'
}

if ($script:canRun) {
    try {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../DrunkenAD/DrunkenAD.psd1'
        Import-Module $modulePath -Force -ErrorAction Stop
        Import-Module ActiveDirectory -ErrorAction Stop
        $script:readinessStatus = Test-ADDrinkAttributeReadyForUserWrite -Server $script:domainController -PassThru
    }
    catch {
        $script:integrationSetupError = $_.Exception.Message
    }
}

Describe 'DrunkenAD integration tests' -Tag 'Integration' -Skip:(-not $script:canRun) {
    BeforeAll {
        if (-not (Get-Variable -Name integrationSetupError -Scope Script -ErrorAction SilentlyContinue)) {
            $script:integrationSetupError = $null
        }

        if (-not (Get-Variable -Name createdUser -Scope Script -ErrorAction SilentlyContinue)) {
            $script:createdUser = $false
        }

        $script:domainController = $env:DRUNKENAD_TEST_DC
        $script:dnsSuffix = $env:DRUNKENAD_TEST_DNS_SUFFIX
        $script:testUserOu = $env:DRUNKENAD_TEST_USER_OU

        if ([string]::IsNullOrWhiteSpace($script:domainController) -or [string]::IsNullOrWhiteSpace($script:dnsSuffix)) {
            throw 'The integration environment variables were not available during test execution.'
        }

        if (-not [string]::IsNullOrWhiteSpace($script:integrationSetupError)) {
            throw $script:integrationSetupError
        }

        $script:readinessStatus = Test-ADDrinkAttributeReadyForUserWrite -Server $script:domainController -PassThru

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

            New-ADUser @newUserParams
            $script:createdUser = $true
        }
    }

    AfterAll {
        if (-not (Get-Variable -Name createdUser -Scope Script -ErrorAction SilentlyContinue)) {
            $script:createdUser = $false
        }

        if ($script:createdUser) {
            Remove-ADUser -Identity $script:userName -Server $script:domainController -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    It 'reports readiness or a blocking reason for user writes' {
        if (-not [string]::IsNullOrWhiteSpace($script:integrationSetupError)) {
            throw $script:integrationSetupError
        }

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
        $flagValues | Should -Be @('Flags-Enabled', 'Flags-Audited')
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
}
