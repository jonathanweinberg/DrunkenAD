$runIntegration = $env:DRUNKENAD_RUN_INTEGRATION -eq '1'
$domainController = $env:DRUNKENAD_TEST_DC
$dnsSuffix = $env:DRUNKENAD_TEST_DNS_SUFFIX
$testUserOu = $env:DRUNKENAD_TEST_USER_OU
$canRun = $runIntegration -and -not [string]::IsNullOrWhiteSpace($domainController) -and -not [string]::IsNullOrWhiteSpace($dnsSuffix)

Describe 'DrunkenAD integration tests' -Tag 'Integration' -Skip:(-not $canRun) {
    BeforeAll {
        $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../DrunkenAD/DrunkenAD.psd1'
        Import-Module $modulePath -Force -ErrorAction Stop
        Import-Module ActiveDirectory -ErrorAction Stop

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

        $script:createdUser = $false
        $script:runId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $script:userName = "DrunkenAD_$($script:runId)"
        $script:userPrincipalName = '{0}@{1}' -f $script:userName, $dnsSuffix
        $script:mail = '{0}@{1}' -f $script:userName, $dnsSuffix
        $script:employeeId = [string](Get-Random -Minimum 100000 -Maximum 999999)

        $newUserParams = @{
            Name            = $script:userName
            SamAccountName  = $script:userName
            UserPrincipalName = $script:userPrincipalName
            AccountPassword = (New-IntegrationPassword | ConvertTo-SecureString -AsPlainText -Force)
            Enabled         = $false
            EmployeeID      = $script:employeeId
            OtherAttributes = @{
                mail  = $script:mail
                pager = $script:mail
            }
            Server          = $domainController
            ErrorAction     = 'Stop'
        }

        if (-not [string]::IsNullOrWhiteSpace($testUserOu)) {
            $newUserParams['Path'] = $testUserOu
        }

        New-ADUser @newUserParams
        $script:createdUser = $true
    }

    AfterAll {
        if ($script:createdUser) {
            Remove-ADUser -Identity $script:userName -Server $domainController -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    It 'finds an enabled drink attribute in the target schema' {
        Test-ADDrinkAttributeEnabled -Server $domainController | Should -BeTrue
    }

    It 'writes and reads back a literal namespace value' {
        Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ 'Demo[01]-' = @('First') } -DomainController $domainController -Confirm:$false

        $values = Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Demo[01]-' -DomainController $domainController

        $values | Should -Be @('Demo[01]-First')
    }

    It 'replaces one namespace without disturbing other namespaces' {
        Set-ADUserDrinkData -SamAccountName $script:userName -DataMap @{ 'Keep-' = @('Stable'); 'Demo[01]-' = @('Second') } -DomainController $domainController -Confirm:$false

        $demoValues = Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Demo[01]-' -DomainController $domainController
        $keepValues = Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Keep-' -DomainController $domainController

        $demoValues | Should -Be @('Demo[01]-Second')
        $keepValues | Should -Be @('Keep-Stable')
    }

    It 'removes a namespace without clearing unrelated stored values' {
        Remove-ADUserDrinkData -SamAccountName $script:userName -Prefixes 'Demo[01]-' -DomainController $domainController -Confirm:$false

        $allValues = Get-ADUserDrinkData -SamAccountName $script:userName -DomainController $domainController
        $removedValues = Get-ADUserDrinkData -SamAccountName $script:userName -Prefix 'Demo[01]-' -DomainController $domainController

        $allValues | Should -Be @('Keep-Stable')
        $removedValues | Should -Be @()
    }
}
