
param location string = 'swedencentral'

@secure()
param rootCertificateData string

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: 'vnet-sqllab-dev'
}

resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: 'GatewaySubnet'
}

resource vpnPublicIP 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-sqllab-vpn'
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
  name: 'vpngw-sqllab-dev'
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation2'
    activeActive: false
    enableBgp: false

    sku: {
      name: 'VpnGw1AZ'
      tier: 'VpnGw1AZ'
    }

    ipConfigurations: [
      {
        name: 'gateway-ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: vpnPublicIP.id
          }
          subnet: {
            id: gatewaySubnet.id
          }
        }
      }
    ]

    vpnClientConfiguration: {
      vpnClientAddressPool: {
        addressPrefixes: [
          '172.16.0.0/24'
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
          name: 'P2SRootCert'
          properties: {
            publicCertData: rootCertificateData
          }
        }
      ]
    }
  }
}

output vpnGatewayName string = vpnGateway.name
