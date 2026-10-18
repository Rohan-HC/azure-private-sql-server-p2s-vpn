$ErrorActionPreference = 'Stop'

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-BicepTemplate {
    param([string]$Path)
    $result = & az bicep build --file $Path --stdout 2>&1
    Assert-That ($LASTEXITCODE -eq 0) "Bicep module does not compile: $Path $($result -join ' ')"
    return ($result -join "`n" | ConvertFrom-Json)
}

$vault = Get-BicepTemplate (Join-Path $PSScriptRoot '..\bicep\modules\keyvault.bicep')
foreach ($name in @('windowsAdminPassword', 'sqlAdminPassword', 'vpnRootCertificatePublicData')) {
    Assert-That ($vault.parameters.$name.type -eq 'secureString') "$name is not a secure parameter"
}
$resources = @($vault.resources)
$keyVault = $resources | Where-Object type -eq 'Microsoft.KeyVault/vaults' | Select-Object -First 1
Assert-That ($null -ne $keyVault) 'Key Vault resource missing'
Assert-That ($keyVault.properties.publicNetworkAccess -eq 'Disabled') 'Key Vault public network access is not disabled'
Assert-That ($keyVault.properties.enableRbacAuthorization -eq $true) 'Key Vault RBAC authorization is not enabled'
$secrets = @($resources | Where-Object type -eq 'Microsoft.KeyVault/vaults/secrets')
foreach ($name in @('windows-admin-password', 'sql-admin-password', 'vpn-root-certificate')) {
    Assert-That ($null -ne ($secrets | Where-Object { $_.name -match $name } | Select-Object -First 1)) "Secret $name missing"
}
Assert-That ($null -ne ($resources | Where-Object type -eq 'Microsoft.Network/privateEndpoints' | Select-Object -First 1)) 'Vault private endpoint missing'
Assert-That ($null -ne ($resources | Where-Object type -eq 'Microsoft.Network/privateDnsZones' | Select-Object -First 1)) 'Vault private DNS zone missing'
Assert-That ($null -ne ($resources | Where-Object type -eq 'Microsoft.Network/privateDnsZones/virtualNetworkLinks' | Select-Object -First 1)) 'Vault VNet DNS link missing'
Assert-That ($null -ne ($resources | Where-Object type -eq 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups' | Select-Object -First 1)) 'Private endpoint DNS zone group missing'

$rbac = Get-BicepTemplate (Join-Path $PSScriptRoot '..\bicep\modules\keyvault-rbac.bicep')
$assignment = @($rbac.resources) | Where-Object type -eq 'Microsoft.Authorization/roleAssignments' | Select-Object -First 1
Assert-That ($null -ne $assignment) 'Managed identity role assignment missing'
Assert-That ($rbac.variables.secretsUserRoleId -eq '4633458b-17de-408a-b874-0445c86b69e6') 'Wrong Key Vault role selected'
Assert-That ($assignment.properties.roleDefinitionId -match 'secretsUserRoleId') 'Wrong Key Vault role assigned'
Assert-That ($assignment.properties.principalId -match 'principalId') 'Role is not assigned to the VM principal'
Assert-That ($assignment.scope -match 'Microsoft.KeyVault/vaults') 'Role assignment is not scoped to the Key Vault'

Write-Output 'Key Vault contract passed.'
