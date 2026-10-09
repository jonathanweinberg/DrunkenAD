# Test-only, PowerShell 5.1-compatible ownership receipts. Dot-source once per run.
# The caller must prepare an EMPTY private local directory outside the repository.
# This helper neither checks nor changes ACLs and gives no ACL/privacy guarantee.
# Handles are valid only in this process; files are receipts, not a recovery API.
# Only New returns an object. Write and Assert return no output on success and
# throw on failure. Never retry a failed write, remove receipts, or infer absence.
# All directory queries, direct-parent proofs, and operations belong to the caller.
$script:DrunkenADIntegrationJournalBindings = New-Object 'System.Runtime.CompilerServices.ConditionalWeakTable[object,object]'

function Get-DrunkenADJournalDirectory {
    param([string]$Path)

    # Reject relative/provider/UNC paths and dot segments before normalization.
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path) -or
        $Path -match '^[\\/]{2}' -or $Path -match '(^|[\\/])\.{1,2}([\\/]|$)' -or
        $Path -match '[\x00-\x1f]' -or $Path -match '^[A-Za-z]:(?![\\/])' -or
        ([IO.Path]::DirectorySeparatorChar -eq '\' -and $Path -notmatch '^[A-Za-z]:[\\/]')) {
        throw 'Integration journal requires an absolute local directory without dot segments.'
    }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Substring($root.Length).Contains(':')) {
        throw 'Integration journal does not allow provider or alternate-stream paths.'
    }
    $directory = New-Object IO.DirectoryInfo $fullPath
    $current = $directory
    while ($null -ne $current) {
        $attributes = [IO.File]::GetAttributes($current.FullName)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($attributes -band [IO.FileAttributes]::Directory) -eq 0) {
            throw 'Integration journal directory and ancestors must be existing directories without reparse points.'
        }
        $current = $current.Parent
    }
    if ($fullPath.Length -gt $root.Length) {
        $fullPath = $fullPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $fullPath
}

