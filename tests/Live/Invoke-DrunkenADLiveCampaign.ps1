[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$VmName = 'WindowsServer2025_ADDNS',

    [string]$VmWrapperPath = $null,

    [string]$RepoShareName = 'DrunkenAD_CODEX',

    [string]$SnapshotName = ('drunkenad-live-seed-baseline-{0}' -f (Get-Date -Format 'yyyy-MM-dd-HHmmss')),

    [string]$ResultsRoot = (Join-Path -Path $PSScriptRoot -ChildPath 'results'),

    [ValidateSet('Quick', 'Standard', 'Full')]
    [string]$CampaignProfile = 'Full'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-PowerShellSingleQuotedLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    "'{0}'" -f $Value.Replace("'", "''")
}

function Test-DrunkenADPathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $trimCharacters = [char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd($trimCharacters)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd($trimCharacters)
    $rootPrefix = '{0}{1}' -f $fullRoot, [System.IO.Path]::DirectorySeparatorChar

    $fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-Prlctl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & prlctl @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ('prlctl {0} failed: {1}' -f ($Arguments -join ' '), ($output | Out-String).Trim())
    }

    $output
}

function Get-VmInfoText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName
    )

    Invoke-Prlctl -Arguments @('list', '-i', $VmName) | Out-String
}

function Ensure-RepoSharedFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,

        [Parameter(Mandatory = $true)]
        [string]$RepoRootPath,

        [Parameter(Mandatory = $true)]
        [string]$ShareName
    )

    $vmInfoText = Get-VmInfoText -VmName $VmName
    if ($vmInfoText -match ('(?m)^\s+{0} \(\+\) path=' -f [regex]::Escape($ShareName))) {
        Invoke-Prlctl -Arguments @('set', $VmName, '--shf-host', 'on', '--shf-host-automount', 'on', '--shf-host-set', $ShareName, '--path', $RepoRootPath, '--mode', 'rw', '--enable') | Out-Null
        return 'Updated'
    }

    Invoke-Prlctl -Arguments @('set', $VmName, '--shf-host', 'on', '--shf-host-automount', 'on', '--shf-host-add', $ShareName, '--path', $RepoRootPath, '--mode', 'rw') | Out-Null
    'Created'
}

function New-VmSnapshotRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,

        [Parameter(Mandatory = $true)]
        [string]$SnapshotName
    )

    Invoke-Prlctl -Arguments @('snapshot', $VmName, '--name', $SnapshotName, '--description', 'DrunkenAD live campaign baseline') | Out-Null
    $snapshotJson = Invoke-Prlctl -Arguments @('snapshot-list', $VmName, '--json') | Out-String | ConvertFrom-Json -ErrorAction Stop
    foreach ($property in $snapshotJson.PSObject.Properties) {
        if ($property.Value.name -eq $SnapshotName) {
            return [pscustomobject]@{
                Name = $SnapshotName
                Id   = $property.Name
                Date = $property.Value.date
            }
        }
    }

    throw "Snapshot '$SnapshotName' was created but could not be resolved in snapshot metadata."
}

function New-CrossProjectExcerpt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$SnapshotRecord,

        [Parameter(Mandatory = $true)]
        [pscustomobject]$Profile,

        [Parameter(Mandatory = $true)]
        [int]$SeedCount
    )

    (
        "We're starting a DrunkenAD live-validation campaign on `WindowsServer2025_ADDNS` against `lab.contoso.com`. " +
        'The work includes the `{0}` campaign profile, a new pre-mutation snapshot named "{1}" ({2}), a repo share named `DrunkenAD_CODEX`, ' +
        'a persistent synthetic seed population of {3} users under `OU=DrunkenAD Seed,DC=lab,DC=contoso,DC=com`, ' +
        'and live validation of CRUD, projection, and CSV ingestion paths. Please avoid mutating that OU tree or the ' +
        '`Profile-`, `Flags-`, `Routing-`, `Tenant-`, `Sync-`, `Identity-`, `Meta-`, `Notify-`, `Org-`, `Keep-`, `Scenario-`, ' +
        'and `Literal[01]-` namespaces while this campaign is in progress.'
    ) -f $Profile.Name, $SnapshotRecord.Name, $SnapshotRecord.Id, $SeedCount
}

