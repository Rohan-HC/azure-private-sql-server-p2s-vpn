param location string = resourceGroup().location
param namePrefix string = 'sqllab-cicd-dev'
param gatewaySubnetId string
param vpnClientAddressPool string = '172.17.0.0/24'
param gatewaySku string = 'VpnGw1AZ'

@secure()
param rootCertificatePublicData string

resource gatewayPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${namePrefix}-vpn-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: '${namePrefix}-vpngw'
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation2'
    activeActive: false
    enableBgp: false
    sku: {
      name: gatewaySku
      tier: gatewaySku
    }
    ipConfigurations: [
      {
        name: 'gateway-ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: gatewayPublicIp.id
          }
          subnet: {
            id: gatewaySubnetId
          }
        }
      }
    ]
    vpnClientConfiguration: {
      vpnClientAddressPool: {
        addressPrefixes: [
          vpnClientAddressPool
        ]
      }
      vpnClientProtocols: [
        'OpenVPN'
      ]
      vpnAuthenticationTypes: [
        'Certificate'
      ]
      vpnClientRootCertificates: [
        {
          name: 'SqlLabCicdRoot'
          properties: {
            publicCertData: rootCertificatePublicData
          }
        }
      ]
    }
  }
}

output vpnGatewayName string = vpnGateway.name
output vpnGatewayPublicIp string = gatewayPublicIp.properties.ipAddress
