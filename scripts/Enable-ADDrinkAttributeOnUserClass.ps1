[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$Server,

    [switch]$Apply,

    [string]$ExpectedForestRoot,

    [string]$ExpectedDomainDnsRoot,

    [string]$ExpectedSchemaMaster,

    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Enable-ADDrinkAttributeOnUserClass {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string]$Server,

        [switch]$Apply,

        [string]$ExpectedForestRoot,

        [string]$ExpectedDomainDnsRoot,

        [string]$ExpectedSchemaMaster,

        [string]$ReportPath
    )

    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $projectRoot -ChildPath 'DrunkenAD/DrunkenAD.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop

    $forestLookupParams = @{
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $forestLookupParams['Server'] = $Server
    }

    $initialForest = Get-ADForest @forestLookupParams
    $effectiveServer = if (-not [string]::IsNullOrWhiteSpace($Server)) { $Server } else { $initialForest.SchemaMaster }
    $forest = Get-ADForest -Server $effectiveServer -ErrorAction Stop
    $domain = Get-ADDomain -Server $effectiveServer -ErrorAction Stop
    $before = Test-ADDrinkAttributeReadyForUserWrite -Server $effectiveServer -PassThru

    $report = [ordered]@{
        GeneratedAt          = (Get-Date).ToString('s')
        TargetServer         = $effectiveServer
        ForestRoot           = $forest.RootDomain
        DomainDnsRoot        = $domain.DNSRoot
        SchemaMaster         = $forest.SchemaMaster
        TargetIsSchemaMaster = ($effectiveServer -ieq $forest.SchemaMaster)
        ApplyRequested       = [bool]$Apply
        Applied              = $false
        Status               = 'Preview'
        Before               = $before
        After                = $before
        ExpectedForestRoot   = $ExpectedForestRoot
        ExpectedDomainDnsRoot = $ExpectedDomainDnsRoot
        ExpectedSchemaMaster = $ExpectedSchemaMaster
    }

    if (-not $Apply) {
        if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
            $reportDirectory = Split-Path -Path $ReportPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($reportDirectory) -and -not (Test-Path -LiteralPath $reportDirectory)) {
                New-Item -Path $reportDirectory -ItemType Directory -Force | Out-Null
            }

            $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8
        }

        [pscustomobject]$report
        return
    }

    if ($before.ReadyForUserWrite) {
        $report['Status'] = 'AlreadyReady'

        if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
            $reportDirectory = Split-Path -Path $ReportPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($reportDirectory) -and -not (Test-Path -LiteralPath $reportDirectory)) {
                New-Item -Path $reportDirectory -ItemType Directory -Force | Out-Null
            }

            $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8
        }

        [pscustomobject]$report
        return
    }

    if ($before.BlockingReason -ne 'NotAllowedOnUserClass') {
        throw $before.BlockingMessage
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedForestRoot) -or [string]::IsNullOrWhiteSpace($ExpectedDomainDnsRoot) -or [string]::IsNullOrWhiteSpace($ExpectedSchemaMaster)) {
        throw "Apply mode requires -ExpectedForestRoot, -ExpectedDomainDnsRoot, and -ExpectedSchemaMaster."
    }

    if ($forest.RootDomain -ne $ExpectedForestRoot) {
        throw "Expected forest root '$ExpectedForestRoot' but found '$($forest.RootDomain)'."
    }

    if ($domain.DNSRoot -ne $ExpectedDomainDnsRoot) {
        throw "Expected domain DNS root '$ExpectedDomainDnsRoot' but found '$($domain.DNSRoot)'."
    }

    if ($forest.SchemaMaster -ne $ExpectedSchemaMaster) {
        throw "Expected schema master '$ExpectedSchemaMaster' but found '$($forest.SchemaMaster)'."
    }

    if ($effectiveServer -ne $forest.SchemaMaster) {
        throw "Schema modification must be targeted at the schema master '$($forest.SchemaMaster)'."
    }

    if ($PSCmdlet.ShouldProcess($effectiveServer, "Add 'drink' to the Active Directory user class mayContain list")) {
        Set-ADObject -Identity $before.UserClassDistinguishedName -Server $effectiveServer -Add @{ mayContain = 'drink' } -ErrorAction Stop
        Start-Sleep -Milliseconds 500

        $after = Test-ADDrinkAttributeReadyForUserWrite -Server $effectiveServer -PassThru
        if (-not $after.ReadyForUserWrite) {
            throw "The schema update completed, but 'drink' is still not ready for user writes on '$effectiveServer'."
        }

        $report['Applied'] = $true
        $report['Status'] = 'Applied'
        $report['After'] = $after
    }
    else {
        $report['Status'] = 'WhatIf'
    }

    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        $reportDirectory = Split-Path -Path $ReportPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($reportDirectory) -and -not (Test-Path -LiteralPath $reportDirectory)) {
            New-Item -Path $reportDirectory -ItemType Directory -Force | Out-Null
        }

        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8
    }

    [pscustomobject]$report
}

if ($MyInvocation.InvocationName -ne '.') {
    Enable-ADDrinkAttributeOnUserClass @PSBoundParameters
}
