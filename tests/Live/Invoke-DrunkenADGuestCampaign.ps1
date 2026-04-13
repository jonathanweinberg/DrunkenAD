[CmdletBinding()]
param(
    [string]$RepoRootPath = '\\psf\DrunkenAD_CODEX',

    [string]$ManifestPath = '\\psf\DrunkenAD_CODEX\tests\Live\Data\seed-manifest.json',

    [string]$CsvPath = '\\psf\DrunkenAD_CODEX\tests\Live\Data\seed-ingestion.csv',

    [string]$ConfigPath = '\\psf\DrunkenAD_CODEX\examples\data\drink-ingestion-config.json',

    [Parameter(Mandatory = $true)]
    [string]$ResultsDirectoryPath,

    [string]$DomainController = $env:COMPUTERNAME,

    [string]$ExpectedDomainDn = 'DC=lab,DC=contoso,DC=com',

    [string]$RootOuName = 'DrunkenAD Seed',

    [int]$CrudSamplePerRegion = 100,

    [int]$ValidationSamplePerRegion = 30,

    [string]$SnapshotName,

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

function Get-OwnedPrefixList {
    [CmdletBinding()]
    param()

    @('Profile-', 'Flags-', 'Routing-', 'Tenant-', 'Sync-', 'Identity-', 'Meta-', 'Notify-', 'Org-', 'Keep-', 'Scenario-', 'Literal[01]-')
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
        $escapedPrefix = [regex]::Escape($prefix)
        $result += @($Values | Where-Object { $_ -match ('^{0}' -f $escapedPrefix) })
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

        [string]$RootOuName = 'DrunkenAD Seed'
    )

    $rootDn = 'OU={0},{1}' -f $RootOuName, $DomainDn

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
    New-ADOrganizationalUnit -Name $name -Path $path -ProtectedFromAccidentalDeletion:$false -Server $DomainController -ErrorAction Stop | Out-Null

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
        [string]$DefaultPassword
    )

    $existingUser = Get-ADUser -LDAPFilter ('(sAMAccountName={0})' -f $SeedUser.SamAccountName) -SearchBase $SearchBaseDn -SearchScope Subtree -Properties mail,pager,employeeID,department,title,company,description,displayName,userPrincipalName,givenName,sn,physicalDeliveryOfficeName,l,st,co,c,distinguishedName,objectGuid -Server $DomainController -ErrorAction SilentlyContinue

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
            AccountPassword   = (ConvertTo-SecureString -String $DefaultPassword -AsPlainText -Force)
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
    if ($existingUser.DistinguishedName -notlike ('*,{0}' -f $TargetOuDn)) {
        Move-ADObject -Identity $identity -TargetPath $TargetOuDn -Server $DomainController -ErrorAction Stop
    }

    if ($existingUser.Name -ne $SeedUser.DisplayName) {
        Rename-ADObject -Identity $identity -NewName $SeedUser.DisplayName -Server $DomainController -ErrorAction Stop
    }

    if (-not (Test-SeedUserRequiresAttributeUpdate -SeedUser $SeedUser -ExistingUser $existingUser)) {
        return [pscustomobject]@{
            Action         = 'Unchanged'
            SamAccountName = $SeedUser.SamAccountName
        }
    }

    Set-ADUser -Identity $identity -Server $DomainController -GivenName $SeedUser.GivenName -Surname $SeedUser.Surname -DisplayName $SeedUser.DisplayName -UserPrincipalName $SeedUser.UserPrincipalName -Department $SeedUser.Department -Title $SeedUser.Title -Company $SeedUser.Company -Description $SeedUser.Description -Replace $replacementAttributes -ErrorAction Stop

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

