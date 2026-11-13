[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$Server,

    [switch]$Apply,

    [string]$ExpectedForestRoot,

    [string]$ExpectedDomainDnsRoot,

    [string]$ExpectedSchemaMaster,

    [string]$ReportPath,

    [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_.UserName) })]
    [pscredential]$Credential
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Update-DrunkenADSchemaCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_.UserName) })]
        [pscredential]$Credential
    )

    $rootDse = $null
    try {
        $path = "LDAP://$Server/RootDSE"
        $secure = [System.DirectoryServices.AuthenticationTypes]::Secure
        if ($PSBoundParameters.ContainsKey('Credential')) {
            # Configure the unbound entry before assigning the target. Never splat a password.
            $rootDse = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ErrorAction Stop
            $rootDse.AuthenticationType = $secure
            $rootDse.Username = $Credential.UserName
            $rootDse.Password = $Credential.GetNetworkCredential().Password
            $rootDse.Path = $path
        }
        else {
            $rootDse = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList $path -ErrorAction Stop
            $rootDse.AuthenticationType = $secure
        }

        # This write-only RootDSE operation blocks until the server cache is updated.
        $rootDse.Put('schemaUpdateNow', 1)
        $rootDse.SetInfo()
    }
    finally {
        if ($null -ne $rootDse) {
            $rootDse.Dispose()
        }
    }
}

function Write-DrunkenADSchemaEnablementReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Report,

        [string]$ReportPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
        $reportDirectory = Split-Path -Path $ReportPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($reportDirectory) -and -not (Test-Path -LiteralPath $reportDirectory)) {
            New-Item -Path $reportDirectory -ItemType Directory -Force | Out-Null
        }

        $Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8
    }

    [pscustomobject]$Report
}

function Enable-ADDrinkAttributeOnUserClass {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string]$Server,

        [switch]$Apply,

        [string]$ExpectedForestRoot,

        [string]$ExpectedDomainDnsRoot,

        [string]$ExpectedSchemaMaster,

        [string]$ReportPath,

        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_.UserName) })]
        [pscredential]$Credential
    )

    $projectRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $projectRoot -ChildPath 'DrunkenAD/DrunkenAD.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop

    $auth = @{}
    if ($PSBoundParameters.ContainsKey('Credential')) { $auth['Credential'] = $Credential }
    $forestLookupParams = @{
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $forestLookupParams['Server'] = $Server
    }

    $initialForest = Get-ADForest @auth @forestLookupParams
    $effectiveServer = if (-not [string]::IsNullOrWhiteSpace($Server)) { $Server } else { $initialForest.SchemaMaster }
    $forest = Get-ADForest @auth -Server $effectiveServer -ErrorAction Stop
    $domain = Get-ADDomain @auth -Server $effectiveServer -ErrorAction Stop
    $before = Test-ADDrinkAttributeReadyForUserWrite @auth -Server $effectiveServer -PassThru

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
        Write-DrunkenADSchemaEnablementReport -Report $report -ReportPath $ReportPath
        return
    }

    if ($before.ReadyForUserWrite) {
        $report['Status'] = 'AlreadyReady'

        Write-DrunkenADSchemaEnablementReport -Report $report -ReportPath $ReportPath
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

    if ($PSCmdlet.ShouldProcess($effectiveServer, "Add 'drink' to the Active Directory user class mayContain list and refresh the schema cache")) {
        Set-ADObject @auth -Identity $before.UserClassDistinguishedName -Server $effectiveServer -Add @{ mayContain = 'drink' } -ErrorAction Stop

        try {
            Write-Verbose "Refreshing the schema cache on '$effectiveServer' through RootDSE schemaUpdateNow. This call blocks until the refresh completes."
            Update-DrunkenADSchemaCache @auth -Server $effectiveServer
        }
        catch {
            throw "The 'drink' mayContain update completed on '$effectiveServer', but the schema cache refresh (RootDSE schemaUpdateNow) failed. The schema change has not been rolled back; readiness was not verified. Resolve the refresh failure and recheck readiness before user writes. Details: $($_.Exception.Message)"
        }

        $after = Test-ADDrinkAttributeReadyForUserWrite @auth -Server $effectiveServer -PassThru
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

    Write-DrunkenADSchemaEnablementReport -Report $report -ReportPath $ReportPath
}

if ($MyInvocation.InvocationName -ne '.') {
    Enable-ADDrinkAttributeOnUserClass @PSBoundParameters
}
