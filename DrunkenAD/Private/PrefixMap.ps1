function Assert-DrunkenADNonOverlappingPrefixes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Prefixes
    )

    $normalizedPrefixes = @()
    foreach ($prefix in $Prefixes) {
        if ([string]::IsNullOrWhiteSpace($prefix)) {
            throw "Prefix values cannot be null, empty, or whitespace."
        }

        $normalizedPrefixes += $prefix
    }

    for ($leftIndex = 0; $leftIndex -lt $normalizedPrefixes.Count; $leftIndex++) {
        for ($rightIndex = $leftIndex + 1; $rightIndex -lt $normalizedPrefixes.Count; $rightIndex++) {
            $leftPrefix = $normalizedPrefixes[$leftIndex]
            $rightPrefix = $normalizedPrefixes[$rightIndex]

            $leftContainsRight = $leftPrefix.StartsWith($rightPrefix, [System.StringComparison]::OrdinalIgnoreCase)
            $rightContainsLeft = $rightPrefix.StartsWith($leftPrefix, [System.StringComparison]::OrdinalIgnoreCase)

            if ($leftContainsRight -or $rightContainsLeft) {
                throw "Prefix '$leftPrefix' overlaps prefix '$rightPrefix'. Prefix namespaces in one operation must not contain one another."
            }
        }
    }
}

function ConvertTo-DrunkenADPrefixMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Prefixes,

        [Parameter(Mandatory = $true)]
        [string[]]$DrinkValues
    )

    if ($Prefixes.Count -gt 1 -and $DrinkValues.Count -gt 1 -and $Prefixes.Count -ne $DrinkValues.Count) {
        throw "When both -Prefixes and -DrinkValues contain multiple values, their counts must match or one side must contain a single item."
    }

    foreach ($prefix in $Prefixes) {
        if ([string]::IsNullOrWhiteSpace($prefix)) {
            throw "Prefix values cannot be null, empty, or whitespace."
        }
    }

    $prefixMap = [ordered]@{}

    if ($Prefixes.Count -eq 1) {
        $prefixMap[$Prefixes[0]] = @($DrinkValues)
        return $prefixMap
    }

    if ($DrinkValues.Count -eq 1) {
        foreach ($prefix in $Prefixes) {
            if ($prefixMap.Contains($prefix)) {
                $prefixMap[$prefix] += @($DrinkValues[0])
            }
            else {
                $prefixMap[$prefix] = @($DrinkValues[0])
            }
        }

        return $prefixMap
    }

    for ($index = 0; $index -lt $Prefixes.Count; $index++) {
        $prefix = $Prefixes[$index]
        if ($prefixMap.Contains($prefix)) {
            $prefixMap[$prefix] += @($DrinkValues[$index])
        }
        else {
            $prefixMap[$prefix] = @($DrinkValues[$index])
        }
    }

    $prefixMap
}

function Merge-DrunkenADAttributeMap {
    [CmdletBinding()]
    param(
        [hashtable]$BaseMap,

        [hashtable]$OverlayMap
    )

    $mergedMap = [ordered]@{}

    foreach ($map in @($BaseMap, $OverlayMap)) {
        if ($null -eq $map) {
            continue
        }

        foreach ($prefixKey in $map.Keys) {
            $prefix = [string]$prefixKey
            if ([string]::IsNullOrWhiteSpace($prefix)) {
                throw "Attribute map prefixes cannot be null, empty, or whitespace."
            }

            $attributeNames = @($map[$prefixKey] | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($attributeNames.Count -eq 0) {
                throw "Attribute map prefix '$prefix' must include at least one attribute name."
            }

            if (-not $mergedMap.Contains($prefix)) {
                $mergedMap[$prefix] = @()
            }

            foreach ($attributeName in $attributeNames) {
                if ($mergedMap[$prefix] -notcontains $attributeName) {
                    $mergedMap[$prefix] += $attributeName
                }
            }
        }
    }

    $mergedMap
}