function Assert-DrinkValuesMatch {
    [CmdletBinding()]
    param(
        [string[]]$Actual,

        [Parameter(Mandatory = $true)]
        [string[]]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $actualNormalized = @($Actual | Sort-Object)
    $expectedNormalized = @($Expected | Sort-Object)
    if ((@($actualNormalized) -join '|') -ne (@($expectedNormalized) -join '|')) {
        throw ('{0} Expected: {1}. Actual: {2}.' -f $Message, ($expectedNormalized -join ', '), ($actualNormalized -join ', '))
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
        New-ADUser @newUserParams
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

        $logLines.Add('Inline smoke validation completed successfully.')
        [pscustomobject]@{
            Runner      = 'InlineSmokeFallback'
            TotalCount  = 4
            FailedCount = 0
            Lines       = @($logLines)
        }
    }
    finally {
        if ($createdUser) {
            Remove-ADUser -Identity $samAccountName -Server $DomainController -Confirm:$false -ErrorAction SilentlyContinue
        }
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
$summary = [ordered]@{
    GeneratedAt          = (Get-Date).ToString('s')
    CompletedAt          = $null
    Status               = 'Running'
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

    if ($seedManifest.Count -ne 3000) {
        throw "Expected the seed manifest to contain 3000 users but found $($seedManifest.Count)."
    }

    if ($csvRows.Count -ne $seedManifest.Count) {
        throw "Expected the CSV row count to match the seed manifest count ($($seedManifest.Count)) but found $($csvRows.Count)."
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
    $defaultPassword = 'DrunkenAD!Seed2026'
    $seedFailures = New-Object System.Collections.Generic.List[object]
    $createdCount = 0
    $updatedCount = 0
    $unchangedCount = 0
    $prunedUsers = New-Object System.Collections.Generic.List[string]
    $expectedSamAccountNames = @{}
    foreach ($seedUser in $seedManifest) {
        $expectedSamAccountNames[$seedUser.SamAccountName] = $true
    }

    $existingManagedUsers = @(Get-ADUser -LDAPFilter '(objectClass=user)' -SearchBase $ouLayout['Root'] -SearchScope Subtree -Properties sAMAccountName,distinguishedName,objectGuid -Server $DomainController -ErrorAction Stop)
    foreach ($existingManagedUser in $existingManagedUsers) {
        if (-not $expectedSamAccountNames.ContainsKey($existingManagedUser.SamAccountName)) {
            Remove-ADObject -Identity $existingManagedUser.ObjectGuid -Confirm:$false -Server $DomainController -ErrorAction Stop
            $prunedUsers.Add($existingManagedUser.SamAccountName)
        }
    }

    foreach ($seedUser in $seedManifest) {
        $targetOuDn = Get-RegionTargetOu -Region $seedUser.Region -OuLayout $ouLayout
        try {
            $seedResult = Set-ManagedSeedUser -SeedUser $seedUser -TargetOuDn $targetOuDn -SearchBaseDn $ExpectedDomainDn -DefaultPassword $defaultPassword
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
        Pruned          = $prunedUsers.Count
        PrunedUsers     = @($prunedUsers.ToArray())
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
        if ($countsByOu[$region] -ne 1000) {
            throw "Seed reconcile expected 1000 users in region '$region' but found $($countsByOu[$region])."
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
        $actualValues = Get-FilteredDrinkValues -Values @($csvResult.FinalDrinkValues) -Prefixes @('Profile-', 'Flags-', 'Routing-', 'Tenant-', 'Sync-')
        $matches = ((@($expectedValues) -join '|') -eq (@($actualValues) -join '|'))

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

        $expectedValues = ConvertTo-ExpectedDrinkValues -DataMap (ConvertTo-ProjectionExpectedDataMap -SeedUser $seedUser)
        $actualValues = Get-FilteredDrinkValues -Values @($projectionResult.FinalDrinkValues) -Prefixes @('Profile-', 'Identity-', 'Meta-', 'Routing-', 'Notify-', 'Org-')
        $matches = ((@($expectedValues) -join '|') -eq (@($actualValues) -join '|'))

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
        $crudUsers += @($seedManifest | Where-Object Region -eq $region | Select-Object -First $CrudSamplePerRegion)
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