function Resolve-DrunkenADVmWrapperPath {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$ExplicitPath,

        [Parameter(Mandatory = $true)]
        [string]$RepoRootPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $resolvedExplicitPath = [System.IO.Path]::GetFullPath($ExplicitPath)
        if (Test-Path -LiteralPath $resolvedExplicitPath -PathType Leaf) {
            return $resolvedExplicitPath
        }

        throw "The VM wrapper path supplied with -VmWrapperPath was not found: $resolvedExplicitPath"
    }

    if (-not [string]::IsNullOrWhiteSpace($env:DRUNKENAD_VM_WRAPPER_PATH)) {
        $resolvedEnvironmentPath = [System.IO.Path]::GetFullPath($env:DRUNKENAD_VM_WRAPPER_PATH)
        if (Test-Path -LiteralPath $resolvedEnvironmentPath -PathType Leaf) {
            return $resolvedEnvironmentPath
        }

        throw "DRUNKENAD_VM_WRAPPER_PATH points to a file that was not found: $resolvedEnvironmentPath"
    }

    $relativeCandidates = @(
        'VM/Invoke-WindowsAddnsGuestPowerShell.ps1'
        '../VM/Invoke-WindowsAddnsGuestPowerShell.ps1'
        '../Codex/VM/Invoke-WindowsAddnsGuestPowerShell.ps1'
    )

    foreach ($relativeCandidate in $relativeCandidates) {
        $candidatePath = [System.IO.Path]::GetFullPath((Join-Path -Path $RepoRootPath -ChildPath $relativeCandidate))
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            return $candidatePath
        }
    }

    $candidateList = ($relativeCandidates | ForEach-Object {
        [System.IO.Path]::GetFullPath((Join-Path -Path $RepoRootPath -ChildPath $_))
    }) -join ', '

    throw "Unable to locate Invoke-WindowsAddnsGuestPowerShell.ps1. Pass -VmWrapperPath, set DRUNKENAD_VM_WRAPPER_PATH, or place the wrapper at one of: $candidateList"
}

function Get-DrunkenADLiveCampaignProfile {
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
                CrudSamplePerRegion = 3
            }
        }
        'Standard' {
            [pscustomobject]@{
                Name                = 'Standard'
                SeedCount           = 300
                CrudSamplePerRegion = 10
            }
        }
        'Full' {
            [pscustomobject]@{
                Name                = 'Full'
                SeedCount           = 3000
                CrudSamplePerRegion = 100
            }
        }
    }
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..\..'))
$allowedResultsRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath 'results'))
$resolvedResultsRoot = [System.IO.Path]::GetFullPath($ResultsRoot)
if (-not (Test-DrunkenADPathWithinRoot -Path $resolvedResultsRoot -Root $allowedResultsRoot)) {
    throw "ResultsRoot must resolve within the ignored live-results directory '$allowedResultsRoot'."
}

