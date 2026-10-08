function Initialize-DrunkenADModule {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -Name ActiveDirectory)) {
        Import-Module ActiveDirectory -ErrorAction Stop
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

function ConvertTo-DrunkenADStringArray {
    [CmdletBinding()]
    param(
        $Values,

        [switch]$SkipBlank
    )

    $result = New-Object System.Collections.Generic.List[string]

    foreach ($value in @($Values)) {
        if ($null -eq $value) {
            continue
        }

        $stringValue = [string]$value
        if ($SkipBlank -and [string]::IsNullOrWhiteSpace($stringValue)) {
            continue
        }

        $result.Add($stringValue)
    }

    return ,([string[]]$result.ToArray())
}

function Test-DrunkenADStringSetEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ReferenceValues,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$DifferenceValues
    )

    if ($ReferenceValues.Count -ne $DifferenceValues.Count) {
        return $false
    }

    $unmatchedValues = New-Object System.Collections.Generic.List[string]
    foreach ($value in $ReferenceValues) {
        $unmatchedValues.Add($value)
    }

    foreach ($value in $DifferenceValues) {
        $matchIndex = -1
        for ($index = 0; $index -lt $unmatchedValues.Count; $index++) {
            if ([string]::Equals($unmatchedValues[$index], $value, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matchIndex = $index
                break
            }
        }

        if ($matchIndex -lt 0) {
            return $false
        }

        $unmatchedValues.RemoveAt($matchIndex)
    }

    return $true
}

function Get-DrunkenADLogRoot {
    [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)
}

function Resolve-DrunkenADLogPath {
    [CmdletBinding()]
    param(
        [string]$LogPath,

        [switch]$EnableLogging
    )

    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        return $LogPath
    }

    if (-not $EnableLogging) {
        return $null
    }

    $logRoot = Get-DrunkenADLogRoot
    if ([string]::IsNullOrWhiteSpace($logRoot)) {
        Write-Warning 'DrunkenAD automatic logging is unavailable because the personal log directory could not be resolved. Specify -LogPath to enable logging. This does not change the directory operation outcome.' -WarningAction Continue
        return $null
    }

    $logDirectory = Join-Path -Path $logRoot -ChildPath 'DrunkenAD/logs-v1'
    $script:DrunkenADDefaultLogPath = Join-Path -Path $logDirectory -ChildPath 'activity.log'
    $script:DrunkenADDefaultLogPath
}

function Assert-DrunkenADLogNotLinked {
    param([string]$Path)

    $current = [System.IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Logging through symbolic links or reparse points is not permitted.'
            }
        }
        $current = [System.IO.Path]::GetDirectoryName($current)
    }
}

function Write-DrunkenADDefaultLog {
    param([string]$Message, [string]$LogPath)

    if ($WhatIfPreference) { return }

    $limit = 1048576
    $header = '# DrunkenAD bounded log v1'
    $archive = Join-Path (Split-Path $LogPath -Parent) 'activity.previous.log'
    $encoding = New-Object System.Text.UTF8Encoding($false)
    if (-not (Get-Variable DrunkenADLogSession -Scope Script -ErrorAction SilentlyContinue)) {
        $script:DrunkenADLogSession = [guid]::NewGuid().ToString('N')
    }
    $line = '{0:u} session={1} {2}{3}' -f (Get-Date), $script:DrunkenADLogSession, $Message, [Environment]::NewLine
    $bytes = $encoding.GetBytes($line)
    if ($bytes.Length -gt ($limit - $encoding.GetByteCount($header + [Environment]::NewLine))) {
        throw 'Log entry exceeds the bounded log size limit.'
    }

    # A stable, path-specific mutex coordinates rotation across module instances.
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try { $key = [BitConverter]::ToString($hash.ComputeHash($encoding.GetBytes([IO.Path]::GetFullPath($LogPath).ToUpperInvariant()))).Replace('-', '') }
    finally { $hash.Dispose() }
    $mutex = New-Object System.Threading.Mutex($false, ('DrunkenADLog_' + $key))
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(5000) }
        catch [System.Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Timed out waiting for the default log writer.' }
        foreach ($path in @($LogPath, $archive)) {
            Assert-DrunkenADLogNotLinked $path
            if (Test-Path -LiteralPath $path) {
                if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
                    (Get-Content -LiteralPath $path -TotalCount 1 -ErrorAction Stop) -cne $header) {
                    throw 'Default log path contains a file not owned by DrunkenAD.'
                }
                if ((Get-Item -LiteralPath $path).Length -gt $limit) {
                    throw 'Existing default log exceeds the bounded log size limit.'
                }
            }
        }
        $directory = Split-Path $LogPath -Parent
        [void][IO.Directory]::CreateDirectory($directory)
        if ((Test-Path -LiteralPath $LogPath) -and ((Get-Item -LiteralPath $LogPath).Length + $bytes.Length -gt $limit)) {
            if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -ErrorAction Stop }
            Move-Item -LiteralPath $LogPath -Destination $archive -ErrorAction Stop
        }
        $stream = [IO.File]::Open($LogPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            if ($stream.Length -eq 0) {
                $headerBytes = $encoding.GetBytes($header + [Environment]::NewLine)
                $stream.Write($headerBytes, 0, $headerBytes.Length)
            }
            [void]$stream.Seek(0, [IO.SeekOrigin]::End)
            $stream.Write($bytes, 0, $bytes.Length)
        }
        finally { $stream.Dispose() }
    }
    finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Write-DrunkenADLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$LogPath
    )

    if ($WhatIfPreference -or [string]::IsNullOrWhiteSpace($LogPath)) {
        return
    }

    try {
        if ((Get-Variable DrunkenADDefaultLogPath -Scope Script -ErrorAction SilentlyContinue) -and
            [string]::Equals($LogPath, $script:DrunkenADDefaultLogPath, [StringComparison]::Ordinal)) {
            Write-DrunkenADDefaultLog -Message $Message -LogPath $LogPath
            return
        }

        Assert-DrunkenADLogNotLinked $LogPath
        $directoryPath = Split-Path -Path $LogPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($directoryPath) -and -not (Test-Path -LiteralPath $directoryPath)) {
            New-Item -Path $directoryPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        Add-Content -LiteralPath $LogPath -Value ('{0:u} {1}' -f (Get-Date), $Message) -ErrorAction Stop
    }
    catch {
        # Logging must not turn an already completed directory write into a failure.
        Write-Warning 'DrunkenAD could not write the activity log. This does not change the directory operation outcome.' -WarningAction Continue
    }
}

