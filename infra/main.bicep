param location string = resourceGroup().location
// 1. Create the main private network
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-sqllab-dev'
  location: location
  properties: {
    privateEndpointVNetPolicies: 'Disabled'
    addressSpace: {
      addressPrefixes: [
        '10.50.0.0/16'
      ]
    }
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-sqllab-workload'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SQL-From-VPN'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: '172.16.0.0/24'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}


// Public IP used for outbound traffic
resource egressPublicIP 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-sqllab-egress'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// NAT Gateway
resource natGateway 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'nat-sqllab-dev'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: egressPublicIP.id
      }
    ]
  }
}


resource workloadSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'snet-workload'
  properties: {
    addressPrefix: '10.50.1.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
    networkSecurityGroup: {
      id: nsg.id
    }
    natGateway: {
      id: natGateway.id
    }
  }
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'snet-private-endpoints'
  properties: {
    addressPrefix: '10.50.2.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'GatewaySubnet'
  properties: {
    addressPrefix: '10.50.255.0/27'
    privateEndpointNetworkPolicies: 'Disabled'
  }
}
output vnetName string = vnet.name
output workloadSubnetId string = workloadSubnet.id
