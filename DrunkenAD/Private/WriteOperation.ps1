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

function Get-DrunkenADPipelineUserGuid {
    param($InputObject, [string]$DomainController)

    if ([string]::IsNullOrWhiteSpace($DomainController)) {
        throw 'Specify DomainController (or Server) for ADUser input.'
    }
    $property = $InputObject.PSObject.Properties['ObjectGUID']
    $guid = [guid]::Empty
    if (-not $property -or -not [guid]::TryParse([string]$property.Value, [ref]$guid) -or $guid -eq [guid]::Empty) {
        throw 'An ADUser with a nonempty ObjectGUID is required.'
    }
    $guid
}

function Read-DrunkenADPipelineUser {
    param([guid]$Guid, [string]$Server, [pscredential]$Credential)

    if ([string]::IsNullOrWhiteSpace($Server)) { throw 'A pinned domain controller is required.' }
    $auth = Get-DrunkenADCredentialParameters $PSBoundParameters
    $user = Get-ADUser @auth -Identity $Guid -Server $Server -Properties drink -ErrorAction Stop
    if ($null -eq $user -or $user.ObjectGUID -ne $Guid) {
        throw 'The directory did not return the requested ADUser.'
    }
    # An unset multivalued attribute may be absent even when requested.
    $drink = $user.PSObject.Properties['drink']
    [pscustomobject]@{
        ObjectGUID = $Guid
        SamAccountName = $user.SamAccountName
        drink = @(if ($null -ne $drink) { $drink.Value })
    }
}

function New-DrunkenADWriteContext {
    [CmdletBinding()]
    param([string]$Server, [pscredential]$Credential)

    $auth = Get-DrunkenADCredentialParameters $PSBoundParameters
    $status = Get-DrunkenADDrinkAttributeStatus @auth -Server $Server
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
        [switch]$PassThru,
        [switch]$ResultObject,
        [System.Management.Automation.PSCmdlet]$PipelineCmdlet,
        [pscredential]$Credential
    )

    if (-not $Context.ReadyForUserWrite -or [string]::IsNullOrWhiteSpace($Context.Server)) {
        throw 'A validated write context with a pinned domain controller is required.'
    }
    $plan = Get-DrunkenADPrefixWritePlan -CurrentValues $User.drink -PrefixMap $PrefixMap -RangeUpper $Context.RangeUpper
    $objectGuid = [guid]::Empty
    $guidProperty = $User.PSObject.Properties['ObjectGUID']
    $accountCorrelation = 'unavailable'
    if ($null -ne $guidProperty -and [guid]::TryParse([string]$guidProperty.Value, [ref]$objectGuid) -and $objectGuid -ne [guid]::Empty) {
        $accountCorrelation = $objectGuid.ToString('D')
    }
    $status = 'NoChange'
    if ($plan.Remove.Count -gt 0 -or $plan.Add.Count -gt 0) {
        $reason = [System.Management.Automation.ShouldProcessReason]::None
        $description = "Remove $($plan.Remove.Count) and add $($plan.Add.Count) drink value(s) for $($User.SamAccountName)"
        # Keep Yes/No to All on the public invocation across pipeline records.
        $confirmation = if ($PipelineCmdlet) { $PipelineCmdlet } else { $PSCmdlet }
        if ($confirmation.ShouldProcess($description, $description + '?', 'Confirm drink write', [ref]$reason)) {
            $parameters = @{
                Identity = if ($PipelineCmdlet) { $objectGuid } else { $User.DistinguishedName }
                Server = $Context.Server
                ErrorAction = 'Stop'
                Confirm = $false
            }
            if ($plan.Remove.Count -gt 0) { $parameters['Remove'] = @{ drink = $plan.Remove } }
            if ($plan.Add.Count -gt 0) { $parameters['Add'] = @{ drink = $plan.Add } }
            $auth = Get-DrunkenADCredentialParameters $PSBoundParameters
            Set-ADUser @auth @parameters
            $status = 'Written'
            Write-DrunkenADLog -LogPath $LogPath -Message "objectGUID=$accountCorrelation Updated drink attribute: removed $($plan.Remove.Count), added $($plan.Add.Count) value(s)."
        }
        else { $status = if ($reason -eq [System.Management.Automation.ShouldProcessReason]::WhatIf) { 'WhatIf' } else { 'Declined' } }
    }
    else {
        Write-Verbose 'No drink attribute changes are required.'
        Write-DrunkenADLog -LogPath $LogPath -Message "objectGUID=$accountCorrelation No drink attribute changes were required: removed 0, added 0 value(s)."
    }
    if ($PipelineCmdlet -and $PassThru) {
        [pscustomobject]@{
            ObjectGUID = $objectGuid; SamAccountName = $User.SamAccountName
            Status = $status; FinalDrinkValues = $plan.FinalDrinkValues
        }
    }
    elseif ($ResultObject) { [pscustomobject]@{ Status = $status; FinalDrinkValues = $plan.FinalDrinkValues } }
    elseif ($PassThru) { $plan.FinalDrinkValues }
}
