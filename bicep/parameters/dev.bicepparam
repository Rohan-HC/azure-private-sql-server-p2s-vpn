using '../main.bicep'

param resourceGroupName = 'rg-sqllab-cicd-dev'
param location = 'swedencentral'
param namePrefix = 'sqllab-cicd-dev'
param vmName = 'vm-sqllab2-sql'
param vmSize = 'Standard_D2as_v5'
param windowsAdminUsername = 'labadmin'
param sqlAdminUsername = 'sqladmin'
param databaseName = 'AppDb'
param windowsAdminPassword = readEnvironmentVariable('WINDOWS_ADMIN_PASSWORD')
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD')
param vpnRootCertificatePublicData = readEnvironmentVariable('VPN_ROOT_CERT_DATA')
