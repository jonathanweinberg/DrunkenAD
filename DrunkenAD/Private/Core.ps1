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

    $tempPath = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempPath)) {
        $tempPath = [System.IO.Path]::GetTempPath()
    }

    Join-Path -Path $tempPath -ChildPath 'DrunkenAD.log'
}

function Write-DrunkenADLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$LogPath
    )

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        return
    }

    $directoryPath = Split-Path -Path $LogPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($directoryPath) -and -not (Test-Path -LiteralPath $directoryPath)) {
        New-Item -Path $directoryPath -ItemType Directory -Force | Out-Null
    }

    Add-Content -LiteralPath $LogPath -Value ('{0:u} {1}' -f (Get-Date), $Message)
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
        Properties = @($Properties + 'distinguishedName', 'samAccountName', 'drink')
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
