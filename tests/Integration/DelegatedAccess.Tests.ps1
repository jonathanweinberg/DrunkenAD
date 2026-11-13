param(
    [switch]$RunDelegatedAccess,
    [string]$DomainController,
    [guid]$FixtureGuid,
    [guid]$ParentOuGuid,
    [pscredential]$Credential,
    [ValidateSet('Writer', 'Reader')]
    [string]$Role
)

Describe 'Pre-provisioned single-OU delegated access' -Tag 'Integration' -Skip:(-not $RunDelegatedAccess) {
    BeforeAll {
        if (-not $RunDelegatedAccess -or -not $Credential -or -not $Role -or
            $FixtureGuid -eq [guid]::Empty -or $ParentOuGuid -eq [guid]::Empty -or
            [string]::IsNullOrWhiteSpace($DomainController)) {
            throw 'Explicit opt-in, role, credentials, writable DC hostname and both fixture GUIDs are required.'
        }
        Import-Module ActiveDirectory -ErrorAction Stop
        Import-Module (Join-Path $PSScriptRoot '../../DrunkenAD/DrunkenAD.psd1') -Force -ErrorAction Stop
        $script:connection = @{ Server = $DomainController; Credential = $Credential; ErrorAction = 'Stop' }
        $dc = ActiveDirectory\Get-ADDomainController -Identity $DomainController @connection
        if ($dc.IsReadOnly -ne $false -or $dc.HostName -ine $DomainController) {
            throw 'Use the actual hostname of one writable controller.'
        }
        $ou = ActiveDirectory\Get-ADOrganizationalUnit -Identity $ParentOuGuid @connection
        function Get-BoundedFixture {
            $target = $FixtureGuid
            $users = @(ActiveDirectory\Get-ADUser -SearchBase $ou.DistinguishedName -SearchScope OneLevel -Filter { ObjectGUID -eq $target } -Properties drink,Description @connection)
            if ($users.Count -ne 1 -or $users[0].ObjectGUID -ne $target -or
                $users[0].Enabled -ne $false -or $users[0].Description -cne 'DrunkenAD: delegated access test fixture') {
                throw 'Fixture identity, immediate parent, disabled state or owner marker did not match.'
            }
            return $users[0]
        }
    }

    It 'reads the fixture and enforces the selected property-write role' {
        $fixture = Get-BoundedFixture
        $result = @(Get-ADUserDrinkData -SamAccountName $fixture.SamAccountName -DomainController $DomainController -Credential $Credential -ErrorAction Stop)
        $baseline = @($fixture.drink | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -CaseSensitive)
        @(Compare-Object -ReferenceObject $baseline -DifferenceObject @($result | Sort-Object -CaseSensitive) -CaseSensitive).Count | Should -Be 0
        $marker = 'DelegationTest-' + [guid]::NewGuid().ToString('N')
        try {
            $permitted = $false
            try {
                $null = Get-BoundedFixture
                ActiveDirectory\Set-ADUser -Identity $FixtureGuid -Add @{ drink = $marker } @connection
                $permitted = $true
            } catch {
                if ($Role -ne 'Reader' -or
                    ($_.Exception -isnot [UnauthorizedAccessException] -and $_.Exception.ErrorCode -ne 8344)) { throw }
            }
            $permitted | Should -Be ($Role -eq 'Writer')
            (@((Get-BoundedFixture).drink) -ccontains $marker) | Should -Be $permitted
        } finally {
            if (@((Get-BoundedFixture).drink) -ccontains $marker) {
                ActiveDirectory\Set-ADUser -Identity $FixtureGuid -Remove @{ drink = $marker } @connection
            }
            $after = @((Get-BoundedFixture).drink | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -CaseSensitive)
            @(Compare-Object -ReferenceObject $baseline -DifferenceObject $after -CaseSensitive).Count | Should -Be 0
        }
    }
}