function Get-DrunkenADIdentityDescription {
    [CmdletBinding(DefaultParameterSetName = 'SamAccountName')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'SamAccountName')]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true, ParameterSetName = 'UserPrincipalName')]
        [string]$UserPrincipalName,

        [Parameter(Mandatory = $true, ParameterSetName = 'EmployeeID')]
        [string]$EmployeeID,

        [Parameter(Mandatory = $true, ParameterSetName = 'Mail')]
        [string]$Mail,

        [Parameter(Mandatory = $true, ParameterSetName = 'Pager')]
        [string]$Pager
    )

    switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName'   { return "SamAccountName '$SamAccountName'" }
        'UserPrincipalName' { return "UserPrincipalName '$UserPrincipalName'" }
        'EmployeeID'       { return "EmployeeID '$EmployeeID'" }
        'Mail'             { return "mail '$Mail'" }
        'Pager'            { return "pager '$Pager'" }
        default            { throw "Unsupported parameter set '$($PSCmdlet.ParameterSetName)'." }
    }
}

function Resolve-DrunkenADUser {
    [CmdletBinding(DefaultParameterSetName = 'SamAccountName')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'SamAccountName')]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true, ParameterSetName = 'UserPrincipalName')]
        [string]$UserPrincipalName,

        [Parameter(Mandatory = $true, ParameterSetName = 'EmployeeID')]
        [string]$EmployeeID,

        [Parameter(Mandatory = $true, ParameterSetName = 'Mail')]
        [string]$Mail,

        [Parameter(Mandatory = $true, ParameterSetName = 'Pager')]
        [string]$Pager,

        [string[]]$Properties = @('drink'),

        [string]$Server
    )

    Initialize-DrunkenADModule

    $identityParams = @{}
    switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName'   { $identityParams['SamAccountName'] = $SamAccountName }
        'UserPrincipalName' { $identityParams['UserPrincipalName'] = $UserPrincipalName }
        'EmployeeID'       { $identityParams['EmployeeID'] = $EmployeeID }
        'Mail'             { $identityParams['Mail'] = $Mail }
        'Pager'            { $identityParams['Pager'] = $Pager }
    }

    $identityDescription = Get-DrunkenADIdentityDescription @identityParams
    $ldapFilter = switch ($PSCmdlet.ParameterSetName) {
        'SamAccountName' {
            '(sAMAccountName={0})' -f (ConvertTo-DrunkenADLdapFilterValue -Value $SamAccountName)
        }
        'UserPrincipalName' {
            '(userPrincipalName={0})' -f (ConvertTo-DrunkenADLdapFilterValue -Value $UserPrincipalName)
        }
        'EmployeeID' {
            '(employeeID={0})' -f (ConvertTo-DrunkenADLdapFilterValue -Value $EmployeeID)
        }
        'Mail' {
            '(mail={0})' -f (ConvertTo-DrunkenADLdapFilterValue -Value $Mail)
        }
        'Pager' {
            '(pager={0})' -f (ConvertTo-DrunkenADLdapFilterValue -Value $Pager)
        }
        default {
            throw "Unsupported parameter set '$($PSCmdlet.ParameterSetName)'."
        }
    }

    $userParams = @{
        LDAPFilter = $ldapFilter
        Properties = @(@($Properties) + @('distinguishedName', 'samAccountName', 'drink') | Select-Object -Unique)
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $userParams['Server'] = $Server
    }

    $users = @(Get-ADUser @userParams)

    if ($users.Count -eq 0) {
        throw "No Active Directory user matched $identityDescription."
    }

    if ($users.Count -gt 1) {
        throw "The lookup for $identityDescription matched $($users.Count) users. Use a unique identifier."
    }

    $users[0]
}
