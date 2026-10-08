[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$RepoRootPath = '\\psf\DrunkenAD_CODEX',

    [string]$ManifestPath = '\\psf\DrunkenAD_CODEX\tests\Live\Data\seed-manifest.json',

    [string]$CsvPath = '\\psf\DrunkenAD_CODEX\tests\Live\Data\seed-ingestion.csv',

    [string]$ConfigPath = '\\psf\DrunkenAD_CODEX\examples\data\drink-ingestion-config.json',

    [Parameter(Mandatory = $true)]
    [string]$ResultsDirectoryPath,

    [string]$DomainController = $env:COMPUTERNAME,

    [string]$ExpectedDomainDn = 'DC=lab,DC=contoso,DC=com',

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$')]
    [string]$RootOuName = 'DrunkenAD Seed',

    [ValidateSet('Quick', 'Standard', 'Full')]
    [string]$CampaignProfile = 'Full',

    [int]$CrudSamplePerRegion = 0,

    [int]$ValidationSamplePerRegion = 30,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SnapshotName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SnapshotId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Start-PhaseStopwatch {
    [CmdletBinding()]
    param()

    [System.Diagnostics.Stopwatch]::StartNew()
}

function Stop-PhaseStopwatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Stopwatch]$Stopwatch
    )

    $Stopwatch.Stop()
    [math]::Round($Stopwatch.Elapsed.TotalSeconds, 3)
}

function Get-DrunkenADGuestCampaignProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Quick', 'Standard', 'Full')]
        [string]$Name
    )

    switch ($Name) {
        'Quick' {
            [pscustomobject]@{
                Name                = 'Quick'
                SeedCount           = 30
                UsersPerRegion      = 10
                CrudSamplePerRegion = 3
            }
        }
        'Standard' {
            [pscustomobject]@{
                Name                = 'Standard'
                SeedCount           = 300
                UsersPerRegion      = 100
                CrudSamplePerRegion = 10
            }
        }
        'Full' {
            [pscustomobject]@{
                Name                = 'Full'
                SeedCount           = 3000
                UsersPerRegion      = 1000
                CrudSamplePerRegion = 100
            }
        }
    }
}

function ConvertTo-DrunkenADLdapFilterValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $Value.ToCharArray()) {
        switch ([int][char]$character) {
            0   { [void]$builder.Append('\00') }
            40  { [void]$builder.Append('\28') }
            41  { [void]$builder.Append('\29') }
            42  { [void]$builder.Append('\2a') }
            92  { [void]$builder.Append('\5c') }
            default { [void]$builder.Append($character) }
        }
    }

    $builder.ToString()
}

function Assert-SeedIdentitySetsMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ManifestUsers,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$CsvRows
    )

    $manifestIdentities = @{}
    foreach ($manifestUser in $ManifestUsers) {
        $identity = [string]$manifestUser.SamAccountName
        if ([string]::IsNullOrWhiteSpace($identity)) {
            throw 'The seed manifest contains a blank SamAccountName.'
        }

        $identity = $identity.Trim()
        if ($manifestIdentities.ContainsKey($identity)) {
            throw "The seed manifest contains a duplicate SamAccountName."
        }

        $manifestIdentities[$identity] = $true
    }

    $csvIdentities = @{}
    foreach ($csvRow in $CsvRows) {
        $identity = [string]$csvRow.SamAccountName
        if ([string]::IsNullOrWhiteSpace($identity)) {
            throw 'The seed CSV contains a blank SamAccountName.'
        }

        $identity = $identity.Trim()
        if ($csvIdentities.ContainsKey($identity)) {
            throw "The seed CSV contains a duplicate SamAccountName."
        }

        $csvIdentities[$identity] = $true
    }

    $missingFromCsvCount = @($manifestIdentities.Keys | Where-Object { -not $csvIdentities.ContainsKey($_) }).Count
    $unexpectedInCsvCount = @($csvIdentities.Keys | Where-Object { -not $manifestIdentities.ContainsKey($_) }).Count
    if ($missingFromCsvCount -gt 0 -or $unexpectedInCsvCount -gt 0) {
        throw "Seed manifest and CSV SamAccountName sets differ. Missing from CSV: $missingFromCsvCount; unexpected in CSV: $unexpectedInCsvCount."
    }
}

function Get-OwnedPrefixList {
    [CmdletBinding()]
    param()

    @('CsvProfile-', 'CsvRouting-', 'Profile-', 'Flags-', 'Routing-', 'Tenant-', 'Sync-', 'Identity-', 'Meta-', 'Notify-', 'Org-', 'Keep-', 'Scenario-', 'Literal[01]-')
}

function Get-FilteredDrinkValues {
    [CmdletBinding()]
    param(
        [string[]]$Values,

        [Parameter(Mandatory = $true)]
        [string[]]$Prefixes
    )

    $result = @()
    foreach ($prefix in $Prefixes) {
        $result += @($Values | Where-Object {
            $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
        })
    }

    @($result | Sort-Object -Unique)
}

function ConvertTo-ExpectedDrinkValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$DataMap
    )

    $values = @()
    foreach ($prefix in $DataMap.Keys) {
        foreach ($value in @($DataMap[$prefix])) {
            $values += '{0}{1}' -f $prefix, $value
        }
    }

    @($values | Sort-Object -Unique)
}

function Get-OuLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainDn,

        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$')]
        [string]$RootOuName = 'DrunkenAD Seed'
    )

    $rootDn = 'OU={0},{1}' -f $RootOuName, $DomainDn
    $rootParentDn = ($rootDn -split ',', 2)[1]
    if ($rootParentDn -ne $DomainDn) {
        throw "The campaign root OU must be an immediate child of the verified domain DN."
    }

    [ordered]@{
        Root = $rootDn
        NA   = 'OU=NA,{0}' -f $rootDn
        EMEA = 'OU=EMEA,{0}' -f $rootDn
        APAC = 'OU=APAC,{0}' -f $rootDn
    }
}

