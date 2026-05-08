[CmdletBinding()]
param(
    [string]$Value = 'Enabled; Audited ; Keep-Stable',

    [string]$Delimiter = ';'
)

$modulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'DrunkenAD/DrunkenAD.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Split-DrunkenADCsvField -Value $Value -Delimiter $Delimiter |
    ForEach-Object {
        [pscustomobject]@{
            Value = $_
        }
    }
