$ErrorActionPreference = 'Stop'

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-CidrRange {
    param([string]$Cidr)
    $address, $prefix = $Cidr.Split('/')
    $bytes = [System.Net.IPAddress]::Parse($address).GetAddressBytes()
    [Array]::Reverse($bytes)
    $value = [BitConverter]::ToUInt32($bytes, 0)
    $hostBits = 32 - [int]$prefix
    $mask = if ($hostBits -eq 32) { [uint64]0 } else { ([uint64]::MaxValue -shl $hostBits) -band [uint64]4294967295 }
    $start = [uint64]$value -band $mask
    $end = $start + ([uint64][Math]::Pow(2, $hostBits) - 1)
    return @($start, $end)
}

function Test-CidrOverlap {
    param([string]$Left, [string]$Right)
    $a = Get-CidrRange $Left
    $b = Get-CidrRange $Right
    return $a[0] -le $b[1] -and $b[0] -le $a[1]
}

Assert-That (Test-CidrOverlap '10.50.0.0/16' '10.50.1.0/24') 'CIDR helper missed a contained subnet'
Assert-That (-not (Test-CidrOverlap '10.50.0.0/16' '10.60.0.0/16')) 'CIDR helper reported a false overlap'

$templatePath = Join-Path $PSScriptRoot '..\bicep\modules\network.bicep'
$json = & az bicep build --file $templatePath --stdout 2>&1
Assert-That ($LASTEXITCODE -eq 0) "Network module does not compile: $($json -join ' ')"
$template = $json -join "`n" | ConvertFrom-Json

$expected = @{
    vnetAddressPrefix = '10.60.0.0/16'
    workloadSubnetPrefix = '10.60.1.0/24'
    privateEndpointSubnetPrefix = '10.60.2.0/24'
    gatewaySubnetPrefix = '10.60.255.0/27'
    vpnClientAddressPool = '172.17.0.0/24'
}
foreach ($name in $expected.Keys) {
    Assert-That ($template.parameters.$name.defaultValue -eq $expected[$name]) "$name default is wrong"
}
Assert-That ($template.parameters.sqlPort.defaultValue -eq 1433) 'SQL port default is wrong'
Assert-That (-not (Test-CidrOverlap $expected.vnetAddressPrefix '10.50.0.0/16')) 'New VNet overlaps the original lab'
Assert-That (-not (Test-CidrOverlap $expected.vpnClientAddressPool '172.16.0.0/24')) 'New VPN pool overlaps the original lab'

$resources = @($template.resources)
$nsg = $resources | Where-Object type -eq 'Microsoft.Network/networkSecurityGroups' | Select-Object -First 1
Assert-That ($null -ne $nsg) 'Workload NSG missing'
$rules = @($nsg.properties.securityRules)
foreach ($port in @('sqlPort', '3389')) {
    $rule = $rules | Where-Object { $_.properties.destinationPortRange -match $port } | Select-Object -First 1
    Assert-That ($null -ne $rule) "Inbound port $port rule missing"
    Assert-That ($rule.properties.sourceAddressPrefix -match 'vpnClientAddressPool') "Inbound port $port is not scoped to VPN clients"
    Assert-That ($rule.properties.direction -eq 'Inbound' -and $rule.properties.access -eq 'Allow') "Inbound port $port rule is not an allow rule"
}
$icmp = $rules | Where-Object { $_.properties.protocol -eq 'Icmp' } | Select-Object -First 1
Assert-That ($null -ne $icmp) 'ICMP rule missing'
Assert-That ($icmp.properties.sourceAddressPrefix -match 'vpnClientAddressPool') 'ICMP rule is not scoped to VPN clients'

$subnets = @($resources | Where-Object type -eq 'Microsoft.Network/virtualNetworks/subnets')
$workload = $subnets | Where-Object { $_.name -match 'snet-workload' } | Select-Object -First 1
Assert-That ($null -ne $workload) 'Workload subnet missing'
Assert-That ($null -ne $workload.properties.natGateway) 'Workload subnet lacks NAT Gateway association'
$gateway = $subnets | Where-Object { $_.name -match 'GatewaySubnet' } | Select-Object -First 1
Assert-That ($null -ne $gateway -and $null -ne $gateway.condition) 'Gateway subnet is not conditional'

Write-Output 'Network contract passed.'
