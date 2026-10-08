function Get-DrunkenADIdentityParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$BoundParameters
    )

    $identity = @{}
    foreach ($name in @('SamAccountName', 'UserPrincipalName', 'EmployeeID', 'Mail', 'Pager')) {
        if ($BoundParameters.Keys -contains $name) {
            $identity[$name] = $BoundParameters[$name]
        }
    }
    return $identity
}

function New-DrunkenADWriteContext {
    [CmdletBinding()]
    param([string]$Server)

    $status = Get-DrunkenADDrinkAttributeStatus -Server $Server
    if (-not $status.ReadyForUserWrite) {
        throw $status.BlockingMessage
    }
    if ([string]::IsNullOrWhiteSpace($status.Server)) {
        throw 'A domain controller could not be selected for this write operation.'
    }
    $status
}

function Get-DrunkenADPrefixWritePlan {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $CurrentValues,

        [Parameter(Mandatory = $true)]
        [hashtable]$PrefixMap,

        [Nullable[int]]$RangeUpper
    )

    Assert-DrunkenADNonOverlappingPrefixes -Prefixes @($PrefixMap.Keys | ForEach-Object { [string]$_ })
    $current = ConvertTo-DrunkenADStringArray -Values $CurrentValues
    $owned = New-Object 'System.Collections.Generic.List[string]'
    $preserved = New-Object 'System.Collections.Generic.List[string]'
    foreach ($value in $current) {
        $matchesPrefix = $false
        foreach ($prefix in $PrefixMap.Keys) {
            if ($value.StartsWith([string]$prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matchesPrefix = $true
                break
            }
        }
        if ($matchesPrefix) { $owned.Add($value) } else { $preserved.Add($value) }
    }

    $desired = New-Object 'System.Collections.Generic.List[string]'
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($prefix in @($PrefixMap.Keys | Sort-Object)) {
        foreach ($suffix in (ConvertTo-DrunkenADStringArray -Values $PrefixMap[$prefix] -SkipBlank)) {
            $value = '{0}{1}' -f $prefix, $suffix
            if ($null -ne $RangeUpper -and $value.Length -gt $RangeUpper) {
                throw "A drink value has $($value.Length) characters; the target schema allows at most $RangeUpper, including the prefix."
            }
            if ($seen.Add($value)) { $desired.Add($value) }
        }
    }

    # Ordinal comparisons retain requested spelling for case-only replacements.
    $oldSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $newSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($value in $owned) { [void]$oldSet.Add($value) }
    foreach ($value in $desired) { [void]$newSet.Add($value) }
    [pscustomobject]@{
        Remove = [string[]]@($owned | Where-Object { -not $newSet.Contains($_) })
        Add = [string[]]@($desired | Where-Object { -not $oldSet.Contains($_) })
        FinalDrinkValues = [string[]]@($preserved.ToArray() + $desired.ToArray())
    }
}

function Invoke-DrunkenADPrefixWrite {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$User,

        [Parameter(Mandatory = $true)]
        [hashtable]$PrefixMap,

        [Parameter(Mandatory = $true)]
        [psobject]$Context,

        [string]$LogPath,
        [switch]$PassThru
    )

    if (-not $Context.ReadyForUserWrite -or [string]::IsNullOrWhiteSpace($Context.Server)) {
        throw 'A validated write context with a pinned domain controller is required.'
    }
    $plan = Get-DrunkenADPrefixWritePlan -CurrentValues $User.drink -PrefixMap $PrefixMap -RangeUpper $Context.RangeUpper
    if ($plan.Remove.Count -gt 0 -or $plan.Add.Count -gt 0) {
        if ($PSCmdlet.ShouldProcess($User.SamAccountName, "Remove $($plan.Remove.Count) and add $($plan.Add.Count) drink value(s)")) {
            $parameters = @{
                Identity = $User.DistinguishedName
                Server = $Context.Server
                ErrorAction = 'Stop'
                Confirm = $false
            }
            if ($plan.Remove.Count -gt 0) { $parameters['Remove'] = @{ drink = $plan.Remove } }
            if ($plan.Add.Count -gt 0) { $parameters['Add'] = @{ drink = $plan.Add } }
            Set-ADUser @parameters
            Write-DrunkenADLog -LogPath $LogPath -Message "Updated drink attribute: removed $($plan.Remove.Count), added $($plan.Add.Count) value(s)."
        }
    }
    else {
        Write-Verbose 'No drink attribute changes are required.'
        Write-DrunkenADLog -LogPath $LogPath -Message 'No drink attribute changes were required.'
    }
    if ($PassThru) { $plan.FinalDrinkValues }
}