function Ensure-OrganizationalUnit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DistinguishedName
    )

    $parentDn = (($DistinguishedName -split ',', 2)[1])
    if ($parentDn -like 'OU=*') {
        Ensure-OrganizationalUnit -DistinguishedName $parentDn | Out-Null
    }

    $existing = $null
    try {
        $existing = Get-ADOrganizationalUnit -Identity $DistinguishedName -Server $DomainController -ErrorAction Stop
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $existing = $null
    }

    if ($existing) {
        return $existing
    }

    $name = ($DistinguishedName -split ',')[0] -replace '^OU=', ''
    $path = (($DistinguishedName -split ',', 2)[1])
    New-ADOrganizationalUnit -Name $name -Path $path -ProtectedFromAccidentalDeletion:$true -Server $DomainController -ErrorAction Stop | Out-Null

    Start-Sleep -Milliseconds 250
    $created = $null
    try {
        $created = Get-ADOrganizationalUnit -Identity $DistinguishedName -Server $DomainController -ErrorAction Stop
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $created = $null
    }

    if (-not $created) {
        throw "Organizational unit '$DistinguishedName' could not be resolved after creation."
    }

    $created
}

function Get-RegionTargetOu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Region,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$OuLayout
    )

    switch ($Region) {
        'NA'   { return $OuLayout['NA'] }
        'EMEA' { return $OuLayout['EMEA'] }
        'APAC' { return $OuLayout['APAC'] }
        default { throw "Unsupported region '$Region'." }
    }
}

function Test-SeedUserRequiresAttributeUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$SeedUser,

        [Parameter(Mandatory = $true)]
        [Microsoft.ActiveDirectory.Management.ADUser]$ExistingUser
    )

    $propertyMap = [ordered]@{
        GivenName                  = $SeedUser.GivenName
        Surname                    = $SeedUser.Surname
        DisplayName                = $SeedUser.DisplayName
        UserPrincipalName          = $SeedUser.UserPrincipalName
        Department                 = $SeedUser.Department
        Title                      = $SeedUser.Title
        Company                    = $SeedUser.Company
        Description                = $SeedUser.Description
        mail                       = $SeedUser.Mail
        pager                      = $SeedUser.Pager
        employeeID                 = $SeedUser.EmployeeID
        physicalDeliveryOfficeName = $SeedUser.Office
        l                          = $SeedUser.City
        st                         = $SeedUser.StateOrProvince
        co                         = $SeedUser.Country
        c                          = $SeedUser.CountryCode
    }

    foreach ($propertyName in $propertyMap.Keys) {
        if ([string]$ExistingUser.$propertyName -ne [string]$propertyMap[$propertyName]) {
            return $true
        }
    }

    $false
}

function Set-ManagedSeedUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$SeedUser,

        [Parameter(Mandatory = $true)]
        [string]$TargetOuDn,

        [Parameter(Mandatory = $true)]
        [string]$SearchBaseDn,

        [Parameter(Mandatory = $true)]
        [securestring]$DefaultPassword
    )

    $escapedSamAccountName = ConvertTo-DrunkenADLdapFilterValue -Value ([string]$SeedUser.SamAccountName)
    $matchingUsers = @(Get-ADUser -LDAPFilter ('(sAMAccountName={0})' -f $escapedSamAccountName) -SearchBase $SearchBaseDn -SearchScope Subtree -Properties mail,pager,employeeID,department,title,company,description,displayName,userPrincipalName,givenName,sn,physicalDeliveryOfficeName,l,st,co,c,distinguishedName,objectGuid -Server $DomainController -ErrorAction Stop)
    if ($matchingUsers.Count -gt 1) {
        throw "Multiple users under the campaign root matched the seed SamAccountName."
    }

    $existingUser = if ($matchingUsers.Count -eq 1) { $matchingUsers[0] } else { $null }

    $replacementAttributes = @{
        mail                       = $SeedUser.Mail
        pager                      = $SeedUser.Pager
        employeeID                 = $SeedUser.EmployeeID
        physicalDeliveryOfficeName = $SeedUser.Office
        l                          = $SeedUser.City
        st                         = $SeedUser.StateOrProvince
        co                         = $SeedUser.Country
        c                          = $SeedUser.CountryCode
    }

    if (-not $existingUser) {
        $newUserParams = @{
            Name              = $SeedUser.DisplayName
            SamAccountName    = $SeedUser.SamAccountName
            UserPrincipalName = $SeedUser.UserPrincipalName
            GivenName         = $SeedUser.GivenName
            Surname           = $SeedUser.Surname
            DisplayName       = $SeedUser.DisplayName
            Department        = $SeedUser.Department
            Title             = $SeedUser.Title
            Company           = $SeedUser.Company
            Description       = $SeedUser.Description
            AccountPassword   = $DefaultPassword
            Enabled           = $false
            Path              = $TargetOuDn
            OtherAttributes   = $replacementAttributes
            Server            = $DomainController
            ErrorAction       = 'Stop'
        }

        New-ADUser @newUserParams | Out-Null

        return [pscustomobject]@{
            Action         = 'Created'
            SamAccountName = $SeedUser.SamAccountName
        }
    }

    $identity = $existingUser.ObjectGuid
    $objectChanged = $false
    if ($existingUser.DistinguishedName -notlike ('*,{0}' -f $TargetOuDn)) {
        Move-ADObject -Identity $identity -TargetPath $TargetOuDn -Server $DomainController -ErrorAction Stop
        $objectChanged = $true
    }

    if ($existingUser.Name -ne $SeedUser.DisplayName) {
        Rename-ADObject -Identity $identity -NewName $SeedUser.DisplayName -Server $DomainController -ErrorAction Stop
        $objectChanged = $true
    }

    $requiresAttributeUpdate = Test-SeedUserRequiresAttributeUpdate -SeedUser $SeedUser -ExistingUser $existingUser
    if (-not $objectChanged -and -not $requiresAttributeUpdate) {
        return [pscustomobject]@{
            Action         = 'Unchanged'
            SamAccountName = $SeedUser.SamAccountName
        }
    }

    if ($requiresAttributeUpdate) {
        Set-ADUser -Identity $identity -Server $DomainController -GivenName $SeedUser.GivenName -Surname $SeedUser.Surname -DisplayName $SeedUser.DisplayName -UserPrincipalName $SeedUser.UserPrincipalName -Department $SeedUser.Department -Title $SeedUser.Title -Company $SeedUser.Company -Description $SeedUser.Description -Replace $replacementAttributes -ErrorAction Stop
    }

    [pscustomobject]@{
        Action         = 'Updated'
        SamAccountName = $SeedUser.SamAccountName
    }
}

