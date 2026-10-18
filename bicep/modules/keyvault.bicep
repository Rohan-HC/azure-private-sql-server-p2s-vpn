param location string = resourceGroup().location
param namePrefix string = 'sqllab-cicd-dev'
param privateEndpointSubnetId string
param vnetId string

@secure()
param windowsAdminPassword string

@secure()
param sqlAdminPassword string

@secure()
param vpnRootCertificatePublicData string = ''

var vaultName = take('${replace(namePrefix, '-', '')}kv${uniqueString(resourceGroup().id)}', 24)

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: vaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    enabledForTemplateDeployment: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
  }
}

resource windowsPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'windows-admin-password'
  properties: {
    value: windowsAdminPassword
    attributes: {
      enabled: true
    }
  }
}

resource sqlPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'sql-admin-password'
  properties: {
    value: sqlAdminPassword
    attributes: {
      enabled: true
    }
  }
}

resource vpnRootSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = if (!empty(vpnRootCertificatePublicData)) {
  parent: keyVault
  name: 'vpn-root-certificate'
  properties: {
    value: vpnRootCertificatePublicData
    attributes: {
      enabled: true
    }
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}

resource privateDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: '${namePrefix}-kv-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${namePrefix}-kv-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${namePrefix}-kv-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource privateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vault-dns'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateDnsLink
  ]
}

output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output sqlAdminVaultItemName string = sqlPasswordSecret.name
output windowsAdminVaultItemName string = windowsPasswordSecret.name
output vpnRootVaultItemName string = 'vpn-root-certificate'
output privateEndpointId string = privateEndpoint.id
