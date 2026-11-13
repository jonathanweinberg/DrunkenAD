[CmdletBinding()]
param(
    [string]$ModulePath = (Join-Path (Split-Path $PSScriptRoot) 'DrunkenAD')
)

$ErrorActionPreference = 'Stop'
$policy = Import-PowerShellDataFile -LiteralPath (Join-Path (Split-Path $PSScriptRoot) '.github/analyzer-policy.psd1')
Import-Module PSScriptAnalyzer -RequiredVersion $policy.RequiredVersion -ErrorAction Stop
$root = (Get-Item -LiteralPath $ModulePath).FullName
$reviewed = [Collections.Generic.HashSet[string]]::new([string[]]$policy.ReviewedWarnings)
$failures = @(foreach ($finding in (PSScriptAnalyzer\Invoke-ScriptAnalyzer -Path $root -Recurse -Severity Error,Warning -ErrorAction Stop)) {
    $file = [IO.Path]::GetRelativePath($root, $finding.ScriptPath).Replace('\', '/')
    $id = if ($finding.RuleSuppressionID) { $finding.RuleSuppressionID } else { $finding.Message }
    $key = "$file|$($finding.RuleName)|$id"
    if ($finding.Severity -eq 'Warning' -and $reviewed.Remove($key)) { continue }
    '{0}:{1} {2} {3}: {4}' -f $file, $finding.Line, $finding.Severity, $finding.RuleName, $finding.Message
})
if ($failures.Count) {
    throw ($failures -join [Environment]::NewLine)
}
if ($reviewed.Count) {
    throw ("Remove stale analyzer exceptions:`n" + (($reviewed | Sort-Object) -join [Environment]::NewLine))
}
Write-Output "PSScriptAnalyzer $($policy.RequiredVersion): no unreviewed module findings ($($policy.ReviewedWarnings.Count) reviewed warnings)."