$resolvedVmWrapperPath = Resolve-DrunkenADVmWrapperPath -ExplicitPath $VmWrapperPath -RepoRootPath $repoRoot
$runName = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$runRoot = Join-Path -Path $resolvedResultsRoot -ChildPath $runName
$runDataDirectory = Join-Path -Path $runRoot -ChildPath 'inputs'
$guestRepoRoot = '\\psf\{0}' -f $RepoShareName
$repoRootPrefix = '{0}{1}' -f $repoRoot.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)), [System.IO.Path]::DirectorySeparatorChar
$resultsRelativePath = $resolvedResultsRoot.Substring($repoRootPrefix.Length)
$resultsRelativePath = $resultsRelativePath.Replace([char]'/', [char]'\')
$guestResultsRoot = '{0}\{1}\{2}' -f $guestRepoRoot, $resultsRelativePath, $runName
$guestDataDirectory = '{0}\inputs' -f $guestResultsRoot
$guestScriptPath = '{0}\tests\Live\Invoke-DrunkenADGuestCampaign.ps1' -f $guestRepoRoot
$profile = Get-DrunkenADLiveCampaignProfile -Name $CampaignProfile
$effectiveSeedCount = $profile.SeedCount

$campaignAction = "Create rollback snapshot '$SnapshotName' and run the $CampaignProfile campaign with $effectiveSeedCount synthetic users"
if (-not $PSCmdlet.ShouldProcess($VmName, $campaignAction)) {
    return [pscustomobject]@{
        Status               = 'Preview'
        VmName               = $VmName
        SnapshotName         = $SnapshotName
        CampaignProfile      = $CampaignProfile
        SeedCount            = $effectiveSeedCount
        ResultsDirectoryPath = $runRoot
    }
}

if (Test-Path -LiteralPath $runRoot) {
    throw "The unique run directory already exists: $runRoot"
}
New-Item -Path $runRoot -ItemType Directory -Force | Out-Null

$seedData = & (Join-Path -Path $PSScriptRoot -ChildPath 'Export-DrunkenADSeedData.ps1') -SeedCount $effectiveSeedCount -OutputDirectory $runDataDirectory
$sourceConfigPath = Join-Path -Path $repoRoot -ChildPath 'examples/data/drink-ingestion-config.json'
$runConfigPath = Join-Path -Path $runDataDirectory -ChildPath 'drink-ingestion-config.json'
Copy-Item -LiteralPath $sourceConfigPath -Destination $runConfigPath -ErrorAction Stop

$manifestHash = (Get-FileHash -LiteralPath $seedData.ManifestPath -Algorithm SHA256 -ErrorAction Stop).Hash
$csvHash = (Get-FileHash -LiteralPath $seedData.CsvPath -Algorithm SHA256 -ErrorAction Stop).Hash
$configHash = (Get-FileHash -LiteralPath $runConfigPath -Algorithm SHA256 -ErrorAction Stop).Hash
$snapshotRecord = New-VmSnapshotRecord -VmName $VmName -SnapshotName $SnapshotName
$shareStatus = Ensure-RepoSharedFolder -VmName $VmName -RepoRootPath $repoRoot -ShareName $RepoShareName

$crossProjectExcerpt = New-CrossProjectExcerpt -SnapshotRecord $snapshotRecord -Profile $profile -SeedCount $effectiveSeedCount
$crossProjectExcerptPath = Join-Path -Path $runRoot -ChildPath 'cross-project-excerpt.txt'
$crossProjectExcerpt | Set-Content -LiteralPath $crossProjectExcerptPath -Encoding utf8

$operatorNotesPath = Join-Path -Path $runRoot -ChildPath 'operator-notes.md'
@(
    '# DrunkenAD Live Campaign Operator Notes'
    ''
    ('- VM: `{0}`' -f $VmName)
    ('- Snapshot: `{0}` (`{1}`)' -f $snapshotRecord.Name, $snapshotRecord.Id)
    ('- Campaign Profile: `{0}`' -f $CampaignProfile)
    ('- Seed Count: `{0}`' -f $effectiveSeedCount)
    ('- Shared Folder: `{0}` (`{1}`)' -f $RepoShareName, $shareStatus)
    ('- VM Wrapper: `{0}`' -f $resolvedVmWrapperPath)
    ('- Manifest: `{0}` (SHA-256 `{1}`)' -f $seedData.ManifestPath, $manifestHash)
    ('- CSV: `{0}` (SHA-256 `{1}`)' -f $seedData.CsvPath, $csvHash)
    ('- Config: `{0}` (SHA-256 `{1}`)' -f $runConfigPath, $configHash)
    ('- Results Directory: `{0}`' -f $runRoot)
) -join [Environment]::NewLine | Set-Content -LiteralPath $operatorNotesPath -Encoding utf8

$guestManifestPath = '{0}\seed-manifest.json' -f $guestDataDirectory
$guestCsvPath = '{0}\seed-ingestion.csv' -f $guestDataDirectory
$guestConfigPath = '{0}\drink-ingestion-config.json' -f $guestDataDirectory
$guestLauncherPath = Join-Path -Path $runRoot -ChildPath 'Invoke-GuestCampaign.ps1'
$guestLauncherArguments = @(
    '&'
    (ConvertTo-PowerShellSingleQuotedLiteral -Value $guestScriptPath)
    '-RepoRootPath'
    (ConvertTo-PowerShellSingleQuotedLiteral -Value $guestRepoRoot)
    '-ManifestPath'
    (ConvertTo-PowerShellSingleQuotedLiteral -Value $guestManifestPath)
    '-CsvPath'
    (ConvertTo-PowerShellSingleQuotedLiteral -Value $guestCsvPath)
    '-ConfigPath'
    (ConvertTo-PowerShellSingleQuotedLiteral -Value $guestConfigPath)
    '-ResultsDirectoryPath'
    (ConvertTo-PowerShellSingleQuotedLiteral -Value $guestResultsRoot)
    '-SnapshotName'
    (ConvertTo-PowerShellSingleQuotedLiteral -Value $snapshotRecord.Name)
    '-SnapshotId'
    (ConvertTo-PowerShellSingleQuotedLiteral -Value $snapshotRecord.Id)
    '-CampaignProfile'
    (ConvertTo-PowerShellSingleQuotedLiteral -Value $CampaignProfile)
    '-CrudSamplePerRegion'
    [string]$profile.CrudSamplePerRegion
    '-Confirm:$false'
)
($guestLauncherArguments -join ' ') | Set-Content -LiteralPath $guestLauncherPath -Encoding utf8

$guestOutput = & pwsh -NoLogo -NoProfile -File $resolvedVmWrapperPath -FilePath $guestLauncherPath 2>&1 | Out-String
$guestExitCode = $LASTEXITCODE
$guestOutputPath = Join-Path -Path $runRoot -ChildPath 'guest-output.txt'
$guestOutput | Set-Content -LiteralPath $guestOutputPath -Encoding utf8

$summaryPath = Join-Path -Path $runRoot -ChildPath 'campaign-summary.json'
if (Test-Path -LiteralPath $summaryPath) {
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json -ErrorAction Stop
    if ($guestExitCode -ne 0 -or $summary.Status -ne 'Passed') {
        throw ('Guest campaign failed with status {0} (exit code {1}). Summary: {2}. Output: {3}.' -f $summary.Status, $guestExitCode, $summaryPath, $guestOutputPath)
    }

    Write-Host ('Live campaign completed. Snapshot {0} ({1}); seed users {2}; CSV {3}; projection {4}; CRUD {5}.' -f $summary.Snapshot.Name, $summary.Snapshot.Id, $summary.Seed.TotalUsers, $summary.CsvIngestion.Processed, $summary.Projection.Processed, $summary.Crud.Processed)
}
else {
    throw ('Guest campaign finished with exit code {0}, but no summary JSON was found. Check {1}.' -f $guestExitCode, $guestOutputPath)
}

[pscustomobject]@{
    Status                  = 'Passed'
    SnapshotName            = $snapshotRecord.Name
    SnapshotId              = $snapshotRecord.Id
    RepoShareName           = $RepoShareName
    SeedManifestPath        = $seedData.ManifestPath
    SeedManifestSha256      = $manifestHash
    SeedCsvPath             = $seedData.CsvPath
    SeedCsvSha256           = $csvHash
    IngestionConfigPath     = $runConfigPath
    IngestionConfigSha256   = $configHash
    ResultsDirectoryPath    = $runRoot
    CrossProjectExcerptPath = $crossProjectExcerptPath
}
