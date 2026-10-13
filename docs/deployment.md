# Deployment Runbook (Windows PowerShell + Azure CLI)

> **Prerequisite:** The original local Bicep sources are required: `infra/main.bicep`, `infra/sql-vm.bicep`, `infra/vpn-gateway.bicep`. They are **not contained** in this documentation ZIP. Confirm their actual parameter declarations before changing commands.

## 1. Prerequisites

- Azure subscription permitted to provision Microsoft.Compute and Microsoft.Network resources.
- Available VM SKU and sufficient regional/family vCPU quota.
- Azure CLI and Bicep (`az bicep version`), Windows PowerShell 5.1+ or PowerShell 7.
- Azure VPN Client for Windows and Microsoft SQL Server Management Studio (SSMS).
- Local P2S root/client certificate pair; public root certificate data saved locally in `certs/P2SRootCert.base64.txt`. Keep the **client private key** out of Git.
- Sufficient budget for running VM, NAT Gateway, public IP, VPN Gateway and OS disk.

## 2. Select subscription and verify Azure quota

```powershell
Set-Location "C:\Users\rohan\Desktop\azure-private-sql-lab"
az login
az account list --output table
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
az account show --query "{Name:name,Subscription:id}" -o table

az provider show --namespace Microsoft.Compute --query registrationState -o tsv
az provider show --namespace Microsoft.Network --query registrationState -o tsv
# Register if necessary:
# az provider register --namespace Microsoft.Compute --wait
# az provider register --namespace Microsoft.Network --wait

az vm list-skus --location swedencentral --resource-type virtualMachines --size Standard_D2as_v5 -o table
az vm list-usage --location swedencentral -o table
```

The personal-subscription deployment used `Standard_D2as_v5`. Previous `Standard_D2as_v4` was restricted in Sweden Central. A SKU listing doesn't guarantee physical capacity or deployment permission.

## 3. Compile and review Bicep

```powershell
az bicep build --file .\infra\main.bicep
az bicep build --file .\infra\sql-vm.bicep
az bicep build --file .\infra\vpn-gateway.bicep
```

The existing templates are expected to target Sweden Central via their resource-group location or parameters. Check this against the real templates.

## 4. Create the resource group and network

```powershell
az group create --name rg-sqllab-personal --location swedencentral

az deployment group what-if `
  --resource-group rg-sqllab-personal `
  --template-file .\infra\main.bicep

# Billable NAT Gateway and public IP resources are created by this step:
az deployment group create `
  --name personal-network-dev `
  --resource-group rg-sqllab-personal `
  --template-file .\infra\main.bicep `
  --output table
```

Expected: deployment `Succeeded`. The deployed network includes an NSG rule permitting VPN pool `172.16.0.0/24` to TCP 1433.

## 5. Deploy SQL VM

The existing `sql-vm.bicep` has a secure `adminPassword` parameter and a `vmSize` default updated to `Standard_D2as_v5`.

```powershell
az deployment group what-if `
  --resource-group rg-sqllab-personal `
  --template-file .\infra\sql-vm.bicep

az deployment group create `
  --name personal-sqlvm-dev `
  --resource-group rg-sqllab-personal `
  --template-file .\infra\sql-vm.bicep `
  --output table
```

**Enter `adminPassword` at the secure prompt**; do not paste it into tracked files or a shared terminal log. The deployed image was `MicrosoftSQLServer:SQL2022-WS2022:sqldev-gen2:latest`. Record VM private IP and ensure there is no public IP:

```powershell
az vm show -g rg-sqllab-personal -n vm-sqllab-sql --show-details `
  --query "{VM:name,Power:powerState,Size:hardwareProfile.vmSize,PrivateIP:privateIps,PublicIP:publicIps}" `
  -o table
```

## 6. Deploy certificate-authenticated P2S VPN

The certificate pair used in the tested environment was created locally and stored in Windows Certificate Store (`Cert:\CurrentUser\My`). An existing public root certificate Base64 file was used to deploy the trust anchor.

```powershell
$certData = (Get-Content .\certs\P2SRootCert.base64.txt -Raw).Trim()

az deployment group what-if `
  -g rg-sqllab-personal `
  --template-file .\infra\vpn-gateway.bicep `
  --parameters rootCertificateData="$certData"

