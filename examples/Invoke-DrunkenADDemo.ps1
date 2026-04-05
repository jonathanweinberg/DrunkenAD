[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DomainController,

    [Parameter(Mandatory = $true)]
    [string]$DnsSuffix,

    [hashtable]$AttributeMap,

    [switch]$IncludeDefaultAttributeMap,

    [switch]$KeepTestObjects
)

$modulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'DrunkenAD/DrunkenAD.psd1'
Import-Module $modulePath -Force -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction Stop

function New-DemoPassword {
    [CmdletBinding()]
    param(
        [int]$Length = 20
    )

    if ($Length -lt 4) {
        throw 'Password length must be at least 4 characters.'
    }

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

if (-not (Test-ADDrinkAttributeEnabled -Server $DomainController)) {
    throw "The 'drink' attribute is not enabled on $DomainController."
}

$runId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$userName = "TesterAccount_$runId"
$groupName = "TesterAccountSG_$runId"
$employeeId = [string](Get-Random -Minimum 100000 -Maximum 999999)
$userPrincipalName = '{0}@{1}' -f $userName, $DnsSuffix
$mail = $userPrincipalName
$pager = $userPrincipalName

$securePassword = New-DemoPassword | ConvertTo-SecureString -AsPlainText -Force
$createdUser = $false
$createdGroup = $false

$otherAttributes = @{
    mail              = $mail
    userPrincipalName = $userPrincipalName
    pager             = $pager
    description       = 'DrunkenAD demo account'
    department        = 'Identity Engineering'
    title             = 'Demo User'
    company           = 'Contoso'
}

try {
    New-ADUser -Name $userName -SamAccountName $userName -AccountPassword $securePassword -Enabled $false -EmployeeID $employeeId -OtherAttributes $otherAttributes -Server $DomainController -ErrorAction Stop
    $createdUser = $true

    New-ADGroup -Name $groupName -SamAccountName $groupName -GroupScope Global -GroupCategory Security -Description 'Temporary demo group for DrunkenAD' -Server $DomainController -ErrorAction Stop
    $createdGroup = $true

    Add-ADGroupMember -Identity $groupName -Members $userName -Server $DomainController -ErrorAction Stop

    $demoParams = @{
        SamAccountName      = $userName
        DomainController    = $DomainController
        Confirm             = $false
        Verbose             = $true
        PassThru            = $true
    }

    if ($PSBoundParameters.ContainsKey('AttributeMap')) {
        $demoParams['AttributeMap'] = $AttributeMap
    }

    if ($IncludeDefaultAttributeMap) {
        $demoParams['IncludeDefaultAttributeMap'] = $true
    }

    (Invoke-ADUserDrinkDataDemo @demoParams).FinalDrinkValues
}
finally {
    if (-not $KeepTestObjects) {
        if ($createdGroup) {
            Remove-ADGroup -Identity $groupName -Server $DomainController -Confirm:$false -ErrorAction SilentlyContinue
        }

        if ($createdUser) {
            Remove-ADUser -Identity $userName -Server $DomainController -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}
