[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Path $PSScriptRoot -Parent
$sourceFiles = @(& git -C $projectRoot ls-files --cached --others --exclude-standard | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

if ($sourceFiles.Count -eq 0) {
    throw 'No source files were found. Run this check from inside the DrunkenAD Git repository.'
}

$trackedLiveResults = @($sourceFiles | Where-Object { $_ -like 'tests/Live/results/*' })
if ($trackedLiveResults.Count -gt 0) {
    foreach ($path in $trackedLiveResults) {
        Write-Host "SOURCE_LIVE_RESULT $path" -ForegroundColor Red
    }

    throw 'Live campaign result artifacts must stay out of source control.'
}

$textExtensions = @(
    '.csv'
    '.html'
    '.json'
    '.md'
    '.mmd'
    '.ps1'
    '.psd1'
    '.psm1'
    '.txt'
    '.yaml'
    '.yml'
)

$pathPatterns = @(
    ('/Users/' + 'jonathanweinberg')
    ('Codex_' + 'DrunkenAD')
)

$pathViolations = @()

foreach ($relativePath in $sourceFiles) {
    if ($textExtensions -notcontains [System.IO.Path]::GetExtension($relativePath)) {
        continue
    }

    $fullPath = Join-Path -Path $projectRoot -ChildPath $relativePath
    $content = Get-Content -LiteralPath $fullPath -Raw

    foreach ($pattern in $pathPatterns) {
        if ($content -match [regex]::Escape($pattern)) {
            $pathViolations += [pscustomobject]@{
                Path    = $relativePath
                Pattern = $pattern
            }
        }
    }
}

if ($pathViolations.Count -gt 0) {
    foreach ($violation in $pathViolations) {
        Write-Host "MACHINE_PATH $($violation.Path): $($violation.Pattern)" -ForegroundColor Red
    }

    throw 'Documentation and test harness text must not contain machine-specific checkout paths.'
}

$markdownFiles = @(
    $sourceFiles |
        Where-Object {
            $_ -match '^(README|CONTRIBUTING|CONTRIBUTOR-LICENSE-AGREEMENT)\.md$' -or
            $_ -match '^docs/.+\.md$'
        }
)

function Test-RelativeDocTarget {
    param(
        [Parameter(Mandatory)]
        [string]$Href,

        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [int]$LineNumber
    )

    $target = ($Href -replace '\s+".*"$', '').Trim()

    if ([string]::IsNullOrWhiteSpace($target)) {
        return $null
    }

    if ($target -match '^(https?:|mailto:)' -or $target.StartsWith('#')) {
        return $null
    }

    $targetPath = ($target -split '#', 2)[0]

    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted($targetPath)) {
        return [pscustomobject]@{
            Path    = $SourcePath
            Line    = $LineNumber
            Target  = $target
            Message = 'Use repository-relative links, not absolute filesystem paths.'
        }
    }

    $sourceDirectory = Split-Path -Path (Join-Path -Path $projectRoot -ChildPath $SourcePath) -Parent
    $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path -Path $sourceDirectory -ChildPath $targetPath))

    if (-not $resolvedPath.StartsWith($projectRoot, [System.StringComparison]::Ordinal)) {
        return [pscustomobject]@{
            Path    = $SourcePath
            Line    = $LineNumber
            Target  = $target
            Message = 'Link target resolves outside the repository.'
        }
    }

    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        return [pscustomobject]@{
            Path    = $SourcePath
            Line    = $LineNumber
            Target  = $target
            Message = 'Link target does not exist.'
        }
    }

    return $null
}

$linkFailures = @()

foreach ($relativePath in $markdownFiles) {
    $fullPath = Join-Path -Path $projectRoot -ChildPath $relativePath
    $lines = @(Get-Content -LiteralPath $fullPath)
    $insideFence = $false

    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        $lineNumber = $lineIndex + 1

        if ($line -match '^\s*```') {
            $insideFence = -not $insideFence
            continue
        }

        if ($insideFence) {
            continue
        }

        foreach ($match in [regex]::Matches($line, '!?\[[^\]]*\]\(([^)]+)\)')) {
            $failure = Test-RelativeDocTarget -Href $match.Groups[1].Value -SourcePath $relativePath -LineNumber $lineNumber
            if ($null -ne $failure) {
                $linkFailures += $failure
            }
        }

        foreach ($match in [regex]::Matches($line, 'src="([^"]+)"')) {
            $failure = Test-RelativeDocTarget -Href $match.Groups[1].Value -SourcePath $relativePath -LineNumber $lineNumber
            if ($null -ne $failure) {
                $linkFailures += $failure
            }
        }
    }
}

if ($linkFailures.Count -gt 0) {
    foreach ($failure in $linkFailures) {
        Write-Host "BROKEN_DOC_LINK $($failure.Path):$($failure.Line) $($failure.Target) - $($failure.Message)" -ForegroundColor Red
    }

    throw 'One or more documentation links failed validation.'
}

& (Join-Path -Path $PSScriptRoot -ChildPath 'Test-DrunkenADArchitectureMap.ps1')

Write-Host 'Documentation hygiene checks passed.' -ForegroundColor Green
