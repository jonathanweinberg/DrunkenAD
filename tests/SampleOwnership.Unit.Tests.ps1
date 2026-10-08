BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:sampleModule = Import-Module (Join-Path $script:root 'DrunkenAD/DrunkenAD.psd1') -Force -PassThru
    $script:configPath = Join-Path $script:root 'examples/data/drink-ingestion-config.json'
}

Describe 'Shipped CSV and projection namespace ownership' {
    It 'retains both maps when planning <Order>' -ForEach @(
        @{ Order = 'CSV then projection' },
        @{ Order = 'projection then CSV' }
    ) {
        & $script:sampleModule {
            param($ConfigPath, $Order)
            $config = Resolve-DrunkenADCsvNamespaceMap -ConfigPath $ConfigPath
            $row = [pscustomobject]@{ ProfileTier = 'Gold'; ProfileRegion = 'NA'; Flags = 'Enabled;Audited'; RoutingMailbox = 'Queue'; TenantId = 'Example'; SyncState = 'Synced' }
            $csv = ConvertTo-DrunkenADCsvDataMap -Row $row -Mappings @(Get-DrunkenADCsvMappings -NamespaceMap $config)
            $user = [pscustomobject]@{ samAccountName = 'sample'; userPrincipalName = 'sample@example.test'; employeeID = 'Example'; mail = 'sample@example.test'; pager = 'sample@example.test' }
            $projection = ConvertTo-DrunkenADProjectionDataMap -User $user -AttributeMap (Get-DrunkenADDefaultProjectionAttributeMap)
            $first = if ($Order -eq 'CSV then projection') { $csv } else { $projection }
            $second = if ($Order -eq 'CSV then projection') { $projection } else { $csv }
            $initial = Get-DrunkenADPrefixWritePlan -CurrentValues @('Keep-Stable') -PrefixMap $first -RangeUpper 256
            $final = Get-DrunkenADPrefixWritePlan -CurrentValues $initial.FinalDrinkValues -PrefixMap $second -RangeUpper 256
            $expected = @('Keep-Stable', 'CsvProfile-Tier=Gold', 'CsvProfile-Region=NA', 'CsvRouting-Mailbox=Queue', 'Flags-Enabled', 'Flags-Audited', 'Tenant-Id=Example', 'Sync-State=Synced', 'Profile-samAccountName=sample', 'Identity-userPrincipalName=sample@example.test', 'Meta-employeeID=Example', 'Routing-mail=sample@example.test', 'Notify-pager=sample@example.test')
            @($final.FinalDrinkValues | Sort-Object) | Should -Be ($expected | Sort-Object)
        } $script:configPath $Order
    }

    It 'has no literal prefix overlap across the shipped maps' {
        & $script:sampleModule {
            param($ConfigPath)
            $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
            $defaults = Get-DrunkenADDefaultProjectionAttributeMap
            $config.PSObject.Properties.Name | Should -Contain 'CsvProfile-'
            $config.PSObject.Properties.Name | Should -Contain 'CsvRouting-'
            $config.PSObject.Properties.Name | Should -Contain 'Flags-'
            foreach ($csvPrefix in $config.PSObject.Properties.Name) {
                foreach ($projectionPrefix in $defaults.Keys) {
                    $csvPrefix.StartsWith($projectionPrefix, [StringComparison]::OrdinalIgnoreCase) | Should -BeFalse
                    $projectionPrefix.StartsWith($csvPrefix, [StringComparison]::OrdinalIgnoreCase) | Should -BeFalse
                }
            }
        } $script:configPath
    }
}
