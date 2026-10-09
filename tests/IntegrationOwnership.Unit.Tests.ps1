BeforeAll {
    $script:ownershipHelperPath = Join-Path $PSScriptRoot 'Support/IntegrationOwnership.ps1'
    . $script:ownershipHelperPath
    $script:repositoryRoot = Split-Path $PSScriptRoot -Parent
    # macOS /var and /tmp are links. Fixtures use the physical local temp root.
    $tempRoot = $TestDrive
    if ([IO.Directory]::Exists('/private/tmp')) { $tempRoot = '/private/tmp' }
    $script:ownershipScratch = Join-Path $tempRoot ('drunkenad-journal-unit-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($script:ownershipScratch)
    $script:forbidden = Join-Path $script:ownershipScratch 'forbidden'
    [void][IO.Directory]::CreateDirectory($script:forbidden)
    $script:fixtureGuid = [guid]'11111111-2222-3333-4444-555555555555'

    function New-TestOwnershipJournal {
        param([hashtable]$Overrides = @{})
        $options = $script:journalArguments.Clone()
        foreach ($key in $Overrides.Keys) { $options[$key] = $Overrides[$key] }
        New-DrunkenADIntegrationJournal @options
    }

    function Initialize-TestCreatedJournal {
        $script:journal = New-TestOwnershipJournal
        Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State CreateIssued
        Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State Created -ObjectGuid $script:fixtureGuid
    }

    function New-TestOwnedUser {
        [pscustomobject]@{
            ObjectGUID = $script:fixtureGuid
            Description = $script:journal.Intent.OwnershipToken
            Enabled = $false
            ObjectClass = 'user'
            Name = 'renamed-synthetic-user'
        }
    }

    function Get-TestReceiptNames {
        @([IO.Directory]::GetFileSystemEntries($script:journalArguments.Directory) | ForEach-Object {
            [IO.Path]::GetFileName($_)
        } | Sort-Object)
    }

    function Set-TestReceipt {
        param([string]$Name, [string]$Text)
        [IO.File]::WriteAllText((Join-Path $script:journalArguments.Directory $Name), $Text, (New-Object Text.UTF8Encoding $false))
    }

    function Initialize-TestJournalCase {
        $script:caseRoot = Join-Path $script:ownershipScratch ([guid]::NewGuid().ToString('N'))
        $directory = Join-Path $script:caseRoot 'journal'
        [void][IO.Directory]::CreateDirectory($directory)
        $script:journalArguments = @{
            Directory = $directory
            ForbiddenRoot = $script:forbidden
            Server = 'dc.example.test'
            ParentDn = 'OU=Integration,DC=example,DC=test'
            ParentGuid = [guid]'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            UserName = 'DrunkenAD_abc01234'
            RunId = [guid]'01234567-89ab-cdef-0123-456789abcdef'
            TestSourceSHA256 = ('A' * 64)
        }
        $script:journal = $null
    }
}

AfterAll {
    if ($script:ownershipScratch -and [IO.Directory]::Exists($script:ownershipScratch)) {
        Remove-Item -LiteralPath $script:ownershipScratch -Recurse -Force -ErrorAction Stop
    }
}

Describe 'Integration journal intent' {
    BeforeEach { Initialize-TestJournalCase }
    It 'returns one bounded handle and serializes only the exact privacy allowlist without a BOM' {
        $outputs = @(New-TestOwnershipJournal)
        $outputs.Count | Should -Be 1
        $journal = $outputs[0]
        @($journal.PSObject.Properties.Name) | Should -Be @('Directory', 'Intent')
        $journal.Directory | Should -BeExactly $script:journalArguments.Directory
        $path = Join-Path $journal.Directory '00-intent.json'
        $bytes = [IO.File]::ReadAllBytes($path)
        $bytes[0] | Should -Be 123
        $bytes.Length | Should -BeLessThan 16385
        $raw = [IO.File]::ReadAllText($path)
        $intent = ConvertFrom-Json $raw
        @($intent.PSObject.Properties.Name) | Should -Be @(
            'SchemaVersion', 'RunId', 'Server', 'ParentDn', 'ParentGuid', 'UserName',
            'OwnershipToken', 'TestSourceSHA256', 'Disabled', 'CreatedUtc'
        )
        $intent.SchemaVersion | Should -Be 1
        $intent.RunId | Should -BeExactly $script:journalArguments.RunId.ToString('D')
        $intent.Server | Should -BeExactly $script:journalArguments.Server
        $intent.ParentDn | Should -BeExactly $script:journalArguments.ParentDn
        $intent.ParentGuid | Should -BeExactly $script:journalArguments.ParentGuid.ToString('D')
        $intent.UserName | Should -BeExactly 'DrunkenAD_abc01234'
        $intent.OwnershipToken | Should -BeExactly 'DrunkenAD integration 0123456789abcdef0123456789abcdef'
        $intent.TestSourceSHA256 | Should -BeExactly ('A' * 64)
        $intent.Disabled | Should -BeOfType ([bool])
        $intent.Disabled | Should -BeTrue
        $journal.Intent.CreatedUtc | Should -Match '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z\z'
        $raw | Should -Not -Match 'Password|Credential|Exception|StackTrace'
        $raw.Contains($journal.Directory) | Should -BeFalse
        Get-TestReceiptNames | Should -Be @('00-intent.json')
    }

    It 'denies reuse without altering the existing intent' {
        $journal = New-TestOwnershipJournal
        $path = Join-Path $journal.Directory '00-intent.json'
        $before = [IO.File]::ReadAllBytes($path)
        { New-TestOwnershipJournal } | Should -Throw '*empty*reuse*'
        [IO.File]::ReadAllBytes($path) | Should -Be $before
    }

    It 'rejects a nonempty directory containing <Entry>' -ForEach @(
        @{ Entry = 'unrelated.txt'; DirectoryEntry = $false }
        @{ Entry = '.hidden'; DirectoryEntry = $false }
        @{ Entry = 'subdirectory'; DirectoryEntry = $true }
    ) {
        $path = Join-Path $script:journalArguments.Directory $Entry
        if ($DirectoryEntry) { [void][IO.Directory]::CreateDirectory($path) }
        else { [IO.File]::WriteAllText($path, 'synthetic') }
        { New-TestOwnershipJournal } | Should -Throw '*empty*'
        [IO.File]::Exists((Join-Path $script:journalArguments.Directory '00-intent.json')) | Should -BeFalse
    }

    It 'never creates a missing directory' {
        $missing = Join-Path $script:caseRoot 'missing'
        { New-TestOwnershipJournal @{ Directory = $missing } } | Should -Throw
        [IO.Directory]::Exists($missing) | Should -BeFalse
    }

    It 'accepts either digest case without changing the pinned value' -ForEach @(
        @{ Digest = ('a' * 64) }
        @{ Digest = ('A' * 64) }
    ) {
        (New-TestOwnershipJournal @{ TestSourceSHA256 = $Digest }).Intent.TestSourceSHA256 | Should -BeExactly $Digest
    }

    It 'rejects forbidden root equality and a real repository descendant' {
        foreach ($directory in @($script:repositoryRoot, (Join-Path $script:repositoryRoot 'tests'))) {
            { New-TestOwnershipJournal @{ Directory = $directory; ForbiddenRoot = $script:repositoryRoot } } |
                Should -Throw '*outside the forbidden root*'
        }
    }

    It 'does not confuse a sibling prefix with a forbidden descendant' {
        $sibling = Join-Path $script:ownershipScratch 'forbidden-sibling'
        [void][IO.Directory]::CreateDirectory($sibling)
        (New-TestOwnershipJournal @{ Directory = $sibling }).Directory | Should -BeExactly $sibling
    }

    It 'rejects noncanonical or nonlocal directory spelling <Label>' -ForEach @(
        @{ Label = 'relative'; Path = 'relative' }
        @{ Label = 'drive-relative'; Path = 'C:relative' }
        @{ Label = 'drive-only'; Path = 'C:' }
        @{ Label = 'UNC'; Path = '\\example.invalid\share\journal' }
        @{ Label = 'slash UNC'; Path = '//example.invalid/share/journal' }
        @{ Label = 'provider'; Path = 'FileSystem::/private/tmp' }
    ) {
        { New-TestOwnershipJournal @{ Directory = $Path } } | Should -Throw
        Get-TestReceiptNames | Should -BeNullOrEmpty
    }

    It 'rejects dot segments before resolving filesystem aliases' {
        $path = $script:journalArguments.Directory + [IO.Path]::DirectorySeparatorChar + '..' + [IO.Path]::DirectorySeparatorChar + 'journal'
        { New-TestOwnershipJournal @{ Directory = $path } } | Should -Throw '*dot segments*'
    }

    It 'rejects <Field> with <Label> before writing' -ForEach @(
        @{ Field = 'ParentGuid'; Label = 'empty GUID'; Value = [guid]::Empty }
        @{ Field = 'RunId'; Label = 'empty GUID'; Value = [guid]::Empty }
        @{ Field = 'ParentGuid'; Label = 'malformed GUID'; Value = 'not-a-guid' }
        @{ Field = 'RunId'; Label = 'GUID array'; Value = @([guid]::NewGuid(), [guid]::NewGuid()) }
        @{ Field = 'UserName'; Label = 'uppercase suffix'; Value = 'DrunkenAD_ABC01234' }
        @{ Field = 'UserName'; Label = 'wrong prefix'; Value = 'drunkenad_abc01234' }
        @{ Field = 'UserName'; Label = 'long suffix'; Value = 'DrunkenAD_abc012345' }
        @{ Field = 'UserName'; Label = 'trailing newline'; Value = "DrunkenAD_abc01234`n" }
        @{ Field = 'TestSourceSHA256'; Label = 'short digest'; Value = ('a' * 63) }
        @{ Field = 'TestSourceSHA256'; Label = 'nonhex digest'; Value = ('g' * 64) }
        @{ Field = 'TestSourceSHA256'; Label = 'trailing newline'; Value = (('a' * 64) + "`n") }
        @{ Field = 'Server'; Label = 'blank'; Value = ' ' }
        @{ Field = 'Server'; Label = 'oversize'; Value = ('a' * 254) }
        @{ Field = 'Server'; Label = 'control characters'; Value = "dc`nexample.test" }
        @{ Field = 'ParentDn'; Label = 'blank'; Value = ' ' }
        @{ Field = 'ParentDn'; Label = 'oversize'; Value = ('a' * 2049) }
        @{ Field = 'ParentDn'; Label = 'control characters'; Value = "OU=test`rDC=test" }
    ) {
        $overrides = @{}
        $overrides[$Field] = $Value
        { New-TestOwnershipJournal $overrides } | Should -Throw
        Get-TestReceiptNames | Should -BeNullOrEmpty
    }
}

Describe 'Integration journal state machine' {
    BeforeEach { Initialize-TestJournalCase }
    It 'records an ordered successful lifecycle with silent event writes and exact event fields' {
        Initialize-TestCreatedJournal
        @(Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued).Count | Should -Be 0
        @(Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State AbsenceVerified -OperationErrorObserved).Count | Should -Be 0
        Get-TestReceiptNames | Should -Be @('00-intent.json', '01-create-issued.json', '02-created.json', '03-delete-issued.json', '04-absence-verified.json')
        foreach ($name in @('01-create-issued.json', '02-created.json', '03-delete-issued.json', '04-absence-verified.json')) {
            $path = Join-Path $script:journal.Directory $name
            [IO.File]::ReadAllBytes($path)[0] | Should -Be 123
            $event = ConvertFrom-Json ([IO.File]::ReadAllText($path))
            @($event.PSObject.Properties.Name) | Should -Be @('SchemaVersion', 'RunId', 'State', 'ObjectGuid', 'OperationErrorObserved', 'CreatedUtc')
            $event.SchemaVersion | Should -Be 1
            $event.RunId | Should -BeExactly $script:journal.Intent.RunId
            $event.OperationErrorObserved | Should -BeOfType ([bool])
            if ($name -eq '01-create-issued.json') { $event.ObjectGuid | Should -BeNullOrEmpty }
            else { $event.ObjectGuid | Should -BeExactly $script:fixtureGuid.ToString('D') }
            $event.OperationErrorObserved | Should -Be ($name -eq '04-absence-verified.json')
        }
    }

    It 'allows Created to terminate as <State> without recording a deletion' -ForEach @(
        @{ State = 'AbsenceVerified'; File = '04-absence-verified.json' }
        @{ State = 'CleanupUnknown'; File = '04-cleanup-unknown.json' }
    ) {
        Initialize-TestCreatedJournal
        Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State $State -ObjectGuid $script:fixtureGuid
        Get-TestReceiptNames | Should -Be @('00-intent.json', '01-create-issued.json', '02-created.json', $File)
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued } | Should -Throw '*terminal*'
    }

    It 'records cleanup uncertainty after a delete attempt without claiming absence' {
        Initialize-TestCreatedJournal
        Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued
        Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State CleanupUnknown -OperationErrorObserved
        Get-TestReceiptNames | Should -Contain '04-cleanup-unknown.json'
        Get-TestReceiptNames | Should -Not -Contain '04-absence-verified.json'
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State AbsenceVerified } | Should -Throw '*terminal*'
    }

    It 'keeps unknown creation terminal with no object identity or inferred absence' {
        $journal = New-TestOwnershipJournal
        Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued
        Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreationOutcomeUnknown -OperationErrorObserved
        $event = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $journal.Directory '02-creation-unknown.json')))
        $event.ObjectGuid | Should -BeNullOrEmpty
        $event.OperationErrorObserved | Should -BeTrue
        foreach ($state in @('CreateIssued', 'Created', 'CreationOutcomeUnknown', 'DeleteIssued', 'AbsenceVerified', 'CleanupUnknown')) {
            { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State $state } | Should -Throw '*terminal*'
        }
        Get-TestReceiptNames | Should -Be @('00-intent.json', '01-create-issued.json', '02-creation-unknown.json')
    }

    It 'refuses an initial <State> transition' -ForEach @(
        @{ State = 'Created' }
        @{ State = 'CreationOutcomeUnknown' }
        @{ State = 'DeleteIssued' }
        @{ State = 'AbsenceVerified' }
        @{ State = 'CleanupUnknown' }
    ) {
        $journal = New-TestOwnershipJournal
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State $State } | Should -Throw '*transition*'
        Get-TestReceiptNames | Should -Be @('00-intent.json')
    }

    It 'refuses duplicate create or delete attempts and preserves receipts' {
        Initialize-TestCreatedJournal
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State CreateIssued } | Should -Throw '*transition*'
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State Created -ObjectGuid $script:fixtureGuid } | Should -Throw '*transition*'
        Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued
        $path = Join-Path $script:journal.Directory '03-delete-issued.json'
        $before = [IO.File]::ReadAllBytes($path)
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued } | Should -Throw '*transition*'
        [IO.File]::ReadAllBytes($path) | Should -Be $before
    }

    It 'requires a nonempty GUID for Created and rejects unexpected GUIDs before creation' {
        $journal = New-TestOwnershipJournal
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued -ObjectGuid $script:fixtureGuid } | Should -Throw '*unconfirmed*'
        Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State Created } | Should -Throw '*requires*GUID*'
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State Created -ObjectGuid ([guid]::Empty) } | Should -Throw '*nonempty*'
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State Created -ObjectGuid 'bad-guid' } | Should -Throw
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreationOutcomeUnknown -ObjectGuid $script:fixtureGuid } | Should -Throw '*unconfirmed*'
        Get-TestReceiptNames | Should -Be @('00-intent.json', '01-create-issued.json')
    }

    It 'rejects a cleanup GUID different from the durable Created GUID for <State>' -ForEach @(
        @{ State = 'DeleteIssued' }
        @{ State = 'AbsenceVerified' }
        @{ State = 'CleanupUnknown' }
    ) {
        Initialize-TestCreatedJournal
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State $State -ObjectGuid ([guid]::NewGuid()) } | Should -Throw '*durably recorded*'
        Get-TestReceiptNames | Should -Be @('00-intent.json', '01-create-issued.json', '02-created.json')
    }

    It 'rejects noncanonical states and raw operation-error text' {
        $journal = New-TestOwnershipJournal
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State createissued } | Should -Throw '*transition*'
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State NotAState } | Should -Throw
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued -OperationErrorObserved:'raw error' } | Should -Throw
        Get-TestReceiptNames | Should -Be @('00-intent.json')
    }
}

