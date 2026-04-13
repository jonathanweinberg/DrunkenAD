[CmdletBinding()]
param(
    [int]$SeedCount = 3000,

    [string]$DomainSuffix = 'lab.contoso.com',

    [string]$OutputDirectory = (Join-Path -Path $PSScriptRoot -ChildPath 'Data'),

    [string]$ManifestPath = (Join-Path -Path $OutputDirectory -ChildPath 'seed-manifest.json'),

    [string]$CsvPath = (Join-Path -Path $OutputDirectory -ChildPath 'seed-ingestion.csv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-SeedToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    (($Value -replace '[^A-Za-z0-9]', '')).ToLowerInvariant()
}

if ($SeedCount -ne 3000) {
    throw 'This live harness standardizes on exactly 3,000 seed users.'
}

$regionProfiles = @(
    [pscustomobject]@{
        Region            = 'NA'
        Token             = 'na'
        Country           = 'United States'
        CountryCode       = 'US'
        StateOrProvince   = 'Washington'
        City              = 'Seattle'
        Office            = 'SEA-HQ'
        Company           = 'Contoso North America'
        PagerPrefix       = '1206'
        FirstNames        = @('Alice','Brandon','Casey','Derek','Elena','Felix','Grace','Hannah','Isaac','Julia','Kevin','Lena','Marcus','Nina','Owen','Paige','Quentin','Riley','Sofia','Trevor','Uma','Victor','Willow','Xavier','Yara')
        LastNames         = @('Bennett','Cho','Morgan','Davis','Foster','Gray','Hayes','Iverson','Jenkins','Keller','Lawson','Miller','Nash','Owens','Parker','Quinn','Reed','Sullivan','Turner','Underwood','Vasquez','Walker','Xu','Young','Zimmerman','Anderson','Brooks','Carter','Diaz','Ellis','Franklin','Garcia','Howard','Ingram','Johnson','King','Lopez','Mitchell','Nelson','Ortiz')
        Departments       = @('Identity Engineering','Platform Operations','Security Engineering','Messaging Services','HR Systems','Cloud Enablement')
        Titles            = @('Systems Engineer','Platform Analyst','Security Specialist','Operations Lead','Application Manager','Directory Services Engineer')
        Tiers             = @('Gold','Silver','Platinum','Standard')
        SyncStates        = @('Ready','Pending','Synced','Staged')
        FlagSets          = @('Enabled;Audited','Enabled;RemoteEligible','Privileged;Audited','Enabled;Pilot','Audited;SyncReady')
    }
    [pscustomobject]@{
        Region            = 'EMEA'
        Token             = 'emea'
        Country           = 'Ireland'
        CountryCode       = 'IE'
        StateOrProvince   = 'Leinster'
        City              = 'Dublin'
        Office            = 'DUB-01'
        Company           = 'Contoso EMEA'
        PagerPrefix       = '1353'
        FirstNames        = @('Aisling','Benoit','Clara','Dominik','Eva','Farah','Gregor','Helena','Idris','Johanna','Kamil','Lucia','Marek','Nadia','Oliver','Petra','Rafal','Selma','Tomas','Ursula','Viktor','Wiktoria','Yvonne','Zane','Amelia')
        LastNames         = @('Adler','Bauer','Costa','Dubois','Eriksen','Fischer','Gruber','Hansen','Ivanov','Jensen','Kovac','Larsen','Meyer','Novak','Olsen','Petrov','Quist','Rossi','Schmidt','Taylor','Ulrich','Varga','Weber','Xenos','Yilmaz','Zoric','Bianchi','Carlsen','Dahl','Estevez','Fournier','Gonzalez','Horvat','Iliev','Keller','Lindberg','Moreau','Nieminen','Popescu','Ribeiro')
        Departments       = @('Identity Engineering','Finance Systems','Regional IT','Security Operations','Workplace Technology','Customer Platforms')
        Titles            = @('Regional Systems Engineer','Identity Analyst','Security Operations Engineer','Service Delivery Lead','Collaboration Engineer','Enterprise Applications Analyst')
        Tiers             = @('Gold','Silver','Platinum','Standard')
        SyncStates        = @('Ready','Pending','Synced','Staged')
        FlagSets          = @('Enabled;Audited','Enabled;RemoteEligible','Privileged;Audited','Enabled;Pilot','Audited;SyncReady')
    }
    [pscustomobject]@{
        Region            = 'APAC'
        Token             = 'apac'
        Country           = 'Singapore'
        CountryCode       = 'SG'
        StateOrProvince   = 'Central Singapore'
        City              = 'Singapore'
        Office            = 'SGP-01'
        Company           = 'Contoso APAC'
        PagerPrefix       = '165'
        FirstNames        = @('Akira','Bao','Chloe','Dev','Emi','Farid','Gia','Haruto','Isha','Jun','Kai','Lina','Min','Noor','Arun','Pia','Qiao','Rohan','Sara','Tariq','Umi','Vihaan','Wen','Xinyi','Yusuf')
        LastNames         = @('Aoki','Bhandari','Chen','Das','Ekaputra','Fujita','Gupta','Hassan','Ibrahim','Jain','Khan','Lim','Mehta','Nakamura','Ong','Patel','Qureshi','Rahman','Sato','Tan','Usman','Varma','Wong','Xu','Yamamoto','Zhang','Bhatt','Chandra','Dutta','Farooq','Goh','Hirano','Iyer','Jalil','Kobayashi','Lee','Mukherjee','Ng','Prasad','Rao')
        Departments       = @('Identity Engineering','Business Systems','Security Operations','Regional IT','Cloud Platforms','Sales Technology')
        Titles            = @('Regional Systems Engineer','Applications Analyst','Security Engineer','Service Desk Lead','Cloud Operations Engineer','Directory Specialist')
        Tiers             = @('Gold','Silver','Platinum','Standard')
        SyncStates        = @('Ready','Pending','Synced','Staged')
        FlagSets          = @('Enabled;Audited','Enabled;RemoteEligible','Privileged;Audited','Enabled;Pilot','Audited;SyncReady')
    }
)

$usersPerRegion = [int]($SeedCount / $regionProfiles.Count)
$manifest = New-Object System.Collections.Generic.List[object]
$csvRows = New-Object System.Collections.Generic.List[object]

foreach ($regionProfile in $regionProfiles) {
    $firstNameCount = $regionProfile.FirstNames.Count
    $lastNameCount = $regionProfile.LastNames.Count

    if (($firstNameCount * $lastNameCount) -lt $usersPerRegion) {
        throw "Region '$($regionProfile.Region)' does not have enough name combinations to generate $usersPerRegion users."
    }

    for ($index = 0; $index -lt $usersPerRegion; $index++) {
        $sequence = $index + 1
        $firstName = $regionProfile.FirstNames[$index % $firstNameCount]
        $lastName = $regionProfile.LastNames[[int][math]::Floor($index / $firstNameCount)]
        $displayName = '{0} {1}' -f $firstName, $lastName
        $sequenceToken = '{0}{1:0000}' -f $regionProfile.Token, $sequence
        $samBase = ConvertTo-SeedToken -Value ('{0}{1}' -f $firstName.Substring(0, 1), $lastName)
        $samAccountName = ('{0}{1}' -f $samBase.Substring(0, [Math]::Min($samBase.Length, 20 - $sequenceToken.Length)), $sequenceToken).ToLowerInvariant()
        $upnLocalPart = ('{0}.{1}.{2}' -f (ConvertTo-SeedToken -Value $firstName), (ConvertTo-SeedToken -Value $lastName), $sequenceToken).ToLowerInvariant()
        $userPrincipalName = '{0}@{1}' -f $upnLocalPart, $DomainSuffix
        $employeeId = switch ($regionProfile.Region) {
            'NA'   { '{0:000000}' -f (100000 + $sequence) }
            'EMEA' { '{0:000000}' -f (200000 + $sequence) }
            'APAC' { '{0:000000}' -f (300000 + $sequence) }
        }
        $department = $regionProfile.Departments[$index % $regionProfile.Departments.Count]
        $title = $regionProfile.Titles[$index % $regionProfile.Titles.Count]
        $profileTier = $regionProfile.Tiers[$index % $regionProfile.Tiers.Count]
        $syncState = $regionProfile.SyncStates[$index % $regionProfile.SyncStates.Count]
        $flags = $regionProfile.FlagSets[$index % $regionProfile.FlagSets.Count]
        $tenantId = 'TEN-{0}-{1:0000}' -f $regionProfile.Region, $sequence
        $pager = '{0}-{1:0000}' -f $regionProfile.PagerPrefix, $sequence
        $description = 'DrunkenAD seed user {0} {1:0000} for live validation' -f $regionProfile.Region, $sequence

        $manifestRow = [pscustomobject]@{
            Region           = $regionProfile.Region
            GivenName        = $firstName
            Surname          = $lastName
            DisplayName      = $displayName
            SamAccountName   = $samAccountName
            UserPrincipalName = $userPrincipalName
            Mail             = $userPrincipalName
            Pager            = $pager
            EmployeeID       = $employeeId
            Department       = $department
            Title            = $title
            Company          = $regionProfile.Company
            Office           = $regionProfile.Office
            City             = $regionProfile.City
            StateOrProvince  = $regionProfile.StateOrProvince
            Country          = $regionProfile.Country
            CountryCode      = $regionProfile.CountryCode
            Description      = $description
            ProfileTier      = $profileTier
            ProfileRegion    = $regionProfile.Region
            Flags            = $flags
            RoutingMailbox   = $userPrincipalName
            TenantId         = $tenantId
            SyncState        = $syncState
        }

        $manifest.Add($manifestRow)
        $csvRows.Add([pscustomobject]@{
            SamAccountName  = $samAccountName
            ProfileTier     = $profileTier
            ProfileRegion   = $regionProfile.Region
            Flags           = $flags
            RoutingMailbox  = $userPrincipalName
            TenantId        = $tenantId
            SyncState       = $syncState
        })
    }
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ManifestPath -Encoding utf8
$csvRows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding utf8

[pscustomobject]@{
    SeedCount    = $manifest.Count
    ManifestPath = $ManifestPath
    CsvPath      = $CsvPath
}
