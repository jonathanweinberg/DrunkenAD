<#
.SYNOPSIS
Gets data entries stored in the Active Directory `drink` attribute.

.DESCRIPTION
Treats the multivalued `drink` attribute like a small prefixed data store. The
function resolves a single Active Directory user by an exact identifier,
validates that the `drink` schema attribute is enabled, and returns either all
stored values or only those values that match a supplied literal prefix.

.PARAMETER SamAccountName
Finds the user by exact `sAMAccountName`.

.PARAMETER UserPrincipalName
Finds the user by exact `userPrincipalName`.

.PARAMETER EmployeeID
Finds the user by exact `employeeID`.

.PARAMETER Mail
Finds the user by exact `mail`.

.PARAMETER Pager
Finds the user by exact `pager`.

.PARAMETER InputObject
ADUser from Get-ADUser. Requires an explicit DomainController (or Server).
Only ObjectGUID is used from the input; directory values are read on that controller.

.PARAMETER Prefix
Optional nonblank literal prefix used to filter the returned `drink` values.

.PARAMETER Credential
Optional directory credential. Omit to use the normal Active Directory authentication context.

.PARAMETER DomainController
Controller for schema validation and reads. Required for ADUser input;
optional when using an explicit identifier.

.INPUTS
Microsoft.ActiveDirectory.Management.ADUser

.OUTPUTS
Explicit identifiers: matching drink strings.
ADUser input: one object per user with ObjectGUID, SamAccountName and a DrinkValues
array, even when no values match.

.EXAMPLE
Get-ADUser -Filter "Department -eq 'Example'" -Server 'dc01.contoso.com' | Get-ADUserDrinkData -Prefix 'App-' -DomainController 'dc01.contoso.com'

Returns one named result per user, including users with no matching values.

.EXAMPLE
Get-ADUserDrinkData -SamAccountName 'TesterAccount' -DomainController 'dc01.contoso.com'

Returns all values currently stored in the user's `drink` attribute.

.EXAMPLE
Get-ADUserDrinkData -SamAccountName 'TesterAccount' -Prefix 'AppProfile-' -DomainController 'dc01.contoso.com'

Returns only the `drink` values that start with the literal prefix `AppProfile-`.

.LINK
about_DrunkenAD

.LINK
Set-ADUserDrinkData

.COMPONENT
DrunkenAD

.ROLE
User

.ROLE
Operator

.FUNCTIONALITY
Read namespaced Active Directory drink data
#>
function Get-ADUserDrinkData {
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

        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'ADUser')]
        [PSTypeName('Microsoft.ActiveDirectory.Management.ADUser')]
        [psobject]$InputObject,

        [string]$Prefix,

        [Alias('Server')]
        [string]$DomainController,

        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_.UserName) })]
        [pscredential]$Credential
    )

    begin {
        if ($PSBoundParameters.ContainsKey('Prefix') -and [string]::IsNullOrWhiteSpace($Prefix)) {
            throw 'Prefix cannot be null, empty, or blank when supplied.'
        }
        $schemaStatus = $null
        $auth = Get-DrunkenADCredentialParameters $PSBoundParameters
    }

    process {
        $fromUser = $PSCmdlet.ParameterSetName -eq 'ADUser'
        if ($fromUser) { $guid = Get-DrunkenADPipelineUserGuid $InputObject $DomainController }
        if ($null -eq $schemaStatus) {
            $schemaStatus = Assert-ADDrinkAttributeEnabled @auth -Server $DomainController -PassThru
        }
        if ($fromUser) {
            $user = Read-DrunkenADPipelineUser @auth -Guid $guid -Server $schemaStatus.Server
        }
        else {
            $identity = Get-DrunkenADIdentityParameters -BoundParameters $PSBoundParameters
            $user = Resolve-DrunkenADUser @auth @identity -Server $schemaStatus.Server -Properties @('drink')
        }
        $values = ConvertTo-DrunkenADStringArray -Values $user.drink -SkipBlank
        if ($PSBoundParameters.ContainsKey('Prefix')) {
            $values = @($values | Where-Object {
                $_.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
            })
        }
        if ($fromUser) {
            [pscustomobject]@{ ObjectGUID = $guid; SamAccountName = $user.SamAccountName; DrinkValues = [string[]]$values }
        }
        else { @($values) }
    }
}
