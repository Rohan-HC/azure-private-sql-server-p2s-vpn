[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$KeyVaultUri,
    [Parameter(Mandatory)][string]$PasswordSecretName,
    [Parameter(Mandatory)][string]$SqlAdminUsername,
    [Parameter(Mandatory)][string]$DatabaseName,
    [Parameter(Mandatory)][int]$SqlPort,
    [Parameter(Mandatory)][string]$AllowedSourceCidr
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($SqlAdminUsername -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,63}$') { throw 'Invalid SQL administrator login name.' }
if ($DatabaseName -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,127}$') { throw 'Invalid database name.' }
if ($SqlPort -lt 1 -or $SqlPort -gt 65535) { throw 'Invalid SQL port.' }
if ($AllowedSourceCidr -notmatch '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$') { throw 'Invalid P2S client CIDR.' }

function Quote-SqlIdentifier {
    param([string]$Value)
    return '[' + $Value.Replace(']', ']]') + ']'
}

function Invoke-Sql {
    param([string]$Query, [string]$Database = 'master', [switch]$Scalar)
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source'] = "localhost,$SqlPort"
    $builder['Initial Catalog'] = $Database
    $builder['User ID'] = $SqlAdminUsername
    $builder['Password'] = $sqlAdminPassword
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    $builder['Connect Timeout'] = 30
    $connection = New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 120
        if ($Scalar) { return $command.ExecuteScalar() }
        [void]$command.ExecuteNonQuery()
    }
    finally {
        $connection.Dispose()
    }
}

Write-Output 'Checking private Key Vault DNS resolution.'
$vaultHost = ([Uri]$KeyVaultUri).Host
$vaultAddress = $null
foreach ($attempt in 1..12) {
    try {
        $vaultAddress = [System.Net.Dns]::GetHostAddresses($vaultHost) |
            Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
            Select-Object -First 1 -ExpandProperty IPAddressToString
        if ($vaultAddress -match '^(10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)') { break }
        $vaultAddress = $null
    }
    catch { $vaultAddress = $null }
    if ($attempt -lt 12) { Start-Sleep -Seconds 10 }
}
if (-not $vaultAddress) { throw 'Key Vault did not resolve to a private IPv4 address.' }
Write-Output "Key Vault resolves privately to $vaultAddress."

Write-Output 'Acquiring VM managed identity token.'
$tokenUri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net'
$accessToken = $null
foreach ($attempt in 1..10) {
    try {
        $response = Invoke-RestMethod -Uri $tokenUri -Headers @{ Metadata = 'true' } -TimeoutSec 20
        $accessToken = $response.access_token
        if ($accessToken) { break }
    }
    catch { }
    if ($attempt -lt 10) { Start-Sleep -Seconds 10 }
}
if (-not $accessToken) { throw 'Managed identity token request failed after 10 attempts.' }

Write-Output 'Reading SQL password from Key Vault over the private endpoint.'
$secretUri = '{0}/secrets/{1}?api-version=7.4' -f $KeyVaultUri.TrimEnd('/'), $PasswordSecretName
$sqlAdminPassword = $null
foreach ($attempt in 1..12) {
    try {
        $secret = Invoke-RestMethod -Uri $secretUri -Headers @{ Authorization = "Bearer $accessToken" } -TimeoutSec 30
        $sqlAdminPassword = $secret.value
        if ($sqlAdminPassword) { break }
    }
    catch { }
    if ($attempt -lt 12) { Start-Sleep -Seconds 15 }
}
if (-not $sqlAdminPassword) { throw 'Key Vault secret read failed after 12 attempts.' }
Write-Output 'Managed identity secret read succeeded.'

Write-Output 'Checking SQL Server TCP and authentication settings.'
$instanceNames = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
$instanceId = $instanceNames.MSSQLSERVER
if (-not $instanceId) { throw 'Default SQL Server instance was not found.' }
$serverRegistry = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer"
$tcpRegistry = "$serverRegistry\SuperSocketNetLib\Tcp"
$ipAllRegistry = "$tcpRegistry\IPAll"
$settingsChanged = $false
if ((Get-ItemPropertyValue -Path $serverRegistry -Name LoginMode) -ne 2) {
    Set-ItemProperty -Path $serverRegistry -Name LoginMode -Value 2
    $settingsChanged = $true
}
if ((Get-ItemPropertyValue -Path $tcpRegistry -Name Enabled) -ne 1) {
    Set-ItemProperty -Path $tcpRegistry -Name Enabled -Value 1
    $settingsChanged = $true
}
if ((Get-ItemPropertyValue -Path $ipAllRegistry -Name TcpDynamicPorts) -ne '') {
    Set-ItemProperty -Path $ipAllRegistry -Name TcpDynamicPorts -Value ''
    $settingsChanged = $true
}
if ((Get-ItemPropertyValue -Path $ipAllRegistry -Name TcpPort) -ne [string]$SqlPort) {
    Set-ItemProperty -Path $ipAllRegistry -Name TcpPort -Value ([string]$SqlPort)
    $settingsChanged = $true
}

