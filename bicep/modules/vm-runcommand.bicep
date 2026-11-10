param location string = resourceGroup().location
param vmName string
param keyVaultUri string
param passwordSecretName string
param sqlAdminUsername string = 'sqladmin'
param databaseName string = 'AppDb'
param sqlPort int = 1433
param allowedSourceCidr string = '172.17.0.0/24'

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
}

resource configureSql 'Microsoft.Compute/virtualMachines/runCommands@2024-07-01' = {
  parent: vm
  name: 'Configure-SqlServer'
  location: location
  properties: {
    asyncExecution: false
    timeoutInSeconds: 1800
    treatFailureAsDeploymentFailure: true
    source: {
      script: loadTextContent('../scripts/Configure-SqlServer.ps1')
    }
    parameters: [
      {
        name: 'KeyVaultUri'
        value: keyVaultUri
      }
      {
        name: 'PasswordSecretName'
        value: passwordSecretName
      }
      {
        name: 'SqlAdminUsername'
        value: sqlAdminUsername
      }
      {
        name: 'DatabaseName'
        value: databaseName
      }
      {
        name: 'SqlPort'
        value: string(sqlPort)
      }
      {
        name: 'AllowedSourceCidr'
        value: allowedSourceCidr
      }
    ]
  }
}

output runCommandId string = configureSql.id
output provisioningState string = configureSql.properties.provisioningState