Describe 'Immutable journal bindings and failure paths' {
    BeforeEach { Initialize-TestJournalCase }
    It 'rejects external intent mutation of <Field>' -ForEach @(
        @{ Field = 'RunId'; Value = '99999999-2222-3333-4444-555555555555' }
        @{ Field = 'Server'; Value = 'other.example.test' }
        @{ Field = 'ParentDn'; Value = 'OU=Other,DC=example,DC=test' }
        @{ Field = 'ParentGuid'; Value = '99999999-2222-3333-4444-555555555555' }
        @{ Field = 'UserName'; Value = 'DrunkenAD_ffffffff' }
        @{ Field = 'OwnershipToken'; Value = 'different token' }
        @{ Field = 'TestSourceSHA256'; Value = ('b' * 64) }
        @{ Field = 'Disabled'; Value = $false }
        @{ Field = 'SchemaVersion'; Value = '1' }
        @{ Field = 'CreatedUtc'; Value = 'changed' }
    ) {
        $journal = New-TestOwnershipJournal
        $journal.Intent.$Field = $Value
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued } | Should -Throw '*intent was changed*'
        Get-TestReceiptNames | Should -Be @('00-intent.json')
    }

    It 'rejects a changed directory even with an exact copy of the immutable intent' {
        $journal = New-TestOwnershipJournal
        $copy = Join-Path $script:caseRoot 'copy'
        [void][IO.Directory]::CreateDirectory($copy)
        [IO.File]::Copy((Join-Path $journal.Directory '00-intent.json'), (Join-Path $copy '00-intent.json'))
        $journal.Directory = $copy
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued } | Should -Throw '*handle was changed*'
        @([IO.Directory]::GetFiles($copy)).Count | Should -Be 1
    }

    It 'rejects a fabricated handle with matching fields' {
        $journal = New-TestOwnershipJournal
        $copy = [pscustomobject]@{ Directory = $journal.Directory; Intent = $journal.Intent }
        { Write-DrunkenADIntegrationJournalEvent -Journal $copy -State CreateIssued } | Should -Throw '*original in-process handle*'
    }

    It 'rejects added properties without ever serializing their values' {
        $journal = New-TestOwnershipJournal
        $journal.Intent | Add-Member -NotePropertyName Password -NotePropertyValue 'synthetic-not-a-password'
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued } | Should -Throw '*intent was changed*'
        [IO.File]::ReadAllText((Join-Path $journal.Directory '00-intent.json')) | Should -Not -Match 'Password'
    }

    It 'fails closed on <Label> intent content and preserves it' -ForEach @(
        @{ Label = 'empty'; Content = '' }
        @{ Label = 'partial'; Content = '{"SchemaVersion":' }
        @{ Label = 'wrong shape'; Content = '[]' }
        @{ Label = 'unbounded'; Content = ('a' * 16385) }
        @{ Label = 'duplicate properties'; Content = '{"SchemaVersion":1,"SchemaVersion":2}' }
    ) {
        $journal = New-TestOwnershipJournal
        Set-TestReceipt -Name '00-intent.json' -Text $Content
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued } | Should -Throw
        [IO.File]::ReadAllText((Join-Path $journal.Directory '00-intent.json')) | Should -BeExactly $Content
        Get-TestReceiptNames | Should -Be @('00-intent.json')
    }

    It 'fails closed on a changed created identity in an otherwise valid JSON receipt' {
        Initialize-TestCreatedJournal
        $path = Join-Path $script:journal.Directory '02-created.json'
        $raw = [IO.File]::ReadAllText($path).Replace($script:fixtureGuid.ToString('D'), [guid]::NewGuid().ToString('D'))
        Set-TestReceipt -Name '02-created.json' -Text $raw
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued } | Should -Throw '*changed or is incomplete*'
    }

    It 'fails closed on a missing receipt' {
        Initialize-TestCreatedJournal
        [IO.File]::Delete((Join-Path $script:journal.Directory '01-create-issued.json'))
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued } | Should -Throw '*missing*'
    }

    It 'rejects a directory in place of an immutable receipt' {
        $journal = New-TestOwnershipJournal
        $path = Join-Path $journal.Directory '00-intent.json'
        [IO.File]::Delete($path)
        [void][IO.Directory]::CreateDirectory($path)
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued } | Should -Throw '*regular files*'
    }

    It 'rejects <EncodingFault> bytes in an immutable receipt' -ForEach @(
        @{ EncodingFault = 'invalid UTF-8'; Prefix = [byte[]]@(255, 254, 255) }
        @{ EncodingFault = 'a UTF-8 BOM'; Prefix = [byte[]]@(239, 187, 191) }
    ) {
        $journal = New-TestOwnershipJournal
        $path = Join-Path $journal.Directory '00-intent.json'
        $bytes = [byte[]]($Prefix + [IO.File]::ReadAllBytes($path))
        [IO.File]::WriteAllBytes($path, $bytes)
        { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued } | Should -Throw
        [IO.File]::ReadAllBytes($path) | Should -Be $bytes
    }

    It 'rejects unexplained <Name> without overwriting or removing it' -ForEach @(
        @{ Name = '02-creation-unknown.json' }
        @{ Name = '03-delete-issued.json' }
        @{ Name = 'unrelated.json' }
    ) {
        Initialize-TestCreatedJournal
        Set-TestReceipt -Name $Name -Text '{'
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued } | Should -Throw '*unexpected or partial*'
        [IO.File]::ReadAllText((Join-Path $script:journal.Directory $Name)) | Should -BeExactly '{'
    }

    It 'uses exclusive file creation and preserves an existing partial file' {
        $path = Join-Path $script:journalArguments.Directory '00-intent.json'
        [IO.File]::WriteAllText($path, '{')
        { Write-DrunkenADJournalFile -Path $path -Json '{"synthetic":true}' } | Should -Throw '*preserve all files*'
        [IO.File]::ReadAllText($path) | Should -BeExactly '{'
    }

    It 'permanently faults a handle after a write collision following preflight' {
        Initialize-TestCreatedJournal
        $script:originalBindingReader = ${function:Get-DrunkenADJournalBinding}
        Mock Get-DrunkenADJournalBinding {
            param($Journal)
            $result = & $script:originalBindingReader -Journal $Journal
            Set-TestReceipt -Name '03-delete-issued.json' -Text '{'
            return $result
        }
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued } | Should -Throw '*preserve all files*'
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued } | Should -Throw '*no retries*'
        [IO.File]::ReadAllText((Join-Path $script:journal.Directory '03-delete-issued.json')) | Should -BeExactly '{'
    }

    It 'preserves a partial write and prevents a second attempt' {
        Initialize-TestCreatedJournal
        Mock Write-DrunkenADJournalFile {
            param($Path, $Json)
            [IO.File]::WriteAllText($Path, '{')
            throw 'Synthetic write failure.'
        }
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued } | Should -Throw '*Synthetic write failure*'
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued } | Should -Throw '*no retries*'
        Should -Invoke Write-DrunkenADJournalFile -Times 1 -Exactly
        [IO.File]::ReadAllText((Join-Path $script:journal.Directory '03-delete-issued.json')) | Should -BeExactly '{'
    }

    It 'faults the handle when opening a new receipt is denied without creating a file' {
        Initialize-TestCreatedJournal
        Mock New-Object {
            throw (New-Object UnauthorizedAccessException 'Synthetic directory write denial.')
        } -ParameterFilter { $TypeName -eq 'IO.FileStream' -and $ArgumentList[1] -eq [IO.FileMode]::CreateNew }
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued } | Should -Throw '*preserve all files*'
        { Write-DrunkenADIntegrationJournalEvent -Journal $script:journal -State DeleteIssued } | Should -Throw '*no retries*'
        Get-TestReceiptNames | Should -Be @('00-intent.json', '01-create-issued.json', '02-created.json')
    }

    It 'requires a durable flush and retains the receipt if that flush fails' {
        $script:flushProbe = $null
        Mock New-Object {
            param($TypeName, $ArgumentList)
            $stream = [IO.File]::Open($ArgumentList[0], [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $probe = [pscustomobject]@{ Inner = $stream; Durable = $false; Disposed = $false; Options = $ArgumentList[5] }
            $probe | Add-Member -MemberType ScriptMethod -Name Write -Value {
                param($Bytes, $Offset, $Count)
                $this.Inner.Write($Bytes, $Offset, $Count)
            }
            $probe | Add-Member -MemberType ScriptMethod -Name Flush -Value {
                param($Durable)
                $this.Durable = $Durable
                throw 'Synthetic flush failure.'
            }
            $probe | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
                $this.Inner.Dispose()
                $this.Disposed = $true
            }
            $script:flushProbe = $probe
            return $probe
        } -ParameterFilter { $TypeName -eq 'IO.FileStream' -and $ArgumentList[1] -eq [IO.FileMode]::CreateNew }
        { New-TestOwnershipJournal } | Should -Throw '*preserve all files*'
        $script:flushProbe.Durable | Should -BeTrue
        $script:flushProbe.Disposed | Should -BeTrue
        $script:flushProbe.Options | Should -Be ([IO.FileOptions]::WriteThrough)
        $path = Join-Path $script:journalArguments.Directory '00-intent.json'
        [IO.File]::Exists($path) | Should -BeTrue
        $before = [IO.File]::ReadAllBytes($path)
        { New-TestOwnershipJournal } | Should -Throw '*reuse is prohibited*'
        [IO.File]::ReadAllBytes($path) | Should -Be $before
    }

    It 'leaves a read-only intent unchanged while appending a new event' {
        $journal = New-TestOwnershipJournal
        $receiptItem = Get-Item -LiteralPath (Join-Path $journal.Directory '00-intent.json')
        $before = [IO.File]::ReadAllBytes($receiptItem.FullName)
        try {
            $receiptItem.IsReadOnly = $true
            { Write-DrunkenADJournalFile -Path $receiptItem.FullName -Json '{}' } | Should -Throw '*preserve all files*'
            Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued
            [IO.File]::ReadAllBytes($receiptItem.FullName) | Should -Be $before
            $receiptItem.Refresh()
            $receiptItem.IsReadOnly | Should -BeTrue
        }
        finally { $receiptItem.IsReadOnly = $false }
    }
}

