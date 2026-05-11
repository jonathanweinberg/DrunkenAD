<#
.SYNOPSIS
Splits a delimited CSV field into clean values for multivalue `drink` ingestion.

.DESCRIPTION
Splits a single CSV column value with a literal delimiter, trims each item, and
removes empty results. This is the same helper used by
`Import-ADUserDrinkCsvData` when a namespace mapping includes `SplitOn`.

The delimiter is escaped before splitting, so characters such as `|`, `.`, `+`,
or `[` are treated as text instead of regular expressions.

.PARAMETER Value
The source CSV field value to split.

.PARAMETER Delimiter
The literal delimiter between values. Defaults to `;`. The delimiter cannot be
empty or whitespace.

.EXAMPLE
Split-DrunkenADCsvField -Value 'Enabled; Audited ; Keep-Stable'

Returns `Enabled`, `Audited`, and `Keep-Stable`.

.EXAMPLE
Split-DrunkenADCsvField -Value 'One|Two||Three' -Delimiter '||'

Splits on the literal `||` delimiter.
#>
function Split-DrunkenADCsvField {
    [CmdletBinding()]
    param(
        [string]$Value,

        [string]$Delimiter = ';'
    )

    if ([string]::IsNullOrWhiteSpace($Delimiter)) {
        throw 'Delimiter cannot be empty or whitespace.'
    }

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    @(
        $Value -split [regex]::Escape($Delimiter) |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}
