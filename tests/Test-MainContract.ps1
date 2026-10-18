$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$mainPath = Join-Path $root 'bicep/main.bicep'
$paramsPath = Join-Path $root 'bicep/parameters/dev.bicepparam'
$ignorePath = Join-Path $root '.gitignore'

foreach ($path in @($mainPath, $paramsPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing deployment entry point: $path" }
}

$main = Get-Content -LiteralPath $mainPath -Raw
$parameters = Get-Content -LiteralPath $paramsPath -Raw
$ignore = Get-Content -LiteralPath $ignorePath -Raw

foreach ($required in @(
    "targetScope = 'subscription'",
    "'rg-sqllab-cicd-dev'",
    "@secure()`nparam windowsAdminPassword string",
    "@secure()`nparam sqlAdminPassword string",
    "@secure()`nparam vpnRootCertificatePublicData string",
    "module network './modules/network.bicep'",
    "module keyVault './modules/keyvault.bicep'",
    "module sqlVm './modules/sql-vm.bicep'",
    "module vpnGateway './modules/vpn-gateway.bicep'",
    "module keyVaultRbac './modules/keyvault-rbac.bicep'",
    "module guestConfiguration './modules/vm-runcommand.bicep'",
    'network.outputs.workloadSubnetId',
    'network.outputs.privateEndpointSubnetId',
    'network.outputs.gatewaySubnetId',
    'sqlVm.outputs.vmPrincipalId',
    'keyVault.outputs.sqlAdminVaultItemName',
    'keyVaultRbac'
)) {
    if (-not $main.Contains($required)) { throw "Main Bicep missing $required" }
}

foreach ($prefix in @('10.60.0.0/16', '10.60.1.0/24', '10.60.2.0/24', '10.60.255.0/27', '172.17.0.0/24')) {
    if (-not $main.Contains($prefix)) { throw "Missing planned CIDR $prefix" }
}

if ($main.Contains('rg-sqllab-personal') -or $parameters.Contains('rg-sqllab-personal')) { throw 'Deployment references the existing lab.' }
foreach ($name in @('WINDOWS_ADMIN_PASSWORD', 'SQL_ADMIN_PASSWORD', 'VPN_ROOT_CERT_DATA')) {
    if (-not $parameters.Contains("readEnvironmentVariable('$name')")) { throw "Parameter file must read $name from environment." }
}
foreach ($pattern in @('/certs/', '/bicep/**/*.json', '/vpn-client-profiles/')) {
    if (-not $ignore.Contains($pattern)) { throw "Missing ignore pattern $pattern" }
}
Write-Output 'Full deployment contract passed.'
