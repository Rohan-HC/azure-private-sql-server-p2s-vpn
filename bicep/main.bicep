targetScope = 'subscription'

@description('Dedicated resource group for the disposable CI/CD lab.')
param resourceGroupName string = 'rg-sqllab-cicd-dev'

param location string = 'swedencentral'
param namePrefix string = 'sqllab-cicd-dev'
param vmName string = 'vm-sqllab2-sql'
param vmSize string = 'Standard_D2as_v5'
param windowsAdminUsername string = 'labadmin'
param sqlAdminUsername string = 'sqladmin'
param databaseName string = 'AppDb'
param sqlPort int = 1433

param vnetAddressPrefix string = '10.60.0.0/16'
param workloadSubnetPrefix string = '10.60.1.0/24'
param privateEndpointSubnetPrefix string = '10.60.2.0/24'
param gatewaySubnetPrefix string = '10.60.255.0/27'
param vpnClientAddressPool string = '172.17.0.0/24'

@secure()
param windowsAdminPassword string

@secure()
param sqlAdminPassword string

@secure()
param vpnRootCertificatePublicData string

resource labResourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: {
    workload: 'private-sql-p2s-lab'
    lifecycle: 'disposable'
  }
}

module network './modules/network.bicep' = {
  name: 'network'
  scope: labResourceGroup
  params: {
    location: location
    namePrefix: namePrefix
    vnetAddressPrefix: vnetAddressPrefix
    workloadSubnetPrefix: workloadSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    gatewaySubnetPrefix: gatewaySubnetPrefix
    vpnClientAddressPool: vpnClientAddressPool
    sqlPort: sqlPort
  }
}

module keyVault './modules/keyvault.bicep' = {
  name: 'keyVault'
  scope: labResourceGroup
  params: {
    location: location
    namePrefix: namePrefix
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    vnetId: network.outputs.vnetId
    windowsAdminPassword: windowsAdminPassword
    sqlAdminPassword: sqlAdminPassword
    vpnRootCertificatePublicData: vpnRootCertificatePublicData
  }
}

module sqlVm './modules/sql-vm.bicep' = {
  name: 'sqlVm'
  scope: labResourceGroup
  params: {
    location: location
    namePrefix: namePrefix
    subnetId: network.outputs.workloadSubnetId
    vmName: vmName
    vmSize: vmSize
    adminUsername: windowsAdminUsername
    adminPassword: windowsAdminPassword
    sqlAdminUsername: sqlAdminUsername
    sqlAdminPassword: sqlAdminPassword
    sqlPort: sqlPort
  }
}

module vpnGateway './modules/vpn-gateway.bicep' = {
  name: 'vpnGateway'
  scope: labResourceGroup
  params: {
    location: location
    namePrefix: namePrefix
    gatewaySubnetId: network.outputs.gatewaySubnetId
    vpnClientAddressPool: vpnClientAddressPool
    rootCertificatePublicData: vpnRootCertificatePublicData
  }
}

module keyVaultRbac './modules/keyvault-rbac.bicep' = {
  name: 'keyVaultRbac'
  scope: labResourceGroup
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: sqlVm.outputs.vmPrincipalId
  }
}

module guestConfiguration './modules/vm-runcommand.bicep' = {
  name: 'guestConfiguration'
  scope: labResourceGroup
  params: {
    location: location
    vmName: sqlVm.outputs.vmName
    keyVaultUri: keyVault.outputs.keyVaultUri
    passwordSecretName: keyVault.outputs.sqlAdminVaultItemName
    sqlAdminUsername: sqlAdminUsername
    databaseName: databaseName
    sqlPort: sqlPort
    allowedSourceCidr: vpnClientAddressPool
  }
  dependsOn: [
    keyVaultRbac
  ]
}

output resourceGroupName string = labResourceGroup.name
output vmName string = sqlVm.outputs.vmName
output vmPrivateIpAddress string = sqlVm.outputs.privateIpAddress
output keyVaultName string = keyVault.outputs.keyVaultName
output vpnGatewayName string = vpnGateway.outputs.vpnGatewayName
output vpnGatewayPublicIp string = vpnGateway.outputs.vpnGatewayPublicIp
output natGatewayPublicIp string = network.outputs.natGatewayPublicIp
output vpnClientAddressPool string = vpnClientAddressPool
output databaseName string = databaseName
