param location string = resourceGroup().location
param namePrefix string = 'sqllab-cicd-dev'
param vnetAddressPrefix string = '10.60.0.0/16'
param workloadSubnetPrefix string = '10.60.1.0/24'
param privateEndpointSubnetPrefix string = '10.60.2.0/24'
param gatewaySubnetPrefix string = '10.60.255.0/27'
param vpnClientAddressPool string = '172.17.0.0/24'
param sqlPort int = 1433
param deployVpnGateway bool = true

resource natPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${namePrefix}-nat-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2024-05-01' = {
  name: '${namePrefix}-nat'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: natPublicIp.id
      }
    ]
  }
}

resource workloadNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-workload-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SQL-From-P2S'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: string(sqlPort)
          sourceAddressPrefix: vpnClientAddressPool
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Allow-RDP-From-P2S'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: vpnClientAddressPool
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'Allow-ICMP-From-P2S'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: vpnClientAddressPool
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${namePrefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

resource workloadSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'snet-workload'
  properties: {
    addressPrefix: workloadSubnetPrefix
    networkSecurityGroup: {
      id: workloadNsg.id
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
    addressPrefix: privateEndpointSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = if (deployVpnGateway) {
  parent: vnet
  name: 'GatewaySubnet'
  properties: {
    addressPrefix: gatewaySubnetPrefix
  }
}

output vnetId string = vnet.id
output workloadSubnetId string = workloadSubnet.id
output privateEndpointSubnetId string = privateEndpointSubnet.id
output gatewaySubnetId string = deployVpnGateway ? gatewaySubnet!.id : ''
output natGatewayPublicIp string = natPublicIp.properties.ipAddress
output nsgId string = workloadNsg.id