# This creates an ONGOING BILLABLE VpnGw1AZ Gateway:
az deployment group create `
  --name personal-vpn-dev `
  -g rg-sqllab-personal `
  --template-file .\infra\vpn-gateway.bicep `
  --parameters rootCertificateData="$certData" `
  -o table
```

This uses **only public root certificate data** as a deployment parameter. Do not upload your P2S client certificate's private key to Azure or GitHub. Provisioning can take tens of minutes.

## 7. Download the VPN profile from Azure Portal

1. Open Azure Portal → **VPN gateways** (not ExpressRoute gateways).
2. Open `vpngw-sqllab-dev`.
3. Select **Point-to-site configuration → Download VPN client**.
4. Extract the generated ZIP and locate `AzureVPN/azurevpnconfig.xml` or `azurevpnconfig_cert.xml`.
5. Open Azure VPN Client → **Import**, choose XML, select the **P2S client certificate**, save and connect.
6. Use your organisation's permitted VPN/security policy; do not bypass managed endpoint filtering.

Verify locally:

```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "172.16.0.*" }
Find-NetRoute -RemoteIPAddress 10.50.1.4
```

The actual private IP may differ after redeployment.

## 8. Configure guest SQL listener and firewall

Verify service/listener over Run Command:

```powershell
az vm run-command invoke -g rg-sqllab-personal -n vm-sqllab-sql `
  --command-id RunPowerShellScript `
  --scripts 'Get-Service MSSQLSERVER; Get-NetTCPConnection -LocalPort 1433 -State Listen -ErrorAction SilentlyContinue' `
  --query "value[].message" -o tsv
```

If the listener is absent, inspect the SQL TCP/IP protocol configuration using **SQL Server Configuration Manager** inside the VM; do not assume all image versions enable it identically.

Guest firewall rule, tested in the project:

```powershell
az vm run-command invoke -g rg-sqllab-personal -n vm-sqllab-sql `
  --command-id RunPowerShellScript `
  --scripts 'if (-not (Get-NetFirewallRule -Name SqlLab-Allow-SQL-From-VPN -ErrorAction SilentlyContinue)) { New-NetFirewallRule -Name SqlLab-Allow-SQL-From-VPN -DisplayName SqlLab-Allow-SQL-From-VPN -Direction Inbound -Action Allow -Protocol TCP -LocalPort 1433 -RemoteAddress 172.16.0.0/24 -Profile Any }; Get-NetFirewallRule -Name SqlLab-Allow-SQL-From-VPN | Format-Table Name,Enabled,Direction,Action' `
  --query "value[].message" -o tsv
```

Verify with the VPN connected:

```powershell
Test-NetConnection 10.50.1.4 -Port 1433
```

Expected: `TcpTestSucceeded : True`.

## 9. Connect with SSMS

SQL Server in the tested deployment used **Windows Authentication only**. Running Azure VM Run Command as `NT AUTHORITY\SYSTEM` succeeded in connecting to SQL but this account did **not** have `sysadmin`.

On the Windows laptop, the VM's local Windows account was used to launch SSMS via network-only credentials:

```powershell
runas /netonly /user:vm-sqllab-sql\labadmin '"C:\Program Files\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\SSMS.exe"'
```

Enter the VM administrator password when prompted (never store it in the repository).

SSMS connection: **Database Engine**, server `tcp:10.50.1.4,1433`, **Windows Authentication**. For the lab, **Trust Server Certificate** was used; review [security.md](security.md) before production use.

## 10. Database validation

In SSMS run [sql/01-demo-database.sql](../sql/01-demo-database.sql).

Then verify the current session:

```sql
SELECT
    encrypt_option AS IsEncrypted,
    auth_scheme AS AuthenticationMethod,
    client_net_address AS ClientIPAddress
FROM sys.dm_exec_connections
WHERE session_id = @@SPID;
```

Observed: `TRUE`, `NTLM`, `172.16.0.2`.

## 11. Stop charges after testing

```powershell
az vm deallocate -g rg-sqllab-personal -n vm-sqllab-sql
az vm show -g rg-sqllab-personal -n vm-sqllab-sql --show-details --query powerState -o tsv
```

Expected: `VM deallocated`. **NAT Gateway, VPN Gateway, public IPs and disk charges may continue.** See [cost-management.md](cost-management.md).

## 12. Publication security

Do not commit any `certs/` private material, `.pfx`, `.p12`, `.key`, VPN profiles/download URLs, admin passwords, connection strings containing credentials or Azure tokens. Use `git diff --cached` and verify Git history.