Describe 'Integration journal reparse rejection' {
    BeforeEach { Initialize-TestJournalCase }
    It 'rejects a linked <Location>' -ForEach @(
        @{ Location = 'directory' }
        @{ Location = 'ancestor' }
        @{ Location = 'receipt' }
    ) {
        $target = Join-Path $script:caseRoot 'target'
        $link = Join-Path $script:caseRoot 'link'
        [void][IO.Directory]::CreateDirectory($target)
        if ($Location -eq 'receipt') {
            $journal = New-TestOwnershipJournal
            $source = Join-Path $target 'intent.json'
            $link = Join-Path $journal.Directory '00-intent.json'
            [IO.File]::Move($link, $source)
            $target = $source
        }
        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because 'This platform or account cannot create test-only symbolic links.'
            return
        }
        try {
            if ($Location -eq 'receipt') {
                { Write-DrunkenADIntegrationJournalEvent -Journal $journal -State CreateIssued } | Should -Throw '*reparse points*'
            }
            else {
                $directory = $link
                if ($Location -eq 'ancestor') {
                    [void][IO.Directory]::CreateDirectory((Join-Path $target 'child'))
                    $directory = Join-Path $link 'child'
                }
                { New-TestOwnershipJournal @{ Directory = $directory } } | Should -Throw '*reparse points*'
            }
        }
        finally { Remove-Item -LiteralPath $link -Force -ErrorAction Stop }
    }
}

