[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path -Path $projectRoot -ChildPath 'DrunkenAD/DrunkenAD.psd1'
$mapJsonPath = Join-Path -Path $projectRoot -ChildPath 'docs/drunkenad-architecture-map.json'
$selfContainedHtmlPath = Join-Path -Path $projectRoot -ChildPath 'docs/drunkenad-architecture-map.html'
$externalHtmlPath = Join-Path -Path $projectRoot -ChildPath 'docs/drunkenad-architecture-map-external.html'
$script:mapValidationFailures = New-Object 'System.Collections.Generic.List[string]'

function Add-ArchitectureMapFailure {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $script:mapValidationFailures.Add($Message) | Out-Null
}

function Test-ObjectProperty {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    return ($InputObject.PSObject.Properties.Name -contains $Name)
}

function Get-RequiredPropertyValue {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Context
    )

    if (-not (Test-ObjectProperty -InputObject $InputObject -Name $Name)) {
        Add-ArchitectureMapFailure "$Context is missing required property '$Name'."
        return $null
    }

    return $InputObject.$Name
}

function Test-RequiredStringProperty {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $value = Get-RequiredPropertyValue -InputObject $InputObject -Name $Name -Context $Context
    if ($null -eq $value) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace([string]$value)) {
        Add-ArchitectureMapFailure "$Context property '$Name' must not be blank."
        return $false
    }

    return $true
}

function Get-RequiredArrayProperty {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $value = Get-RequiredPropertyValue -InputObject $InputObject -Name $Name -Context $Context
    if ($null -eq $value) {
        return @()
    }

    $items = @($value)
    if ($items.Count -eq 0) {
        Add-ArchitectureMapFailure "$Context property '$Name' must contain at least one item."
    }

    return $items
}

function Add-UniqueMapId {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Seen,

        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Context
    )

    if ($Seen.ContainsKey($Id)) {
        Add-ArchitectureMapFailure "Duplicate $Context id '$Id'."
        return
    }

    $Seen[$Id] = $true
}

function Test-RepositoryRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        Add-ArchitectureMapFailure "$Context contains a blank file path."
        return
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        Add-ArchitectureMapFailure "$Context file path '$Path' must be repository-relative."
        return
    }

    $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path -Path $projectRoot -ChildPath $Path))
    $projectPrefix = $projectRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $resolvedPath.StartsWith($projectPrefix, [System.StringComparison]::Ordinal)) {
        Add-ArchitectureMapFailure "$Context file path '$Path' resolves outside the repository."
        return
    }

    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        Add-ArchitectureMapFailure "$Context file path '$Path' does not exist."
    }
}

function ConvertTo-CanonicalJson {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    return ($InputObject | ConvertTo-Json -Depth 64 -Compress)
}

foreach ($requiredPath in @($manifestPath, $mapJsonPath, $selfContainedHtmlPath, $externalHtmlPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        Add-ArchitectureMapFailure "Required file not found: $requiredPath"
    }
}