function Assert-DrunkenADJournalOutsideRoot {
    param([string]$Directory, [string]$ForbiddenRoot)

    $prefix = $ForbiddenRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ([string]::Equals($Directory, $ForbiddenRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $Directory.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Integration journal directory must be outside the forbidden root.'
    }
}

function Write-DrunkenADJournalFile {
    param([string]$Path, [string]$Json)

    $stream = $null
    try {
        $encoding = New-Object Text.UTF8Encoding $false, $true
        $bytes = $encoding.GetBytes($Json)
        if ($bytes.Length -gt 16384) { throw 'Journal record exceeds its bound.' }
        $stream = New-Object IO.FileStream $Path, ([IO.FileMode]::CreateNew), ([IO.FileAccess]::Write), ([IO.FileShare]::None), 4096, ([IO.FileOptions]::WriteThrough)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    catch {
        throw 'Integration journal write failed; preserve all files and do not retry.'
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Read-DrunkenADJournalFile {
    param([string]$Path)

    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Directory)) -ne 0) {
        throw 'Integration journal receipts must be regular files without reparse points.'
    }
    $stream = $null
    $reader = $null
    try {
        $stream = New-Object IO.FileStream $Path, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
        if ($stream.Length -eq 0 -or $stream.Length -gt 16384) { throw 'Invalid journal record size.' }
        $encoding = New-Object Text.UTF8Encoding $false, $true
        # Do not detect/strip a BOM: exact bytes written by this helper are required.
        $reader = New-Object IO.StreamReader $stream, $encoding, $false, 4096
        return $reader.ReadToEnd()
    }
    catch {
        throw 'Integration journal receipt is incomplete or unreadable.'
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-DrunkenADJournalBinding {
    param($Journal)

    $binding = $null
    if ($null -eq $Journal -or
        -not $script:DrunkenADIntegrationJournalBindings.TryGetValue($Journal, [ref]$binding)) {
        throw 'Integration journal requires its original in-process handle.'
    }
    if ($binding.Faulted) { throw 'Integration journal had a failed write; no retries are permitted.' }
    $properties = @($Journal.PSObject.Properties)
    if ($properties.Count -ne 2 -or $null -eq $Journal.PSObject.Properties['Directory'] -or
        $null -eq $Journal.PSObject.Properties['Intent'] -or
        @($properties | Where-Object { $_.MemberType -ne 'NoteProperty' }).Count -ne 0 -or
        $Journal.Directory -isnot [string] -or $Journal.Directory -cne $binding.Directory -or
        $null -eq $Journal.Intent) {
        throw 'Integration journal handle was changed.'
    }
    $intentProperties = @($Journal.Intent.PSObject.Properties)
    if ($intentProperties.Count -ne $binding.Intent.Count) { throw 'Integration journal intent was changed.' }
    foreach ($name in $binding.Intent.Keys) {
        $property = $Journal.Intent.PSObject.Properties[$name]
        $expected = $binding.Intent[$name]
        if ($null -eq $property -or $property.MemberType -ne 'NoteProperty' -or
            $null -eq $property.Value -or $property.Value.GetType() -ne $expected.GetType() -or
            $property.Value -cne $expected) {
            throw 'Integration journal intent was changed.'
        }
    }
    $directory = Get-DrunkenADJournalDirectory -Path $binding.Directory
    Assert-DrunkenADJournalOutsideRoot -Directory $directory -ForbiddenRoot $binding.ForbiddenRoot
    $count = 0
    foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($directory)) {
        $count++
        $name = [IO.Path]::GetFileName($path)
        if ($count -gt 5 -or $name -cnotin @($binding.Records.Keys)) {
            throw 'Integration journal contains unexpected or partial state.'
        }
        # Comparing to bounded, originally serialized records also rejects partial
        # JSON, duplicate JSON keys, changed types, and any lost identity binding.
        $json = Read-DrunkenADJournalFile -Path $path
        if (-not [string]::Equals($json, $binding.Records[$name], [StringComparison]::Ordinal)) {
            throw 'Integration journal receipt was changed or is incomplete.'
        }
    }
    if ($count -ne $binding.Records.Count) { throw 'Integration journal is missing an immutable receipt.' }
    return $binding
}

function New-DrunkenADIntegrationJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$ForbiddenRoot,
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$ParentDn,
        [Parameter(Mandatory = $true)][guid]$ParentGuid,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][guid]$RunId,
        [Parameter(Mandatory = $true)][string]$TestSourceSHA256
    )

    if ($ParentGuid -eq [guid]::Empty -or $RunId -eq [guid]::Empty -or
        [string]::IsNullOrWhiteSpace($Server) -or $Server.Length -gt 253 -or $Server -match '[\x00-\x1f\x7f]' -or
        [string]::IsNullOrWhiteSpace($ParentDn) -or $ParentDn.Length -gt 2048 -or $ParentDn -match '[\x00-\x1f\x7f]' -or
        $UserName -cnotmatch '\ADrunkenAD_[0-9a-f]{8}\z' -or $TestSourceSHA256 -notmatch '\A[0-9a-fA-F]{64}\z') {
        throw 'Integration journal intent requires valid bounded identity fields.'
    }
    $directoryPath = Get-DrunkenADJournalDirectory -Path $Directory
    $forbiddenPath = Get-DrunkenADJournalDirectory -Path $ForbiddenRoot
    Assert-DrunkenADJournalOutsideRoot -Directory $directoryPath -ForbiddenRoot $forbiddenPath
    foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries($directoryPath)) {
        throw 'Integration journal directory must be empty; reuse is prohibited.'
    }
    $intent = [ordered]@{
        SchemaVersion = 1
        RunId = $RunId.ToString('D')
        Server = $Server
        ParentDn = $ParentDn
        ParentGuid = $ParentGuid.ToString('D')
        UserName = $UserName
        OwnershipToken = 'DrunkenAD integration ' + $RunId.ToString('N')
        TestSourceSHA256 = $TestSourceSHA256
        Disabled = $true
        CreatedUtc = [DateTime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }
    $json = ConvertTo-Json -InputObject $intent -Depth 3 -Compress
    Write-DrunkenADJournalFile -Path (Join-Path $directoryPath '00-intent.json') -Json $json
    # The public view is a separate object, never the binding's authoritative map.
    $publicIntent = [ordered]@{}
    foreach ($key in $intent.Keys) { $publicIntent[$key] = $intent[$key] }
    $journal = [pscustomobject]@{ Directory = $directoryPath; Intent = [pscustomobject]$publicIntent }
    $binding = [pscustomobject]@{
        Directory = $directoryPath
        ForbiddenRoot = $forbiddenPath
        Intent = $intent
        Records = [ordered]@{ '00-intent.json' = $json }
        State = 'Intent'
        ObjectGuid = $null
        Faulted = $false
    }
    $script:DrunkenADIntegrationJournalBindings.Add($journal, $binding)
    return $journal
}

function Write-DrunkenADIntegrationJournalEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Journal,
        [Parameter(Mandatory = $true)]
        [ValidateSet('CreateIssued', 'Created', 'CreationOutcomeUnknown', 'DeleteIssued', 'AbsenceVerified', 'CleanupUnknown')]
        [string]$State,
        [guid]$ObjectGuid,
        [switch]$OperationErrorObserved
    )

    $binding = Get-DrunkenADJournalBinding -Journal $Journal
    $transitions = @{
        CreateIssued = @{ From = @('Intent'); File = '01-create-issued.json' }
        Created = @{ From = @('CreateIssued'); File = '02-created.json' }
        CreationOutcomeUnknown = @{ From = @('CreateIssued'); File = '02-creation-unknown.json' }
        DeleteIssued = @{ From = @('Created'); File = '03-delete-issued.json' }
        AbsenceVerified = @{ From = @('Created', 'DeleteIssued'); File = '04-absence-verified.json' }
        CleanupUnknown = @{ From = @('Created', 'DeleteIssued'); File = '04-cleanup-unknown.json' }
    }
    # Require canonical spelling as state names and filenames form the protocol.
    $transition = $transitions[$State]
    if ($State -cnotin @('CreateIssued', 'Created', 'CreationOutcomeUnknown', 'DeleteIssued', 'AbsenceVerified', 'CleanupUnknown') -or
        $binding.State -notin $transition.From) {
        throw 'Integration journal transition is illegal, duplicated, or terminal.'
    }
    $hasGuid = $PSBoundParameters.ContainsKey('ObjectGuid')
    if ($hasGuid -and $ObjectGuid -eq [guid]::Empty) { throw 'Integration journal object GUID must be nonempty.' }
    if ($State -eq 'Created') {
        if (-not $hasGuid) { throw 'Created requires the exact returned object GUID.' }
        $eventGuid = $ObjectGuid.ToString('D')
    }
    elseif ($State -in @('CreateIssued', 'CreationOutcomeUnknown')) {
        if ($hasGuid) { throw 'An unconfirmed creation cannot record an owned object GUID.' }
        $eventGuid = $null
    }
    else {
        $eventGuid = $binding.ObjectGuid
        if ($null -eq $eventGuid -or ($hasGuid -and $ObjectGuid.ToString('D') -cne $eventGuid)) {
            throw 'Cleanup requires the durably recorded created object GUID.'
        }
    }
    $record = [ordered]@{
        SchemaVersion = 1
        RunId = $binding.Intent.RunId
        State = $State
        ObjectGuid = $eventGuid
        OperationErrorObserved = [bool]$OperationErrorObserved
        CreatedUtc = [DateTime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }
    $json = ConvertTo-Json -InputObject $record -Depth 3 -Compress
    $binding.Faulted = $true
    Write-DrunkenADJournalFile -Path (Join-Path $binding.Directory $transition.File) -Json $json
    $binding.Records.Add($transition.File, $json)
    $binding.ObjectGuid = $eventGuid
    $binding.State = $State
    $binding.Faulted = $false
}

function Assert-DrunkenADIntegrationOwnedUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Journal,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()]$User,
        [Parameter(Mandatory = $true)][guid]$ExpectedGuid
    )

    $binding = Get-DrunkenADJournalBinding -Journal $Journal
    if ($ExpectedGuid -eq [guid]::Empty -or @($User).Count -ne 1 -or $null -eq $User) {
        throw 'Ownership verification requires exactly one user and a nonempty expected GUID.'
    }
    $singleUser = @($User)[0]
    foreach ($name in @('ObjectGUID', 'Description', 'Enabled', 'ObjectClass')) {
        if ($null -eq $singleUser.PSObject.Properties[$name] -or $null -eq $singleUser.PSObject.Properties[$name].Value) {
            throw 'Ownership verification requires complete, unambiguous user metadata.'
        }
    }
    $guidValue = $singleUser.ObjectGUID
    $parsedGuid = [guid]::Empty
    if (($guidValue -isnot [guid] -and $guidValue -isnot [string]) -or
        -not [guid]::TryParse([string]$guidValue, [ref]$parsedGuid) -or $parsedGuid -ne $ExpectedGuid -or
        ($null -ne $binding.ObjectGuid -and $ExpectedGuid.ToString('D') -cne $binding.ObjectGuid) -or
        $singleUser.Description -isnot [string] -or $singleUser.Description -cne $binding.Intent.OwnershipToken -or
        $singleUser.Enabled -isnot [bool] -or $singleUser.Enabled -ne $false -or
        $singleUser.ObjectClass -isnot [string] -or $singleUser.ObjectClass -cne 'user') {
        throw 'User ownership metadata does not match the immutable integration intent.'
    }
}