Describe 'Integration owned-user assertions' {
    BeforeEach {
        Initialize-TestJournalCase
        Initialize-TestCreatedJournal
    }

    It 'silently accepts one renamed disabled user with the exact GUID and token' {
        $user = New-TestOwnedUser
        @(Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User $user -ExpectedGuid $script:fixtureGuid).Count | Should -Be 0
        @(Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User @($user) -ExpectedGuid $script:fixtureGuid).Count | Should -Be 0
        $user.ObjectGUID = $script:fixtureGuid.ToString('D')
        { Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User $user -ExpectedGuid $script:fixtureGuid } | Should -Not -Throw
    }

    It 'requires one result, not <Label>' -ForEach @(
        @{ Label = 'null'; Kind = 'null' }
        @{ Label = 'empty collection'; Kind = 'empty' }
        @{ Label = 'duplicate results'; Kind = 'duplicate' }
    ) {
        $users = switch ($Kind) {
            'null' { $null }
            'empty' { @() }
            'duplicate' { New-TestOwnedUser; New-TestOwnedUser }
        }
        { Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User $users -ExpectedGuid $script:fixtureGuid } | Should -Throw '*exactly one user*'
    }

    It 'rejects missing <Field>' -ForEach @(
        @{ Field = 'ObjectGUID' }
        @{ Field = 'Description' }
        @{ Field = 'Enabled' }
        @{ Field = 'ObjectClass' }
    ) {
        $user = New-TestOwnedUser
        $user.PSObject.Properties.Remove($Field)
        { Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User $user -ExpectedGuid $script:fixtureGuid } | Should -Throw '*complete, unambiguous*'
    }

    It 'rejects <Field> with <Label>' -ForEach @(
        @{ Field = 'ObjectGUID'; Label = 'empty GUID'; Value = [guid]::Empty }
        @{ Field = 'ObjectGUID'; Label = 'different GUID'; Value = [guid]::NewGuid() }
        @{ Field = 'ObjectGUID'; Label = 'invalid string'; Value = 'invalid' }
        @{ Field = 'ObjectGUID'; Label = 'array'; Value = @([guid]'11111111-2222-3333-4444-555555555555') }
        @{ Field = 'ObjectGUID'; Label = 'null'; Value = $null }
        @{ Field = 'ObjectGUID'; Label = 'numeric type'; Value = 123 }
        @{ Field = 'Description'; Label = 'wrong token'; Value = 'DrunkenAD integration other' }
        @{ Field = 'Description'; Label = 'wrong case'; Value = 'drunkenad integration 0123456789abcdef0123456789abcdef' }
        @{ Field = 'Description'; Label = 'array'; Value = @('DrunkenAD integration 0123456789abcdef0123456789abcdef') }
        @{ Field = 'Description'; Label = 'null'; Value = $null }
        @{ Field = 'Enabled'; Label = 'true'; Value = $true }
        @{ Field = 'Enabled'; Label = 'false string'; Value = 'false' }
        @{ Field = 'Enabled'; Label = 'zero'; Value = 0 }
        @{ Field = 'Enabled'; Label = 'null'; Value = $null }
        @{ Field = 'Enabled'; Label = 'array'; Value = @($false) }
        @{ Field = 'ObjectClass'; Label = 'computer'; Value = 'computer' }
        @{ Field = 'ObjectClass'; Label = 'array'; Value = @('user') }
        @{ Field = 'ObjectClass'; Label = 'null'; Value = $null }
    ) {
        $user = New-TestOwnedUser
        $user.$Field = $Value
        { Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User $user -ExpectedGuid $script:fixtureGuid } | Should -Throw
    }

    It 'rejects an empty or malformed expected GUID' {
        $user = New-TestOwnedUser
        { Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User $user -ExpectedGuid ([guid]::Empty) } | Should -Throw '*nonempty*'
        { Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User $user -ExpectedGuid 'invalid' } | Should -Throw
    }

    It 'rejects a matching supplied and returned GUID when it differs from Created' {
        $user = New-TestOwnedUser
        $user.ObjectGUID = [guid]::NewGuid()
        { Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User $user -ExpectedGuid $user.ObjectGUID } | Should -Throw '*ownership metadata*'
    }

    It 'rechecks the immutable intent before trusting a user' {
        $user = New-TestOwnedUser
        $script:journal.Intent.OwnershipToken = 'changed'
        $user.Description = 'changed'
        { Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User $user -ExpectedGuid $script:fixtureGuid } | Should -Throw '*intent was changed*'
    }

    It 'rereads on-disk intent before trusting a matching in-memory user' {
        $user = New-TestOwnedUser
        Set-TestReceipt -Name '00-intent.json' -Text '{}'
        { Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User $user -ExpectedGuid $script:fixtureGuid } | Should -Throw '*changed or is incomplete*'
    }

    It 'does not use the mutable name as ownership proof' {
        $user = New-TestOwnedUser
        $user.Name = $script:journal.Intent.UserName
        $user.Description = 'unowned'
        { Assert-DrunkenADIntegrationOwnedUser -Journal $script:journal -User $user -ExpectedGuid $script:fixtureGuid } | Should -Throw '*ownership metadata*'
    }
}