function ConvertFrom-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function ConvertTo-UnwrappedArray {
    [CmdletBinding()]
    param(
        $InputObject
    )

    if ($null -eq $InputObject) {
        return @()
    }

    $items = @($InputObject)
    if ($items.Count -eq 1 -and $items[0] -is [System.Array]) {
        return @($items[0])
    }

    $items
}

function ConvertTo-CsvExpectedDataMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$CsvRow,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$ConfigObject
    )

    $dataMap = @{}
    foreach ($property in $ConfigObject.PSObject.Properties) {
        $prefix = $property.Name
        foreach ($entry in @($property.Value)) {
            $columnValue = [string]$CsvRow.($entry.Column)
            if ([string]::IsNullOrWhiteSpace($columnValue)) {
                continue
            }

            $fieldValues = if ($entry.PSObject.Properties.Name -contains 'SplitOn' -and -not [string]::IsNullOrWhiteSpace([string]$entry.SplitOn)) {
                @($columnValue -split [regex]::Escape([string]$entry.SplitOn) | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            }
            else {
                @($columnValue)
            }

            foreach ($fieldValue in $fieldValues) {
                $recordValue = if ($entry.PSObject.Properties.Name -contains 'Label' -and -not [string]::IsNullOrWhiteSpace([string]$entry.Label)) {
                    '{0}={1}' -f $entry.Label, $fieldValue
                }
                else {
                    $fieldValue
                }

                if (-not $dataMap.ContainsKey($prefix)) {
                    $dataMap[$prefix] = @()
                }

                if ($dataMap[$prefix] -notcontains $recordValue) {
                    $dataMap[$prefix] += $recordValue
                }
            }
        }
    }

    $dataMap
}

function ConvertTo-ProjectionExpectedDataMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$SeedUser
    )

    @{
        'Profile-'  = @(
            'samAccountName={0}' -f $SeedUser.SamAccountName
        )
        'Identity-' = @(
            'userPrincipalName={0}' -f $SeedUser.UserPrincipalName
        )
        'Meta-'     = @(
            'employeeID={0}' -f $SeedUser.EmployeeID
        )
        'Routing-'  = @(
            'mail={0}' -f $SeedUser.Mail
        )
        'Notify-'   = @(
            'pager={0}' -f $SeedUser.Pager
        )
        'Org-'      = @(
            'department={0}' -f $SeedUser.Department
            'title={0}' -f $SeedUser.Title
        )
    }
}

function New-SmokeValidationPassword {
    [CmdletBinding()]
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

function Test-DrinkValuesMatch {
    [CmdletBinding()]
    param([string[]]$Actual, [string[]]$Expected)

    [string[]]$actualNormalized = @($Actual)
    [string[]]$expectedNormalized = @($Expected)
    if ($actualNormalized.Count -ne $expectedNormalized.Count) { return $false }
    [Array]::Sort($actualNormalized, [StringComparer]::Ordinal)
    [Array]::Sort($expectedNormalized, [StringComparer]::Ordinal)
    for ($index = 0; $index -lt $actualNormalized.Count; $index++) {
        if (-not [string]::Equals($actualNormalized[$index], $expectedNormalized[$index], [StringComparison]::Ordinal)) {
            return $false
        }
    }
    return $true
}

function Assert-DrinkValuesMatch {
    [CmdletBinding()]
    param(
        [string[]]$Actual,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $actualNormalized = @($Actual | Sort-Object)
    $expectedNormalized = @($Expected | Sort-Object)
    if (-not (Test-DrinkValuesMatch -Actual $Actual -Expected $Expected)) {
        throw ('{0} Expected: {1}. Actual: {2}.' -f $Message, ($expectedNormalized -join ', '), ($actualNormalized -join ', '))
    }
}

function Remove-DrunkenADSmokeAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DistinguishedName,
        [Parameter(Mandatory = $true)]
        [string]$Server
    )

    try {
        Remove-ADUser -Identity $DistinguishedName -Server $Server -Confirm:$false -ErrorAction Stop
        $escapedDn = ConvertTo-DrunkenADLdapFilterValue -Value $DistinguishedName
        $remaining = @(Get-ADUser -LDAPFilter "(distinguishedName=$escapedDn)" -Server $Server -ErrorAction Stop)
        if ($remaining.Count -ne 0) {
            throw 'The isolated smoke account is still present after removal.'
        }
    }
    catch {
        throw ('Smoke account cleanup failed; verify the isolated account manually. {0}' -f $_.Exception.Message)
    }
}

