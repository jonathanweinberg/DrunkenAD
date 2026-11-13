<#
.SYNOPSIS
Finds users with a complete namespaced value in their drink attribute.

.DESCRIPTION
Joins Prefix and Value without a separator, escapes the result as literal LDAP
data, and runs one server-side equality query. A wildcard is an ordinary
character here. Equality uses the directory's matching rule, not a case-sensitive
PowerShell comparison. No schema checks or writes are performed.
This command has mocked unit-test coverage only; it has not been validated
against a live directory.

.PARAMETER Prefix
Literal namespace prefix, including any delimiter used when storing the entry.

.PARAMETER Value
Literal value following the prefix. Neither part is trimmed.

.PARAMETER DomainController
Directory server to query. When omitted, Get-ADUser selects its default server.

.PARAMETER SearchBase
Distinguished name at which to start the search. Omit to use the AD cmdlet default.

.PARAMETER Credential
Optional credential for the query. Omit to use the AD cmdlet's normal credentials.

.INPUTS
None. This command does not accept pipeline input.

.OUTPUTS
Microsoft.ActiveDirectory.Management.ADUser. Returns each matching user with
the default Get-ADUser properties; no matches produce no output.

.EXAMPLE
Find-ADUserByDrinkData -Prefix 'Dept-' -Value 'Ops' -DomainController 'dc01.contoso.com'

Finds users with a drink entry equal to Dept-Ops.

.EXAMPLE
Find-ADUserByDrinkData -Prefix 'Tag-' -Value 'A*' -SearchBase 'OU=Staff,DC=contoso,DC=com' -DomainController 'dc01.contoso.com'

Searches under Staff for Tag-A followed by a literal asterisk.

.LINK
about_DrunkenAD

.LINK
Get-ADUserDrinkData

.COMPONENT
DrunkenAD

.ROLE
Operator

.FUNCTIONALITY
Find users by a literal namespaced drink value
#>
function Find-ADUserByDrinkData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('\S')]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('\S')]
        [string]$Value,

        [Alias('Server')]
        [ValidatePattern('\S')]
        [string]$DomainController,

        [ValidatePattern('\S')]
        [string]$SearchBase,

        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_.UserName) })]
        [pscredential]$Credential
    )

    $query = @{
        LDAPFilter = '(drink={0})' -f (ConvertTo-DrunkenADLdapFilterValue -Value ($Prefix + $Value))
        ErrorAction = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('DomainController')) { $query.Server = $DomainController }
    if ($PSBoundParameters.ContainsKey('SearchBase')) { $query.SearchBase = $SearchBase }
    $auth = Get-DrunkenADCredentialParameters $PSBoundParameters

    Initialize-DrunkenADModule
    Get-ADUser @query @auth
}
