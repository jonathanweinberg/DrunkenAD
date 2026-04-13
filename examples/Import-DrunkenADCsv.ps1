[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ConfigPath')]
param(
    [Parameter(Mandatory = $true)]
    [string]$DomainController,

    [string]$CsvPath = (Join-Path -Path $PSScriptRoot -ChildPath 'data/drink-ingestion-sample.csv'),

    [Parameter(Mandatory = $true, ParameterSetName = 'NamespaceMap')]
    [hashtable]$NamespaceMap,

    [Parameter(ParameterSetName = 'ConfigPath')]
    [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'data/drink-ingestion-config.json'),

    [string]$LogPath
)

$modulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'DrunkenAD/DrunkenAD.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

$importParams = @{
    CsvPath          = $CsvPath
    DomainController = $DomainController
}

if ($PSBoundParameters.ContainsKey('LogPath')) {
    $importParams['LogPath'] = $LogPath
}

if ($PSCmdlet.ParameterSetName -eq 'NamespaceMap') {
    $importParams['NamespaceMap'] = $NamespaceMap
}
else {
    $importParams['ConfigPath'] = $ConfigPath
}

Import-ADUserDrinkCsvData @importParams