function Invoke-DrunkenADSmokeValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestOuDn,

        [Parameter(Mandatory = $true)]
        [string]$DnsRoot
    )

    $logLines = New-Object System.Collections.Generic.List[string]
    $runToken = [Guid]::NewGuid().ToString('N').Substring(0, 8).ToLowerInvariant()
    $samAccountName = 'drksmk{0}' -f $runToken
    $userPrincipalName = '{0}@{1}' -f $samAccountName, $DnsRoot
    $mail = $userPrincipalName
    $employeeId = 'SMK{0}' -f $runToken.ToUpperInvariant()
    $createdUser = $false

    $newUserParams = @{
        Name              = $samAccountName
        SamAccountName    = $samAccountName
        UserPrincipalName = $userPrincipalName
        AccountPassword   = (New-SmokeValidationPassword | ConvertTo-SecureString -AsPlainText -Force)
        Enabled           = $false
        EmployeeID        = $employeeId
        OtherAttributes   = @{
            mail  = $mail
            pager = $mail
        }
        Path              = $TestOuDn
        Server            = $DomainController
        ErrorAction       = 'Stop'
    }

    try {
        $logLines.Add(('Creating smoke-test user {0} in {1}.' -f $samAccountName, $TestOuDn))
        $smokeUser = New-ADUser @newUserParams -PassThru
        $createdUser = $true

        $logLines.Add('Validating drink write readiness.')
        if (-not (Test-ADDrinkAttributeReadyForUserWrite -Server $DomainController)) {
            throw "The 'drink' attribute is not ready for user writes on $DomainController."
        }

        $logLines.Add('Writing an initial literal namespace value.')
        Set-ADUserDrinkData -SamAccountName $samAccountName -DataMap @{ 'Smoke[01]-' = @('First') } -DomainController $DomainController -Confirm:$false -ErrorAction Stop | Out-Null
        $firstValues = @(Get-ADUserDrinkData -SamAccountName $samAccountName -Prefix 'Smoke[01]-' -DomainController $DomainController)
        Assert-DrinkValuesMatch -Actual $firstValues -Expected @('Smoke[01]-First') -Message 'Initial smoke write did not round-trip correctly.'

        $logLines.Add('Replacing the smoke namespace while preserving Keep-.')
        Set-ADUserDrinkData -SamAccountName $samAccountName -DataMap @{ 'Keep-' = @('Stable'); 'Smoke[01]-' = @('Second') } -DomainController $DomainController -Confirm:$false -ErrorAction Stop | Out-Null
        $secondSmokeValues = @(Get-ADUserDrinkData -SamAccountName $samAccountName -Prefix 'Smoke[01]-' -DomainController $DomainController)
        $keepValues = @(Get-ADUserDrinkData -SamAccountName $samAccountName -Prefix 'Keep-' -DomainController $DomainController)
        Assert-DrinkValuesMatch -Actual $secondSmokeValues -Expected @('Smoke[01]-Second') -Message 'Updated smoke namespace did not match the expected value.'
        Assert-DrinkValuesMatch -Actual $keepValues -Expected @('Keep-Stable') -Message 'Keep namespace was not preserved during the smoke update.'

        $logLines.Add('Removing the smoke namespace and verifying Keep- remains.')
        Remove-ADUserDrinkData -SamAccountName $samAccountName -Prefixes @('Smoke[01]-') -DomainController $DomainController -Confirm:$false -ErrorAction Stop | Out-Null
        $remainingValues = @(Get-ADUserDrinkData -SamAccountName $samAccountName -DomainController $DomainController)
        $removedValues = @(Get-ADUserDrinkData -SamAccountName $samAccountName -Prefix 'Smoke[01]-' -DomainController $DomainController)
        Assert-DrinkValuesMatch -Actual $remainingValues -Expected @('Keep-Stable') -Message 'Smoke remove did not leave the Keep namespace behind.'
        Assert-DrinkValuesMatch -Actual $removedValues -Expected @() -Message 'Smoke namespace was not fully removed.'

    }
    finally {
        if ($createdUser) {
            Remove-DrunkenADSmokeAccount -DistinguishedName $smokeUser.DistinguishedName -Server $DomainController
        }
    }

    $logLines.Add('Inline smoke validation completed successfully; isolated account removal was verified.')
    [pscustomobject]@{
        Runner      = 'InlineSmokeFallback'
        TotalCount  = 4
        FailedCount = 0
        Lines       = @($logLines)
    }
}

function Get-SummarySection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Summary.Contains($Name)) {
        $section = $Summary[$Name]
        if ($section -is [System.Collections.IDictionary]) {
            return $section
        }

        $sectionProperties = if ($null -ne $section) { @($section.PSObject.Properties) } else { @() }
        if ($sectionProperties.Count -gt 0) {
            $sectionMap = @{}
            foreach ($property in $sectionProperties) {
                $sectionMap[$property.Name] = $property.Value
            }

            return $sectionMap
        }
    }

    @{}
}

function ConvertTo-MarkdownSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Summary
    )

    $snapshot = Get-SummarySection -Summary $Summary -Name 'Snapshot'
    $domain = Get-SummarySection -Summary $Summary -Name 'Domain'
    $preflight = Get-SummarySection -Summary $Summary -Name 'Preflight'
    $smoke = Get-SummarySection -Summary $Summary -Name 'Smoke'
    $seed = Get-SummarySection -Summary $Summary -Name 'Seed'
    $csvIngestion = Get-SummarySection -Summary $Summary -Name 'CsvIngestion'
    $projection = Get-SummarySection -Summary $Summary -Name 'Projection'
    $crud = Get-SummarySection -Summary $Summary -Name 'Crud'

    @(
        '# DrunkenAD Live Campaign Summary'
        ''
        ('- Status: `{0}`' -f $Summary['Status'])
        ('- Campaign Profile: `{0}`' -f $Summary['CampaignProfile'])
        ('- Snapshot: `{0}` (`{1}`)' -f $snapshot['Name'], $snapshot['Id'])
        ('- Domain: `{0}`' -f $domain['DistinguishedName'])
        ('- Results Directory: `{0}`' -f $Summary['ResultsDirectoryPath'])
        ('- Seed Users: `{0}`' -f $seed['TotalUsers'])
        ('- Smoke Passed: `{0}`' -f $smoke['Passed'])
        ('- CSV Ingestion Processed: `{0}`' -f $csvIngestion['Processed'])
        ('- Projection Processed: `{0}`' -f $projection['Processed'])
        ('- CRUD Processed: `{0}`' -f $crud['Processed'])
        ''
        '## Phase Durations (seconds)'
        ''
        ('- Preflight: `{0}`' -f $preflight['DurationSeconds'])
        ('- Smoke: `{0}`' -f $smoke['DurationSeconds'])
        ('- Seed: `{0}`' -f $seed['DurationSeconds'])
        ('- CSV Ingestion: `{0}`' -f $csvIngestion['DurationSeconds'])
        ('- Projection: `{0}`' -f $projection['DurationSeconds'])
        ('- CRUD: `{0}`' -f $crud['DurationSeconds'])
    ) + @(
        if (-not [string]::IsNullOrWhiteSpace([string]$Summary['Error'])) {
            ''
            '## Error'
            ''
            ('- `{0}`' -f $Summary['Error'])
        }
    ) -join [Environment]::NewLine
}

function Write-SummaryArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Summary,

        [Parameter(Mandatory = $true)]
        [string]$SummaryJsonPath,

        [Parameter(Mandatory = $true)]
        [string]$SummaryMarkdownPath
    )

    $Summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $SummaryJsonPath -Encoding utf8
    (ConvertTo-MarkdownSummary -Summary $Summary) | Set-Content -LiteralPath $SummaryMarkdownPath -Encoding utf8
}

if (-not (Test-Path -LiteralPath $ResultsDirectoryPath)) {
    New-Item -Path $ResultsDirectoryPath -ItemType Directory -Force | Out-Null
}