if ($script:mapValidationFailures.Count -eq 0) {
    $manifest = Test-ModuleManifest -Path $manifestPath
    $mapJson = Get-Content -LiteralPath $mapJsonPath -Raw | ConvertFrom-Json

    foreach ($propertyName in @('title', 'subtitle', 'version', 'updated')) {
        Test-RequiredStringProperty -InputObject $mapJson -Name $propertyName -Context 'architecture map root' | Out-Null
    }

    if ((Test-ObjectProperty -InputObject $mapJson -Name 'version') -and $mapJson.version -ne $manifest.Version.ToString()) {
        Add-ArchitectureMapFailure "Architecture map version '$($mapJson.version)' must match manifest version '$($manifest.Version)'."
    }

    $legendKinds = @{}
    $legendItems = Get-RequiredArrayProperty -InputObject $mapJson -Name 'legend' -Context 'architecture map root'
    foreach ($legendItem in $legendItems) {
        $context = 'legend item'
        $hasKind = Test-RequiredStringProperty -InputObject $legendItem -Name 'kind' -Context $context
        Test-RequiredStringProperty -InputObject $legendItem -Name 'label' -Context $context | Out-Null
        Test-RequiredStringProperty -InputObject $legendItem -Name 'color' -Context $context | Out-Null

        if ($hasKind) {
            Add-UniqueMapId -Seen $legendKinds -Id ([string]$legendItem.kind) -Context 'legend kind'
        }
    }

    $laneIds = @{}
    $nodesById = @{}
    $lanes = Get-RequiredArrayProperty -InputObject $mapJson -Name 'lanes' -Context 'architecture map root'
    foreach ($lane in $lanes) {
        $laneContext = 'lane'
        $hasLaneId = Test-RequiredStringProperty -InputObject $lane -Name 'id' -Context $laneContext
        Test-RequiredStringProperty -InputObject $lane -Name 'title' -Context $laneContext | Out-Null
        Test-RequiredStringProperty -InputObject $lane -Name 'description' -Context $laneContext | Out-Null

        if ($hasLaneId) {
            $laneContext = "lane '$($lane.id)'"
            Add-UniqueMapId -Seen $laneIds -Id ([string]$lane.id) -Context 'lane'
        }

        $nodes = Get-RequiredArrayProperty -InputObject $lane -Name 'nodes' -Context $laneContext
        foreach ($node in $nodes) {
            $nodeContext = "$laneContext node"
            $hasNodeId = Test-RequiredStringProperty -InputObject $node -Name 'id' -Context $nodeContext
            Test-RequiredStringProperty -InputObject $node -Name 'label' -Context $nodeContext | Out-Null
            $hasKind = Test-RequiredStringProperty -InputObject $node -Name 'kind' -Context $nodeContext
            Test-RequiredStringProperty -InputObject $node -Name 'summary' -Context $nodeContext | Out-Null

            if ($hasNodeId) {
                $nodeContext = "node '$($node.id)'"
                Add-UniqueMapId -Seen $nodesById -Id ([string]$node.id) -Context 'node'
            }

            if ($hasKind -and -not $legendKinds.ContainsKey([string]$node.kind)) {
                Add-ArchitectureMapFailure "$nodeContext uses kind '$($node.kind)' that is not declared in legend."
            }

            $files = Get-RequiredArrayProperty -InputObject $node -Name 'files' -Context $nodeContext
            foreach ($file in $files) {
                Test-RepositoryRelativePath -Path ([string]$file) -Context $nodeContext
            }
        }
    }

    $flowIds = @{}
    $flows = Get-RequiredArrayProperty -InputObject $mapJson -Name 'flows' -Context 'architecture map root'
    foreach ($flow in $flows) {
        $flowContext = 'flow'
        $hasFlowId = Test-RequiredStringProperty -InputObject $flow -Name 'id' -Context $flowContext
        Test-RequiredStringProperty -InputObject $flow -Name 'title' -Context $flowContext | Out-Null
        Test-RequiredStringProperty -InputObject $flow -Name 'description' -Context $flowContext | Out-Null

        if ($hasFlowId) {
            $flowContext = "flow '$($flow.id)'"
            Add-UniqueMapId -Seen $flowIds -Id ([string]$flow.id) -Context 'flow'
        }

        $pathNodes = Get-RequiredArrayProperty -InputObject $flow -Name 'path' -Context $flowContext
        foreach ($nodeId in $pathNodes) {
            if (-not $nodesById.ContainsKey([string]$nodeId)) {
                Add-ArchitectureMapFailure "$flowContext references unknown node '$nodeId'."
            }
        }

        $steps = Get-RequiredArrayProperty -InputObject $flow -Name 'steps' -Context $flowContext
        foreach ($step in $steps) {
            if ([string]::IsNullOrWhiteSpace([string]$step)) {
                Add-ArchitectureMapFailure "$flowContext contains a blank step."
            }
        }
    }

    foreach ($propertyName in @('failureBoundaries', 'entrypoints')) {
        $items = Get-RequiredArrayProperty -InputObject $mapJson -Name $propertyName -Context 'architecture map root'
        foreach ($item in $items) {
            if ([string]::IsNullOrWhiteSpace([string]$item)) {
                Add-ArchitectureMapFailure "architecture map root property '$propertyName' contains a blank item."
            }
        }
    }

    $selfContainedHtml = Get-Content -LiteralPath $selfContainedHtmlPath -Raw
    $embeddedMatch = [regex]::Match(
        $selfContainedHtml,
        '<script\s+type="application/json"\s+id="map-data">\s*(?<json>.*?)\s*</script>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    if (-not $embeddedMatch.Success) {
        Add-ArchitectureMapFailure 'Self-contained architecture map HTML is missing the embedded map-data JSON script.'
    }
    else {
        $embeddedJson = $embeddedMatch.Groups['json'].Value | ConvertFrom-Json
        if ((ConvertTo-CanonicalJson -InputObject $embeddedJson) -ne (ConvertTo-CanonicalJson -InputObject $mapJson)) {
            Add-ArchitectureMapFailure 'Embedded self-contained architecture map data does not match docs/drunkenad-architecture-map.json.'
        }
    }

    $externalHtml = Get-Content -LiteralPath $externalHtmlPath -Raw
    if ($externalHtml -notmatch 'drunkenad-architecture-map\.json') {
        Add-ArchitectureMapFailure 'External-data architecture map HTML must reference drunkenad-architecture-map.json.'
    }

    if ($externalHtml -notmatch 'fetch\(') {
        Add-ArchitectureMapFailure 'External-data architecture map HTML must fetch the external JSON map data.'
    }
}

if ($script:mapValidationFailures.Count -gt 0) {
    foreach ($failure in $script:mapValidationFailures) {
        Write-Host "ARCHITECTURE_MAP_ERROR $failure" -ForegroundColor Red
    }

    throw 'Architecture map validation failed.'
}

Write-Host 'Architecture map validation passed.' -ForegroundColor Green
