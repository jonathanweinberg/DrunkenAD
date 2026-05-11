<#
.SYNOPSIS
Compatibility wrapper for the older projection command name.

.DESCRIPTION
Calls `Set-ADUserDrinkProjection` with the same parameters. Retained for
backward compatibility with earlier scripts and examples.

.NOTES
Prefer `Set-ADUserDrinkProjection` for new usage.
#>
function Invoke-ADUserDrinkDataDemo {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low', DefaultParameterSetName = 'SamAccountName')]
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

        [hashtable]$AttributeMap,

        [switch]$IncludeDefaultAttributeMap,

        [Alias('Server')]
        [string]$DomainController,

        [string]$LogPath,

        [switch]$PassThru
    )

    Set-ADUserDrinkProjection @PSBoundParameters
}