$summaryJsonPath = Join-Path -Path $ResultsDirectoryPath -ChildPath 'campaign-summary.json'
$summaryMarkdownPath = Join-Path -Path $ResultsDirectoryPath -ChildPath 'campaign-summary.md'
$profile = Get-DrunkenADGuestCampaignProfile -Name $CampaignProfile
$effectiveCrudSamplePerRegion = if ($PSBoundParameters.ContainsKey('CrudSamplePerRegion') -and $CrudSamplePerRegion -gt 0) {
    $CrudSamplePerRegion
}
else {
    $profile.CrudSamplePerRegion
}
$summary = [ordered]@{
    GeneratedAt          = (Get-Date).ToString('s')
    CompletedAt          = $null
    Status               = 'Running'
    CampaignProfile      = $profile.Name
    ResultsDirectoryPath = $ResultsDirectoryPath
    Snapshot             = @{
        Name = $SnapshotName
        Id   = $SnapshotId
    }
    Error                = $null
}

$exitCode = 0

try {
    $modulePath = Join-Path -Path $RepoRootPath -ChildPath 'DrunkenAD\DrunkenAD.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop

    $domain = Get-ADDomain -Server $DomainController -ErrorAction Stop
    $summary['Domain'] = @{
        DNSRoot           = $domain.DNSRoot
        DistinguishedName = $domain.DistinguishedName
        UsersContainer    = $domain.UsersContainer
    }

    $ouLayout = Get-OuLayout -DomainDn $domain.DistinguishedName -RootOuName $RootOuName
    $configObject = ConvertFrom-JsonFile -Path $ConfigPath
    $seedManifest = ConvertTo-UnwrappedArray -InputObject (ConvertFrom-JsonFile -Path $ManifestPath)
    $csvRows = @(Import-Csv -LiteralPath $CsvPath)
    $csvRowsBySam = @{}
    foreach ($row in $csvRows) {
        $csvRowsBySam[$row.SamAccountName] = $row
    }

    $preflightWatch = Start-PhaseStopwatch
    $shareVisible = Test-Path -LiteralPath $RepoRootPath
    $moduleVisible = Test-Path -LiteralPath $modulePath
    $manifestVisible = Test-Path -LiteralPath $ManifestPath
    $csvVisible = Test-Path -LiteralPath $CsvPath
    $readinessStatus = Test-ADDrinkAttributeReadyForUserWrite -Server $DomainController -PassThru
    $summary['Preflight'] = @{
        ShareVisible           = $shareVisible
        ModuleVisible          = $moduleVisible
        ManifestVisible        = $manifestVisible
        CsvVisible             = $csvVisible
        AttributeEnabled       = $readinessStatus.Enabled
        ReadyForUserWrite      = $readinessStatus.ReadyForUserWrite
        UserClassSupportsDrink = $readinessStatus.AllowedOnUserClass
        BlockingReason         = $readinessStatus.BlockingReason
        BlockingMessage        = $readinessStatus.BlockingMessage
        DrinkAttributeDn       = $readinessStatus.AttributeDistinguishedName
        UserClassDn            = $readinessStatus.UserClassDistinguishedName
        ExpectedDomainDn       = $ExpectedDomainDn
        ActualDomainDn         = $domain.DistinguishedName
        ManifestCount          = $seedManifest.Count
        CsvRowCount            = $csvRows.Count
        DurationSeconds        = Stop-PhaseStopwatch -Stopwatch $preflightWatch
    }
    Write-SummaryArtifacts -Summary $summary -SummaryJsonPath $summaryJsonPath -SummaryMarkdownPath $summaryMarkdownPath

    if (-not $shareVisible -or -not $moduleVisible -or -not $manifestVisible -or -not $csvVisible) {
        throw 'Guest preflight failed because the shared repo artifacts are not visible.'
    }

    if ($domain.DistinguishedName -ne $ExpectedDomainDn) {
        throw "Guest preflight expected domain '$ExpectedDomainDn' but found '$($domain.DistinguishedName)'."
    }

    if (-not $readinessStatus.ReadyForUserWrite) {
        throw $readinessStatus.BlockingMessage
    }

    if ($seedManifest.Count -ne $profile.SeedCount) {
        throw "Expected the seed manifest to contain $($profile.SeedCount) users for the $($profile.Name) campaign profile but found $($seedManifest.Count)."
    }

    if ($csvRows.Count -ne $seedManifest.Count) {
        throw "Expected the CSV row count to match the seed manifest count ($($seedManifest.Count)) but found $($csvRows.Count)."
    }

    Assert-SeedIdentitySetsMatch -ManifestUsers $seedManifest -CsvRows $csvRows

    if (-not $PSCmdlet.ShouldProcess($ouLayout['Root'], "Run the $($profile.Name) DrunkenAD live campaign")) {
        $summary['Status'] = 'Preview'
        return
    }

    if ([string]::IsNullOrWhiteSpace($env:DRUNKENAD_SEED_PASSWORD)) {
        throw 'DRUNKENAD_SEED_PASSWORD must be set in the guest environment before live seed mutation.'
    }

    foreach ($ouDn in @($ouLayout['Root'], $ouLayout['NA'], $ouLayout['EMEA'], $ouLayout['APAC'])) {
        Ensure-OrganizationalUnit -DistinguishedName $ouDn | Out-Null
    }

    $smokeWatch = Start-PhaseStopwatch
    $env:DRUNKENAD_RUN_INTEGRATION = '1'
    $env:DRUNKENAD_TEST_DC = $DomainController
    $env:DRUNKENAD_TEST_DNS_SUFFIX = $domain.DNSRoot
    $env:DRUNKENAD_TEST_USER_OU = $ouLayout['NA']
    $smokeOutputPath = Join-Path -Path $ResultsDirectoryPath -ChildPath 'smoke-output.txt'
    $smokeRunner = 'Unknown'
    $smokeFailedCount = 0
    $smokeTotalCount = 0
    $smokePassed = $false
    $smokeException = $null
    $canUsePester = $false

    try {
        try {
            Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
            $canUsePester = $true
        }
        catch {
            $canUsePester = $false
        }

        if ($canUsePester) {
            $smokeRunner = 'Pester'

            $smokeTranscriptStarted = $false
            $smokeResult = $null
            try {
                Start-Transcript -LiteralPath $smokeOutputPath -Force | Out-Null
                $smokeTranscriptStarted = $true
                $smokeConfiguration = New-PesterConfiguration
                $smokeConfiguration.Run.Path = Join-Path -Path $RepoRootPath -ChildPath 'tests\DrunkenAD.Integration.Tests.ps1'
                $smokeConfiguration.Run.PassThru = $true
                $smokeConfiguration.Output.Verbosity = 'Normal'
                $smokeResult = Invoke-Pester -Configuration $smokeConfiguration
            }
            finally {
                if ($smokeTranscriptStarted) {
                    Stop-Transcript | Out-Null
                }
            }

            $smokeFailedCount = if ($null -ne $smokeResult -and $smokeResult.PSObject.Properties.Name -contains 'FailedCount') { [int]$smokeResult.FailedCount } else { 0 }
            $smokeTotalCount = if ($null -ne $smokeResult -and $smokeResult.PSObject.Properties.Name -contains 'TotalCount') { [int]$smokeResult.TotalCount } else { 0 }
            $smokePassed = ($null -ne $smokeResult) -and ($smokeFailedCount -eq 0)
        }
        else {
            $smokeResult = Invoke-DrunkenADSmokeValidation -TestOuDn $ouLayout['NA'] -DnsRoot $domain.DNSRoot
            $smokeRunner = $smokeResult.Runner
            $smokeFailedCount = [int]$smokeResult.FailedCount
            $smokeTotalCount = [int]$smokeResult.TotalCount
            @($smokeResult.Lines) | Set-Content -LiteralPath $smokeOutputPath -Encoding utf8
            $smokePassed = ($smokeFailedCount -eq 0)
        }
    }
    catch {
        $smokeException = $_.Exception.Message
        $smokeFailedCount = if ($smokeFailedCount -gt 0) { $smokeFailedCount } else { 1 }
        $smokePassed = $false
        @(
            'Smoke validation failed.'
            $smokeException
        ) | Set-Content -LiteralPath $smokeOutputPath -Encoding utf8
    }

    $summary['Smoke'] = @{
        Passed          = $smokePassed
        Runner          = $smokeRunner
        FailedCount     = $smokeFailedCount
        TotalCount      = $smokeTotalCount
        OutputPath      = $smokeOutputPath
        DurationSeconds = Stop-PhaseStopwatch -Stopwatch $smokeWatch
    }
    Write-SummaryArtifacts -Summary $summary -SummaryJsonPath $summaryJsonPath -SummaryMarkdownPath $summaryMarkdownPath

    if (-not $smokePassed) {
        if ([string]::IsNullOrWhiteSpace($smokeException)) {
            throw 'The live smoke validation failed.'
        }

        throw ('The live smoke validation failed: {0}' -f $smokeException)
    }

    $seedWatch = Start-PhaseStopwatch
    $defaultPassword = ConvertTo-SecureString -String $env:DRUNKENAD_SEED_PASSWORD -AsPlainText -Force
    $seedFailures = New-Object System.Collections.Generic.List[object]
    $createdCount = 0
    $updatedCount = 0
    $unchangedCount = 0
    $expectedSamAccountNames = @{}
    foreach ($seedUser in $seedManifest) {
        $expectedSamAccountNames[$seedUser.SamAccountName] = $true
    }

    $existingManagedUsers = @(Get-ADUser -LDAPFilter '(objectClass=user)' -SearchBase $ouLayout['Root'] -SearchScope Subtree -Properties sAMAccountName,distinguishedName,objectGuid -Server $DomainController -ErrorAction Stop)
    $unexpectedManagedUsers = @($existingManagedUsers | Where-Object { -not $expectedSamAccountNames.ContainsKey($_.SamAccountName) })
    if ($unexpectedManagedUsers.Count -gt 0) {
        throw "Unexpected users were found under the campaign root OU. Refusing to prune or reconcile while $($unexpectedManagedUsers.Count) unowned user(s) are present."
    }

    foreach ($seedUser in $seedManifest) {
        $targetOuDn = Get-RegionTargetOu -Region $seedUser.Region -OuLayout $ouLayout
        try {
            $seedResult = Set-ManagedSeedUser -SeedUser $seedUser -TargetOuDn $targetOuDn -SearchBaseDn $ouLayout['Root'] -DefaultPassword $defaultPassword
            if ($seedResult.Action -eq 'Created') {
                $createdCount++
            }
            elseif ($seedResult.Action -eq 'Updated') {
                $updatedCount++
            }
            else {
                $unchangedCount++
            }
        }
        catch {
            $seedFailures.Add([pscustomobject]@{
                SamAccountName = $seedUser.SamAccountName
                Phase          = 'Seed'
                Error          = $_.Exception.Message
            })
        }
    }

    $countsByOu = @{
        NA   = (Get-ADUser -Filter * -SearchBase $ouLayout['NA'] -SearchScope OneLevel -Server $DomainController -ErrorAction Stop | Measure-Object).Count
        EMEA = (Get-ADUser -Filter * -SearchBase $ouLayout['EMEA'] -SearchScope OneLevel -Server $DomainController -ErrorAction Stop | Measure-Object).Count
        APAC = (Get-ADUser -Filter * -SearchBase $ouLayout['APAC'] -SearchScope OneLevel -Server $DomainController -ErrorAction Stop | Measure-Object).Count
    }
    $totalManagedUsers = (Get-ADUser -Filter * -SearchBase $ouLayout['Root'] -SearchScope Subtree -Server $DomainController -ErrorAction Stop | Measure-Object).Count

    $summary['Seed'] = [pscustomobject][ordered]@{
        TotalUsers      = $seedManifest.Count
        Created         = $createdCount
        Updated         = $updatedCount
        Unchanged       = $unchangedCount
        Pruned          = 0
        PrunedUsers     = @()
        FailureCount    = $seedFailures.Count
        CountsByOu      = [pscustomobject]$countsByOu
        TotalManaged    = $totalManagedUsers
        Failures        = @($seedFailures.ToArray())
        DurationSeconds = Stop-PhaseStopwatch -Stopwatch $seedWatch
    }
    Write-SummaryArtifacts -Summary $summary -SummaryJsonPath $summaryJsonPath -SummaryMarkdownPath $summaryMarkdownPath

    if ($seedFailures.Count -gt 0) {
        throw "Seed reconcile failed for $($seedFailures.Count) users."
    }

    foreach ($region in @('NA', 'EMEA', 'APAC')) {
        if ($countsByOu[$region] -ne $profile.UsersPerRegion) {
            throw "Seed reconcile expected $($profile.UsersPerRegion) users in region '$region' for the $($profile.Name) campaign profile but found $($countsByOu[$region])."
        }
    }

    if ($totalManagedUsers -ne $seedManifest.Count) {
        throw "Seed reconcile expected $($seedManifest.Count) managed users but found $totalManagedUsers."
    }

    $csvWatch = Start-PhaseStopwatch
    $csvResults = @()
    $csvFailures = New-Object System.Collections.Generic.List[object]

    try {
        $csvResults = @(Import-ADUserDrinkCsvData -CsvPath $CsvPath -ConfigPath $ConfigPath -DomainController $DomainController -ErrorAction Stop)
    }
    catch {
        $csvFailures.Add([pscustomobject]@{
            Phase = 'CsvIngestion'
            Error = $_.Exception.Message
        })
    }

    $csvResultsBySam = @{}
    foreach ($result in $csvResults) {
        $csvResultsBySam[$result.SamAccountName] = $result
    }

    $csvSamples = @()
    foreach ($region in @('NA', 'EMEA', 'APAC')) {
        $csvSamples += @($seedManifest | Where-Object Region -eq $region | Select-Object -First $ValidationSamplePerRegion)
    }

    $csvSampleValidation = New-Object System.Collections.Generic.List[object]
    foreach ($seedUser in $csvSamples) {
        $csvResult = $csvResultsBySam[$seedUser.SamAccountName]
        if (-not $csvResult) {
            $csvFailures.Add([pscustomobject]@{
                SamAccountName = $seedUser.SamAccountName
                Phase          = 'CsvIngestion'
                Error          = 'No CSV import result was captured for the user.'
            })
            continue
        }

        $expectedValues = ConvertTo-ExpectedDrinkValues -DataMap (ConvertTo-CsvExpectedDataMap -CsvRow $csvRowsBySam[$seedUser.SamAccountName] -ConfigObject $configObject)
        $currentValues = @(Get-ADUserDrinkData -SamAccountName $seedUser.SamAccountName -DomainController $DomainController -ErrorAction Stop)
        $actualValues = Get-FilteredDrinkValues -Values $currentValues -Prefixes @($configObject.PSObject.Properties.Name)
        $matches = Test-DrinkValuesMatch -Actual $actualValues -Expected $expectedValues

        $csvSampleValidation.Add([pscustomobject]@{
            SamAccountName = $seedUser.SamAccountName
            Region         = $seedUser.Region
            ExpectedValues = $expectedValues
            ActualValues   = $actualValues
            Matches        = $matches
        })

        if (-not $matches) {
            $csvFailures.Add([pscustomobject]@{
                SamAccountName = $seedUser.SamAccountName
                Phase          = 'CsvIngestion'
                Error          = 'Sample read-back did not match the expected namespace values.'
            })
        }
    }

    $summary['CsvIngestion'] = [pscustomobject][ordered]@{
        Processed       = $csvResults.Count
        FailureCount    = $csvFailures.Count
        SampleValidated = $csvSampleValidation.Count
        SampleResults   = @($csvSampleValidation.ToArray())
        Failures        = @($csvFailures.ToArray())
        DurationSeconds = Stop-PhaseStopwatch -Stopwatch $csvWatch
    }
    Write-SummaryArtifacts -Summary $summary -SummaryJsonPath $summaryJsonPath -SummaryMarkdownPath $summaryMarkdownPath

    if ($csvResults.Count -ne $seedManifest.Count) {
        throw "CSV ingestion expected $($seedManifest.Count) processed users but found $($csvResults.Count)."
    }

    if ($csvFailures.Count -gt 0) {
        throw "CSV ingestion phase failed with $($csvFailures.Count) issues."
    }

    $projectionWatch = Start-PhaseStopwatch
    $projectionResults = New-Object System.Collections.Generic.List[object]
    $projectionFailures = New-Object System.Collections.Generic.List[object]

    foreach ($seedUser in $seedManifest) {
        try {
            $projectionResults.Add((Set-ADUserDrinkProjection -SamAccountName $seedUser.SamAccountName -AttributeMap @{ 'Org-' = @('department', 'title') } -IncludeDefaultAttributeMap -DomainController $DomainController -Confirm:$false -PassThru -ErrorAction Stop))
        }
        catch {
            $projectionFailures.Add([pscustomobject]@{
                SamAccountName = $seedUser.SamAccountName
                Phase          = 'Projection'
                Error          = $_.Exception.Message
            })
        }
    }

    $projectionResultsBySam = @{}
    foreach ($result in $projectionResults) {
        $projectionResultsBySam[$result.SamAccountName] = $result
    }

    $projectionSampleValidation = New-Object System.Collections.Generic.List[object]
    foreach ($seedUser in $csvSamples) {
        $projectionResult = $projectionResultsBySam[$seedUser.SamAccountName]
        if (-not $projectionResult) {
            $projectionFailures.Add([pscustomobject]@{
                SamAccountName = $seedUser.SamAccountName
                Phase          = 'Projection'
                Error          = 'No projection result was captured for the user.'
            })
            continue
        }

        $projectionMap = ConvertTo-ProjectionExpectedDataMap -SeedUser $seedUser
        $csvMap = ConvertTo-CsvExpectedDataMap -CsvRow $csvRowsBySam[$seedUser.SamAccountName] -ConfigObject $configObject
        $expectedValues = @((ConvertTo-ExpectedDrinkValues -DataMap $projectionMap) + (ConvertTo-ExpectedDrinkValues -DataMap $csvMap) | Sort-Object)
        $currentValues = @(Get-ADUserDrinkData -SamAccountName $seedUser.SamAccountName -DomainController $DomainController -ErrorAction Stop)
        $actualValues = Get-FilteredDrinkValues -Values $currentValues -Prefixes @(@($projectionMap.Keys) + @($csvMap.Keys))
        $matches = Test-DrinkValuesMatch -Actual $actualValues -Expected $expectedValues

        $projectionSampleValidation.Add([pscustomobject]@{
            SamAccountName = $seedUser.SamAccountName
            Region         = $seedUser.Region
            ExpectedValues = $expectedValues
            ActualValues   = $actualValues
            Matches        = $matches
        })

        if (-not $matches) {
            $projectionFailures.Add([pscustomobject]@{
                SamAccountName = $seedUser.SamAccountName
                Phase          = 'Projection'
                Error          = 'Sample projection read-back did not match the expected namespace values.'
            })
        }
    }

    $summary['Projection'] = [pscustomobject][ordered]@{
        Processed       = $projectionResults.Count
        FailureCount    = $projectionFailures.Count
        SampleValidated = $projectionSampleValidation.Count
        SampleResults   = @($projectionSampleValidation.ToArray())
        Failures        = @($projectionFailures.ToArray())
        DurationSeconds = Stop-PhaseStopwatch -Stopwatch $projectionWatch
    }
    Write-SummaryArtifacts -Summary $summary -SummaryJsonPath $summaryJsonPath -SummaryMarkdownPath $summaryMarkdownPath

    if ($projectionResults.Count -ne $seedManifest.Count) {
        throw "Projection expected $($seedManifest.Count) processed users but found $($projectionResults.Count)."
    }

    if ($projectionFailures.Count -gt 0) {
        throw "Projection phase failed with $($projectionFailures.Count) issues."
    }

    $crudWatch = Start-PhaseStopwatch
    $crudFailures = New-Object System.Collections.Generic.List[object]
    $crudProcessed = 0

    $crudUsers = @()
    foreach ($region in @('NA', 'EMEA', 'APAC')) {
        $crudUsers += @($seedManifest | Where-Object Region -eq $region | Select-Object -First $effectiveCrudSamplePerRegion)
    }

    foreach ($seedUser in $crudUsers) {
        try {
            Set-ADUserDrinkData -SamAccountName $seedUser.SamAccountName -DataMap @{ 'Keep-' = @('Stable'); 'Scenario-' = @('Phase=Initial'); 'Literal[01]-' = @('Value=First') } -DomainController $DomainController -Confirm:$false -ErrorAction Stop | Out-Null
            $initialValues = @(Get-ADUserDrinkData -SamAccountName $seedUser.SamAccountName -DomainController $DomainController)
            $initialFiltered = Get-FilteredDrinkValues -Values $initialValues -Prefixes @('Keep-', 'Scenario-', 'Literal[01]-')
            $expectedInitial = @('Keep-Stable', 'Literal[01]-Value=First', 'Scenario-Phase=Initial') | Sort-Object
            if ((@($initialFiltered) -join '|') -ne (@($expectedInitial) -join '|')) {
                throw 'Initial CRUD write did not round-trip as expected.'
            }

            Set-ADUserDrinkData -SamAccountName $seedUser.SamAccountName -DataMap @{ 'Scenario-' = @('Phase=Updated'); 'Literal[01]-' = @('Value=Second') } -DomainController $DomainController -Confirm:$false -ErrorAction Stop | Out-Null
            $updatedValues = @(Get-ADUserDrinkData -SamAccountName $seedUser.SamAccountName -DomainController $DomainController)
            $updatedFiltered = Get-FilteredDrinkValues -Values $updatedValues -Prefixes @('Keep-', 'Scenario-', 'Literal[01]-')
            $expectedUpdated = @('Keep-Stable', 'Literal[01]-Value=Second', 'Scenario-Phase=Updated') | Sort-Object
            if ((@($updatedFiltered) -join '|') -ne (@($expectedUpdated) -join '|')) {
                throw 'CRUD update did not preserve the keep namespace or literal namespace as expected.'
            }

            Remove-ADUserDrinkData -SamAccountName $seedUser.SamAccountName -Prefixes @('Scenario-', 'Literal[01]-') -DomainController $DomainController -Confirm:$false -ErrorAction Stop | Out-Null
            $finalValues = @(Get-ADUserDrinkData -SamAccountName $seedUser.SamAccountName -DomainController $DomainController)
            $finalFiltered = Get-FilteredDrinkValues -Values $finalValues -Prefixes @('Keep-', 'Scenario-', 'Literal[01]-')
            $expectedFinal = @('Keep-Stable')
            if ((@($finalFiltered) -join '|') -ne (@($expectedFinal) -join '|')) {
                throw 'CRUD remove did not leave only the keep namespace behind.'
            }

            $crudProcessed++
        }
        catch {
            $crudFailures.Add([pscustomobject]@{
                SamAccountName = $seedUser.SamAccountName
                Phase          = 'Crud'
                Error          = $_.Exception.Message
            })
        }
    }

    $summary['Crud'] = [pscustomobject][ordered]@{
        Processed       = $crudProcessed
        FailureCount    = $crudFailures.Count
        Failures        = @($crudFailures.ToArray())
        DurationSeconds = Stop-PhaseStopwatch -Stopwatch $crudWatch
    }
    Write-SummaryArtifacts -Summary $summary -SummaryJsonPath $summaryJsonPath -SummaryMarkdownPath $summaryMarkdownPath

    if ($crudProcessed -ne $crudUsers.Count) {
        throw "CRUD expected $($crudUsers.Count) processed users but found $crudProcessed."
    }

    if ($crudFailures.Count -gt 0) {
        throw "CRUD phase failed with $($crudFailures.Count) issues."
    }

    $summary['Status'] = 'Passed'
}
catch {
    $summary['Status'] = 'Failed'
    $summary['Error'] = $_.Exception.Message
    $summary['FailureDetail'] = $_.ToString()
    $summary['FailureExceptionType'] = $_.Exception.GetType().FullName
    $summary['FailureScriptStackTrace'] = $_.ScriptStackTrace
    $summary['FailurePosition'] = $_.InvocationInfo.PositionMessage
    $summary['FailureFullyQualifiedErrorId'] = $_.FullyQualifiedErrorId
    $exitCode = 1
}
finally {
    $summary['CompletedAt'] = (Get-Date).ToString('s')
    Write-SummaryArtifacts -Summary $summary -SummaryJsonPath $summaryJsonPath -SummaryMarkdownPath $summaryMarkdownPath
}

if ($exitCode -ne 0) {
    Write-Error ('Live campaign failed. Summary: {0}' -f $summaryJsonPath)
    exit $exitCode
}

Write-Host ('Live campaign completed successfully. Summary: {0}' -f $summaryJsonPath)
