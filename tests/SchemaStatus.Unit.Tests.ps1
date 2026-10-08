$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '../DrunkenAD/DrunkenAD.psd1'
Import-Module $modulePath -Force -ErrorAction Stop

Describe 'Schema readiness inheritance and metadata' {
    BeforeAll {
        $script:SchemaStatusUnitOriginalFunctions = @{}
        $stubDefinitions = @{
            'Get-ADRootDSE' = {
                param($Server, $ErrorAction)
                throw 'Get-ADRootDSE test stub must be mocked.'
            }
            'Get-ADObject' = {
                param($SearchBase, $LDAPFilter, $Properties, $Server, $ErrorAction)
                throw 'Get-ADObject test stub must be mocked.'
            }
        }

        foreach ($functionName in $stubDefinitions.Keys) {
            $functionPath = 'Function:\global:{0}' -f $functionName
            $existingFunction = Get-Item -LiteralPath $functionPath -ErrorAction SilentlyContinue
            if ($existingFunction) {
                $script:SchemaStatusUnitOriginalFunctions[$functionName] = $existingFunction.ScriptBlock
            }
            Set-Item -LiteralPath $functionPath -Value $stubDefinitions[$functionName]
        }
    }

    AfterAll {
        foreach ($functionName in @('Get-ADRootDSE', 'Get-ADObject')) {
            $functionPath = 'Function:\global:{0}' -f $functionName
            if ($script:SchemaStatusUnitOriginalFunctions.ContainsKey($functionName)) {
                Set-Item -LiteralPath $functionPath -Value $script:SchemaStatusUnitOriginalFunctions[$functionName]
            }
            else {
                Remove-Item -LiteralPath $functionPath -ErrorAction SilentlyContinue
            }
        }
    }

    InModuleScope DrunkenAD {
        BeforeEach {
            function New-SchemaStatusTestClass {
                param([string]$Name, [hashtable]$Properties = @{})

                $values = @{
                    lDAPDisplayName = $Name
                    DistinguishedName = 'CN={0},{1}' -f $Name, $script:SchemaStatusNamingContext
                }
                foreach ($key in $Properties.Keys) {
                    $values[$key] = $Properties[$key]
                }
                $node = [pscustomobject]$values
                $script:SchemaStatusReferences['(&(objectClass=classSchema)(|(lDAPDisplayName={0})(cn={0})))' -f $Name] = $node
                $script:SchemaStatusReferences['(&(objectClass=classSchema)(distinguishedName={0}))' -f $node.DistinguishedName] = $node
                if ($Properties.ContainsKey('governsID')) {
                    $script:SchemaStatusReferences['(&(objectClass=classSchema)(governsID={0}))' -f $Properties['governsID']] = $node
                }
                return $node
            }
            $script:SchemaStatusNamingContext = 'CN=Schema,CN=Configuration,DC=contoso,DC=com'
            $script:SchemaStatusReferences = @{}
            $script:SchemaStatusRootDse = [pscustomobject]@{
                SchemaNamingContext = $script:SchemaStatusNamingContext
                dnsHostName = 'discovered.contoso.com'
            }
            $script:SchemaStatusDrink = [pscustomobject]@{
                lDAPDisplayName = 'drink'
                DistinguishedName = 'CN=Favourite-Drink,{0}' -f $script:SchemaStatusNamingContext
                attributeID = '0.9.2342.19200300.100.1.5'
                isDefunct = $false
                rangeUpper = 777
            }
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user'

            Mock Initialize-DrunkenADModule {}
            Mock Get-ADRootDSE { $script:SchemaStatusRootDse }
            Mock Get-ADObject {
                switch ($LDAPFilter) {
                    '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))' { return $script:SchemaStatusDrink }
                    '(&(objectClass=classSchema)(lDAPDisplayName=user))' { return $script:SchemaStatusUser }
                    default {
                        if ($script:SchemaStatusReferences.ContainsKey($LDAPFilter)) {
                            return $script:SchemaStatusReferences[$LDAPFilter]
                        }
                        throw "Unexpected schema query '$LDAPFilter'."
                    }
                }
            }
        }

        It 'accepts drink directly in <ListName>' -ForEach @(
            @{ ListName = 'mayContain' }
            @{ ListName = 'systemMayContain' }
            @{ ListName = 'mustContain' }
            @{ ListName = 'systemMustContain' }
        ) {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ $ListName = @('cn', 'DRINK') }

            $status = Get-DrunkenADDrinkAttributeStatus

            $status.Enabled | Should -BeTrue
            $status.AllowedOnUserClass | Should -BeTrue
            $status.ReadyForUserWrite | Should -BeTrue
            $status.BlockingReason | Should -BeNullOrEmpty
        }

        It 'inherits <ListName> through multiple superclasses' -ForEach @(
            @{ ListName = 'mayContain' }
            @{ ListName = 'systemMayContain' }
            @{ ListName = 'mustContain' }
            @{ ListName = 'systemMustContain' }
        ) {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ subClassOf = 'organizationalPerson' }
            New-SchemaStatusTestClass -Name 'organizationalPerson' -Properties @{ subClassOf = 'person' } | Out-Null
            New-SchemaStatusTestClass -Name 'person' -Properties @{ $ListName = @('drink') } | Out-Null

            (Get-DrunkenADDrinkAttributeStatus).ReadyForUserWrite | Should -BeTrue
        }

        It 'inherits <ListName> from <LinkName>' -ForEach @(
            @{ LinkName = 'auxiliaryClass'; ListName = 'mayContain' }
            @{ LinkName = 'auxiliaryClass'; ListName = 'systemMayContain' }
            @{ LinkName = 'auxiliaryClass'; ListName = 'mustContain' }
            @{ LinkName = 'auxiliaryClass'; ListName = 'systemMustContain' }
            @{ LinkName = 'systemAuxiliaryClass'; ListName = 'mayContain' }
            @{ LinkName = 'systemAuxiliaryClass'; ListName = 'systemMayContain' }
            @{ LinkName = 'systemAuxiliaryClass'; ListName = 'mustContain' }
            @{ LinkName = 'systemAuxiliaryClass'; ListName = 'systemMustContain' }
        ) {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ $LinkName = @('drinkAux') }
            New-SchemaStatusTestClass -Name 'drinkAux' -Properties @{ $ListName = @('drink') } | Out-Null

            (Get-DrunkenADDrinkAttributeStatus).ReadyForUserWrite | Should -BeTrue
        }

        It 'follows inherited auxiliary classes, their superclasses, and nested auxiliary classes' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ subClassOf = 'person' }
            New-SchemaStatusTestClass -Name 'person' -Properties @{ auxiliaryClass = @('outerAux') } | Out-Null
            New-SchemaStatusTestClass -Name 'outerAux' -Properties @{ subClassOf = 'baseAux' } | Out-Null
            New-SchemaStatusTestClass -Name 'baseAux' -Properties @{ systemAuxiliaryClass = @('drinkAux') } | Out-Null
            New-SchemaStatusTestClass -Name 'drinkAux' -Properties @{ mustContain = @('drink') } | Out-Null

            (Get-DrunkenADDrinkAttributeStatus).ReadyForUserWrite | Should -BeTrue
        }

        It 'resolves class references represented as <ReferenceKind>' -ForEach @(
            @{ ReferenceKind = 'LDAP name' }
            @{ ReferenceKind = 'DN' }
            @{ ReferenceKind = 'OID' }
            @{ ReferenceKind = 'CN' }
        ) {
            $parent = New-SchemaStatusTestClass -Name 'person' -Properties @{ governsID = '2.5.6.6'; mayContain = @('drink') }
            $reference = switch ($ReferenceKind) {
                'LDAP name' { 'PERSON' }
                'DN' { $parent.DistinguishedName.ToUpperInvariant() }
                'OID' { '2.5.6.6' }
                'CN' {
                    $script:SchemaStatusReferences['(&(objectClass=classSchema)(|(lDAPDisplayName=Person-Class)(cn=Person-Class)))'] = $parent
                    'Person-Class'
                }
            }
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ subClassOf = $reference }

            (Get-DrunkenADDrinkAttributeStatus).ReadyForUserWrite | Should -BeTrue
        }

        It 'recognizes drink attribute references represented as <ReferenceKind>' -ForEach @(
            @{ ReferenceKind = 'LDAP name' }
            @{ ReferenceKind = 'DN' }
            @{ ReferenceKind = 'OID' }
        ) {
            $reference = switch ($ReferenceKind) {
                'LDAP name' { 'DRINK' }
                'DN' { $script:SchemaStatusDrink.DistinguishedName.ToUpperInvariant() }
                'OID' { $script:SchemaStatusDrink.attributeID }
            }
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ systemMustContain = @($reference) }

            (Get-DrunkenADDrinkAttributeStatus).ReadyForUserWrite | Should -BeTrue
        }

        It 'does not confuse a similarly named attribute with drink' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ mayContain = @('otherDrink', 'drinkSuffix', '0.9.2342.19200300.100.1.50') }

            (Get-DrunkenADDrinkAttributeStatus).ReadyForUserWrite | Should -BeFalse
        }

        It 'accepts the special top superclass self-reference as <ReferenceKind>' -ForEach @(
            @{ ReferenceKind = 'LDAP name' }
            @{ ReferenceKind = 'DN' }
            @{ ReferenceKind = 'OID' }
        ) {
            $topReference = switch ($ReferenceKind) {
                'LDAP name' { 'top' }
                'DN' { 'CN=top,{0}' -f $script:SchemaStatusNamingContext }
                'OID' { '2.5.6.0' }
            }
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ subClassOf = 'top' }
            New-SchemaStatusTestClass -Name 'top' -Properties @{ subClassOf = $topReference; governsID = '2.5.6.0'; mayContain = @('drink') } | Out-Null

            (Get-DrunkenADDrinkAttributeStatus).ReadyForUserWrite | Should -BeTrue
        }

        It 'handles shared ancestors without confusing a diamond with a cycle' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ subClassOf = 'person'; auxiliaryClass = @('drinkAux', 'DRINKAUX') }
            New-SchemaStatusTestClass -Name 'person' -Properties @{ subClassOf = 'top' } | Out-Null
            New-SchemaStatusTestClass -Name 'drinkAux' -Properties @{ subClassOf = 'top'; mayContain = @('drink') } | Out-Null
            New-SchemaStatusTestClass -Name 'top' -Properties @{ subClassOf = 'top' } | Out-Null

            (Get-DrunkenADDrinkAttributeStatus).ReadyForUserWrite | Should -BeTrue
            Assert-MockCalled Get-ADObject -Times 1 -Exactly -ParameterFilter {
                $LDAPFilter -eq '(&(objectClass=classSchema)(|(lDAPDisplayName=top)(cn=top)))'
            }
            Assert-MockCalled Get-ADObject -Times 1 -Exactly -ParameterFilter {
                $LDAPFilter -eq '(&(objectClass=classSchema)(|(lDAPDisplayName=drinkAux)(cn=drinkAux)))'
            }
        }

        It 'rejects a superclass cycle even when drink is directly allowed' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ mayContain = @('drink'); subClassOf = 'person' }
            New-SchemaStatusTestClass -Name 'person' -Properties @{ subClassOf = $script:SchemaStatusUser.DistinguishedName.ToUpperInvariant() } | Out-Null

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*cycle*'
        }

        It 'rejects a non-top superclass self-cycle' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ mayContain = @('drink'); subClassOf = 'user' }

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*cycle*'
        }

        It 'rejects cycles through auxiliary and system auxiliary links' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ auxiliaryClass = @('outerAux') }
            New-SchemaStatusTestClass -Name 'outerAux' -Properties @{ systemAuxiliaryClass = @('innerAux'); mayContain = @('drink') } | Out-Null
            New-SchemaStatusTestClass -Name 'innerAux' -Properties @{ auxiliaryClass = @('outerAux') } | Out-Null

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*cycle*'
        }

        It 'does not exempt top auxiliary self-cycles' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ subClassOf = 'top' }
            New-SchemaStatusTestClass -Name 'top' -Properties @{ auxiliaryClass = @('top'); mayContain = @('drink') } | Out-Null

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*cycle*'
        }

        It 'rejects a missing <LinkName> node even after finding drink' -ForEach @(
            @{ LinkName = 'subClassOf' }
            @{ LinkName = 'auxiliaryClass' }
            @{ LinkName = 'systemAuxiliaryClass' }
        ) {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ mayContain = @('drink'); $LinkName = 'missing' }
            $script:SchemaStatusReferences['(&(objectClass=classSchema)(|(lDAPDisplayName=missing)(cn=missing)))'] = @()

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*could not be resolved*'
        }

        It 'rejects an ambiguous <LinkName> node even after finding drink' -ForEach @(
            @{ LinkName = 'subClassOf' }
            @{ LinkName = 'auxiliaryClass' }
            @{ LinkName = 'systemAuxiliaryClass' }
        ) {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ mayContain = @('drink'); $LinkName = 'duplicate' }
            $first = New-SchemaStatusTestClass -Name 'first'
            $second = New-SchemaStatusTestClass -Name 'second'
            $script:SchemaStatusReferences['(&(objectClass=classSchema)(|(lDAPDisplayName=duplicate)(cn=duplicate)))'] = @($first, $second)

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*ambiguous*'
        }

        It 'rejects empty references, multiple superclasses, and unidentifiable nodes' -ForEach @(
            @{ Malformation = 'empty'; Message = '*empty*reference*' }
            @{ Malformation = 'multiple'; Message = '*multiple subClassOf*' }
            @{ Malformation = 'no DN'; Message = '*no distinguished name*' }
        ) {
            switch ($Malformation) {
                'empty' { $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ auxiliaryClass = @(' ') } }
                'multiple' { $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ subClassOf = @('person', 'top') } }
                'no DN' { $script:SchemaStatusUser = [pscustomobject]@{ lDAPDisplayName = 'user'; mayContain = @('drink') } }
            }

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw $Message
        }

        It 'escapes schema reference values in LDAP filters' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ auxiliaryClass = @('aux*(test)\name') }
            $node = New-SchemaStatusTestClass -Name 'aux' -Properties @{ mayContain = @('drink') }
            $script:SchemaStatusReferences['(&(objectClass=classSchema)(|(lDAPDisplayName=aux\2a\28test\29\5cname)(cn=aux\2a\28test\29\5cname)))'] = $node

            (Get-DrunkenADDrinkAttributeStatus).ReadyForUserWrite | Should -BeTrue
        }

        It 'pins every schema query to the discovered DC including inherited classes' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ subClassOf = 'person' }
            New-SchemaStatusTestClass -Name 'person' -Properties @{ mayContain = @('drink') } | Out-Null

            $status = Get-DrunkenADDrinkAttributeStatus

            $status.Server | Should -Be 'discovered.contoso.com'
            Assert-MockCalled Get-ADRootDSE -Times 1 -Exactly -ParameterFilter { [string]::IsNullOrEmpty($Server) }
            Assert-MockCalled Get-ADObject -Times 3 -Exactly -ParameterFilter {
                $Server -eq 'discovered.contoso.com' -and $SearchBase -eq 'CN=Schema,CN=Configuration,DC=contoso,DC=com'
            }
        }

        It 'preserves an explicit server including its port without requiring dnsHostName' {
            $script:SchemaStatusRootDse.PSObject.Properties.Remove('dnsHostName')

            $status = Get-DrunkenADDrinkAttributeStatus -Server 'explicit.contoso.com:50000'

            $status.Server | Should -Be 'explicit.contoso.com:50000'
            Assert-MockCalled Get-ADRootDSE -Times 1 -Exactly -ParameterFilter { $Server -eq 'explicit.contoso.com:50000' }
            Assert-MockCalled Get-ADObject -Times 2 -Exactly -ParameterFilter { $Server -eq 'explicit.contoso.com:50000' }
        }

        It 'fails before schema queries when discovered dnsHostName is <HostnameState>' -ForEach @(
            @{ HostnameState = 'missing' }
            @{ HostnameState = 'null' }
            @{ HostnameState = 'blank' }
        ) {
            switch ($HostnameState) {
                'missing' { $script:SchemaStatusRootDse.PSObject.Properties.Remove('dnsHostName') }
                'null' { $script:SchemaStatusRootDse.dnsHostName = $null }
                'blank' { $script:SchemaStatusRootDse.dnsHostName = ' ' }
            }

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*dnsHostName*'
            Assert-MockCalled Get-ADObject -Times 0
        }

        It 'fails before schema queries when the schema naming context is missing' {
            $script:SchemaStatusRootDse.PSObject.Properties.Remove('SchemaNamingContext')

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*schema naming context*'
            Assert-MockCalled Get-ADObject -Times 0
        }

        It 'returns the actual rangeUpper <Limit> without a fixed default' -ForEach @(
            @{ Limit = 42 }
            @{ Limit = 777 }
            @{ Limit = 0 }
            @{ Limit = '1024' }
            @{ Limit = @(8192) }
        ) {
            $script:SchemaStatusDrink.rangeUpper = $Limit

            $status = Get-DrunkenADDrinkAttributeStatus

            $status.RangeUpper | Should -Be ([int]@($Limit)[0])
            $status.RangeUpper | Should -BeOfType ([int])
            Assert-MockCalled Get-ADObject -Times 1 -Exactly -ParameterFilter {
                $LDAPFilter -eq '(&(objectClass=attributeSchema)(lDAPDisplayName=drink))' -and
                $Properties -contains 'rangeUpper' -and $Properties -contains 'attributeID'
            }
        }

        It 'leaves absent or empty rangeUpper unknown' -ForEach @(
            @{ MetadataState = 'missing' }
            @{ MetadataState = 'null' }
            @{ MetadataState = 'empty collection' }
        ) {
            switch ($MetadataState) {
                'missing' { $script:SchemaStatusDrink.PSObject.Properties.Remove('rangeUpper') }
                'null' { $script:SchemaStatusDrink.rangeUpper = $null }
                'empty collection' { $script:SchemaStatusDrink.rangeUpper = @() }
            }

            (Get-DrunkenADDrinkAttributeStatus).RangeUpper | Should -BeNullOrEmpty
        }

        It 'rejects malformed rangeUpper metadata <Limit>' -ForEach @(
            @{ Limit = -1 }
            @{ Limit = 'not a number' }
            @{ Limit = '2.5' }
            @{ Limit = '2147483648' }
            @{ Limit = @(42, 777) }
        ) {
            $script:SchemaStatusDrink.rangeUpper = $Limit

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*invalid rangeUpper*'
        }

        It 'tolerates sparse optional schema properties under strict mode' {
            $script:SchemaStatusDrink = [pscustomobject]@{ DistinguishedName = 'CN=Drink,{0}' -f $script:SchemaStatusNamingContext }
            $script:SchemaStatusUser = [pscustomobject]@{ DistinguishedName = 'CN=User,{0}' -f $script:SchemaStatusNamingContext; mayContain = @('drink') }

            $status = Get-DrunkenADDrinkAttributeStatus -Server 'explicit.contoso.com'

            $status.ReadyForUserWrite | Should -BeTrue
            $status.IsDefunct | Should -BeFalse
            $status.RangeUpper | Should -BeNullOrEmpty
        }

        It 'treats null optional class properties as absent under strict mode' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{
                mayContain = @('drink')
                systemMayContain = $null
                mustContain = $null
                systemMustContain = $null
                subClassOf = $null
                auxiliaryClass = $null
                systemAuxiliaryClass = $null
            }

            (Get-DrunkenADDrinkAttributeStatus).ReadyForUserWrite | Should -BeTrue
        }

        It 'propagates schema query failures instead of accepting a partial graph' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ mayContain = @('drink'); subClassOf = 'person' }
            Mock Get-ADObject { throw 'Simulated schema lookup failure.' } -ParameterFilter {
                $LDAPFilter -eq '(&(objectClass=classSchema)(|(lDAPDisplayName=person)(cn=person)))'
            }

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*Simulated schema lookup failure*'
        }

        It 'preserves all existing status fields and not-allowed semantics' {
            $status = Get-DrunkenADDrinkAttributeStatus

            $status.PSObject.Properties.Name | Should -Contain 'Server'
            $status.Enabled | Should -BeTrue
            $status.IsDefunct | Should -BeFalse
            $status.DistinguishedName | Should -Be $script:SchemaStatusDrink.DistinguishedName
            $status.AttributeDistinguishedName | Should -Be $status.DistinguishedName
            $status.SchemaNamingContext | Should -Be $script:SchemaStatusNamingContext
            $status.UserClassDistinguishedName | Should -Be $script:SchemaStatusUser.DistinguishedName
            $status.AllowedOnUserClass | Should -BeFalse
            $status.ReadyForUserWrite | Should -BeFalse
            $status.BlockingReason | Should -Be 'NotAllowedOnUserClass'
            $status.BlockingMessage | Should -BeLike '*not allowed on the Active Directory user class*'
        }

        It 'preserves missing and defunct attribute status' -ForEach @(
            @{ AttributeState = 'missing'; BlockingReason = 'AttributeMissing' }
            @{ AttributeState = 'defunct'; BlockingReason = 'AttributeDefunct' }
        ) {
            if ($AttributeState -eq 'missing') { $script:SchemaStatusDrink = $null }
            else { $script:SchemaStatusDrink.isDefunct = $true }

            $status = Get-DrunkenADDrinkAttributeStatus

            $status.Enabled | Should -BeFalse
            $status.AllowedOnUserClass | Should -BeFalse
            $status.ReadyForUserWrite | Should -BeFalse
            $status.BlockingReason | Should -Be $BlockingReason
        }

        It 'rejects ambiguous initial <Node> lookup results' -ForEach @(
            @{ Node = 'attribute' }
            @{ Node = 'user class' }
        ) {
            if ($Node -eq 'attribute') { $script:SchemaStatusDrink = @($script:SchemaStatusDrink, $script:SchemaStatusDrink) }
            else { $script:SchemaStatusUser = @($script:SchemaStatusUser, $script:SchemaStatusUser) }

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*ambiguous*'
        }

        It 'rejects a missing user class' {
            $script:SchemaStatusUser = @()

            { Get-DrunkenADDrinkAttributeStatus } | Should -Throw '*user class could not be resolved*'
        }

        It 'requests the complete class inheritance and attribute lists' {
            Get-DrunkenADDrinkAttributeStatus | Out-Null

            Assert-MockCalled Get-ADObject -Times 1 -Exactly -ParameterFilter {
                $LDAPFilter -eq '(&(objectClass=classSchema)(lDAPDisplayName=user))' -and
                $Properties -contains 'mayContain' -and $Properties -contains 'systemMayContain' -and
                $Properties -contains 'mustContain' -and $Properties -contains 'systemMustContain' -and
                $Properties -contains 'subClassOf' -and $Properties -contains 'auxiliaryClass' -and
                $Properties -contains 'systemAuxiliaryClass'
            }
        }

        It 'keeps both private assertions silent on success' {
            $script:SchemaStatusUser = New-SchemaStatusTestClass -Name 'user' -Properties @{ mustContain = @('drink') }

            @(Assert-ADDrinkAttributeEnabled -Server 'explicit.contoso.com').Count | Should -Be 0
            @(Assert-ADDrinkAttributeReadyForUserWrite -Server 'explicit.contoso.com').Count | Should -Be 0
        }

        It 'keeps the private presence assertion distinct from write readiness' {
            { Assert-ADDrinkAttributeEnabled -Server 'explicit.contoso.com' } | Should -Not -Throw
            { Assert-ADDrinkAttributeReadyForUserWrite -Server 'explicit.contoso.com' } | Should -Throw '*not allowed on the Active Directory user class*'
        }

        It 'keeps the private presence assertion blocking absent attributes' {
            $script:SchemaStatusDrink = $null

            { Assert-ADDrinkAttributeEnabled -Server 'explicit.contoso.com' } | Should -Throw '*not enabled*'
        }
    }
}
