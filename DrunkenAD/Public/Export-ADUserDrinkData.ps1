<#
.SYNOPSIS
Exports one drink namespace for an explicit list of users to a new JSON file.

.DESCRIPTION
Reads exact accounts on the selected endpoint. The UTF-8 review document has
schemaVersion (1), prefix, and users in request order. Each record contains
samAccountName and values, an ordinally sorted array of complete stored
strings, including their original prefix. No matches yields an empty array.
All lookups must succeed before the file is published. Never overwrites.

.PARAMETER SamAccountName
One or more distinct, exact account names; no wildcard or domain-wide search.

.PARAMETER Prefix
One nonblank literal namespace prefix, matched with ordinal case-insensitivity.

.PARAMETER DomainController
Explicit directory endpoint for the schema check and user lookups.

.PARAMETER Credential
Optional credential for all directory reads. Omit to use your current identity.

.PARAMETER Path
Literal path to a new file in an existing, access-controlled filesystem directory.
The export contains directory data in plaintext.

.INPUTS
None. Supply account names explicitly.

.OUTPUTS
None. Writes a UTF-8 JSON file without a byte-order mark.

.EXAMPLE
Export-ADUserDrinkData -SamAccountName 'TesterAccount' -Prefix 'AppProfile-' -DomainController 'dc01.contoso.com' -Path './review.json'

Exports the AppProfile namespace for one account.

.EXAMPLE
Export-ADUserDrinkData -SamAccountName 'TesterAccount','SecondAccount' -Prefix 'AppProfile-' -DomainController 'dc01.contoso.com' -Credential $reader -Path './team-review.json'

Uses an existing PSCredential to read both accounts.

.NOTES
Evidence for this command is mocked unit coverage only, not native AD validation.

.LINK
about_DrunkenAD

.LINK
Get-ADUserDrinkData

.COMPONENT
DrunkenAD

.ROLE
Operator

.FUNCTIONALITY
Export namespaced Active Directory drink data for review
#>
function Export-ADUserDrinkData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SamAccountName,

        [Parameter(Mandatory)]
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
        [string]$Prefix,

        [Parameter(Mandatory)]
        [Alias('Server')]
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
        [string]$DomainController,

        [ValidateNotNull()]
        [pscredential]$Credential,

        [Parameter(Mandatory)]
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
        [string]$Path
    )

    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $SamAccountName) {
        if ([string]::IsNullOrWhiteSpace($name) -or -not $names.Add($name)) {
            throw 'SamAccountName must contain only distinct, nonblank account names.'
        }
    }

    $provider = $drive = $null
    $target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$provider, [ref]$drive)
    if ($provider.Name -ne 'FileSystem') { throw 'Path must be a filesystem path.' }
    if (Test-Path -LiteralPath $Path -ErrorAction Stop) { throw 'Export destination already exists.' }
    $parent = [IO.Path]::GetDirectoryName($target)
    if (-not [IO.Directory]::Exists($parent)) { throw 'Export directory does not exist.' }

    $auth = @{}
    if ($PSBoundParameters.ContainsKey('Credential')) { $auth.Credential = $Credential }
    $status = Assert-ADDrinkAttributeEnabled -Server $DomainController -PassThru @auth
    $records = @(foreach ($name in $SamAccountName) {
        $user = Resolve-DrunkenADUser -SamAccountName $name -Server $status.Server @auth
        [string[]]$values = @(foreach ($value in $user.drink) {
            if ($null -ne $value -and $value.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) { $value }
        })
        [Array]::Sort($values, [StringComparer]::Ordinal)
        [ordered]@{ samAccountName = $user.samAccountName; values = $values }
    })
    $json = ConvertTo-Json -InputObject ([ordered]@{ schemaVersion = 1; prefix = $Prefix; users = $records }) -Depth 5
    $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($json)

    # Finish writing a sibling file before the no-overwrite rename.
    $temp = [IO.Path]::Combine($parent, [IO.Path]::GetRandomFileName())
    $stream = [IO.File]::Open($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        [IO.File]::Move($temp, $target)
    }
    finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
    }
}