Write-Output 'Scoping Windows Firewall to P2S clients.'
$rules = @(
    @{ Name = 'SqlLab-Allow-SQL-P2S'; Protocol = 'TCP'; Port = $SqlPort },
    @{ Name = 'SqlLab-Allow-RDP-P2S'; Protocol = 'TCP'; Port = 3389 }
)
foreach ($spec in $rules) {
    $rule = Get-NetFirewallRule -Name $spec.Name -ErrorAction SilentlyContinue
    if ($rule) {
        $rule | Set-NetFirewallRule -Enabled True -RemoteAddress $AllowedSourceCidr
    }
    else {
        New-NetFirewallRule -Name $spec.Name -DisplayName $spec.Name -Direction Inbound -Action Allow `
            -Protocol $spec.Protocol -LocalPort $spec.Port -RemoteAddress $AllowedSourceCidr -Profile Any | Out-Null
    }
}
$icmpRule = Get-NetFirewallRule -Name 'SqlLab-Allow-ICMP-P2S' -ErrorAction SilentlyContinue
if ($icmpRule) {
    $icmpRule | Set-NetFirewallRule -Enabled True -RemoteAddress $AllowedSourceCidr
}
else {
    New-NetFirewallRule -Name 'SqlLab-Allow-ICMP-P2S' -DisplayName 'SqlLab-Allow-ICMP-P2S' `
        -Direction Inbound -Action Allow -Protocol ICMPv4 -IcmpType 8 `
        -RemoteAddress $AllowedSourceCidr -Profile Any | Out-Null
}

# A broad rule from the Marketplace image would bypass a scoped rule. Narrow any existing
# inbound allow rules for the SQL and RDP ports before completing configuration.
Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True |
    Get-NetFirewallPortFilter |
    Where-Object { $_.Protocol -eq 'TCP' -and $_.LocalPort -in @([string]$SqlPort, '3389') } |
    Get-NetFirewallRule |
    Set-NetFirewallRule -RemoteAddress $AllowedSourceCidr

if ($settingsChanged) { Restart-Service MSSQLSERVER -Force }
$ready = $false
foreach ($attempt in 1..30) {
    $service = Get-Service MSSQLSERVER -ErrorAction SilentlyContinue
    $listener = Get-NetTCPConnection -LocalPort $SqlPort -State Listen -ErrorAction SilentlyContinue
    if ($service.Status -eq 'Running' -and $listener) { $ready = $true; break }
    if ($attempt -lt 30) { Start-Sleep -Seconds 10 }
}
if (-not $ready) { throw 'SQL Server did not become ready on the configured TCP port.' }

Write-Output 'Reconciling SQL login and sample database.'
$login = Quote-SqlIdentifier $SqlAdminUsername
$database = Quote-SqlIdentifier $DatabaseName
$escapedPassword = $sqlAdminPassword.Replace("'", "''")
$escapedLogin = $SqlAdminUsername.Replace("'", "''")
$escapedDatabase = $DatabaseName.Replace("'", "''")
Invoke-Sql -Query @"
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$escapedLogin')
    ALTER LOGIN $login WITH PASSWORD = N'$escapedPassword';
ELSE
    CREATE LOGIN $login WITH PASSWORD = N'$escapedPassword', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
IF ISNULL(IS_SRVROLEMEMBER(N'sysadmin', N'$escapedLogin'), 0) <> 1
    ALTER SERVER ROLE [sysadmin] ADD MEMBER $login;
ALTER LOGIN [sa] DISABLE;
"@
if (-not (Invoke-Sql -Scalar -Query "SELECT DB_ID(N'$escapedDatabase')")) {
    Invoke-Sql -Query "CREATE DATABASE $database"
}
Invoke-Sql -Database $DatabaseName -Query @"
IF OBJECT_ID(N'dbo.HealthCheck', N'U') IS NULL
    CREATE TABLE dbo.HealthCheck (
        Id INT NOT NULL PRIMARY KEY,
        Note NVARCHAR(200) NOT NULL,
        CreatedAt DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
    );
IF NOT EXISTS (SELECT 1 FROM dbo.HealthCheck WHERE Id = 1)
    INSERT INTO dbo.HealthCheck (Id, Note) VALUES (1, N'Provisioned by Azure Run Command');
"@
$rowCount = Invoke-Sql -Database $DatabaseName -Scalar -Query 'SELECT COUNT(*) FROM dbo.HealthCheck'
Write-Output "SQL configuration succeeded. Health rows: $rowCount; TCP port: $SqlPort."
