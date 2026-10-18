# Separate private SQL lab: setup

This is the **second**, disposable stack in this repository. It lives in `rg-sqllab-cicd-dev`; the original lab remains in `rg-sqllab-personal`. The entry point is [`bicep/main.bicep`](../bicep/main.bicep), and [`azure-pipelines.yml`](../azure-pipelines.yml) validates and deploys it. The planned VNet is `10.60.0.0/16`, with a `172.17.0.0/24` P2S pool. The VM has no public IP.

## Prerequisites

- Azure subscription permissions to create a resource group and resources, including role assignments on the new Key Vault. Check the `Microsoft.Compute`, `Microsoft.Network`, `Microsoft.KeyVault`, `Microsoft.SqlVirtualMachine`, and `Microsoft.Authorization` providers, the `Standard_D2as_v5` regional quota, and availability in Sweden Central.
- An Azure DevOps organization and project, a GitHub connection to this repository, a Microsoft-hosted agent job, and an Azure Resource Manager service connection using workload identity federation. See [Microsoft's organization setup](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/create-organization?view=azure-devops), [service connection guidance](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure?view=azure-devops), and [hosted-job limits](https://learn.microsoft.com/en-us/azure/devops/pipelines/licensing/concurrent-jobs?view=azure-devops).
- PowerShell 7 and Azure CLI with Bicep for local checks. Windows PowerShell is needed to generate certificate material in the Windows certificate store.

## Azure DevOps setup

1. Create an organization and private project named `PrivateSqlLab` in the Azure DevOps web portal. Connect the existing GitHub repository `Rohan-HC/azure-private-sql-server-p2s-vpn` and select `azure-pipelines.yml` as the pipeline definition.
2. Create an Azure Resource Manager service connection named `sc-sqllab-subscription` using workload identity federation. Grant the identity the subscription permissions needed for resource-group creation and deployment, plus permission to create the new Key Vault role assignment. Authorize only this pipeline to use the connection. Record the service principal and role scope in private operator notes; do not commit credentials.
3. Create a variable group named `sql-p2s-lab-secrets`. Add secret variables `windowsAdminPassword`, `sqlAdminPassword`, and `vpnRootCertData`. Restrict access to this pipeline. Use distinct strong Windows and SQL passwords. `vpnRootCertData` is the Base64 public root certificate, not a PFX or private key.
4. Confirm the hosted job can run the `Validate` stage before deploying. New organizations may need a hosted parallel-job grant. Keep billable resources undeployed while waiting for capacity.

## Certificates and parameters

Run [`scripts/New-P2SRootCertificate.ps1`](../scripts/New-P2SRootCertificate.ps1) on the Windows client that will connect to the VPN. Store the root and client PFX files under ignored `certs/cicd-lab/`; protect them and their export password. Set `vpnRootCertData` from the script's public certificate output. Import the client PFX into the connecting user's certificate store when testing. Only the public root data goes to Azure.

The development parameter file [`bicep/parameters/dev.bicepparam`](../bicep/parameters/dev.bicepparam) reads `WINDOWS_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`, and `VPN_ROOT_CERT_DATA` from process environment at compilation time. Do not save a compiled parameter JSON file with real values. The pipeline injects these from its secret variable group for manual deployment jobs only.

For local structural checks, use disposable dummy values:

```powershell
$env:WINDOWS_ADMIN_PASSWORD = 'DummyWindowsPassword!123'
$env:SQL_ADMIN_PASSWORD = 'DummySqlPassword!123'
$env:VPN_ROOT_CERT_DATA = 'RHVtbXlQdWJsaWNDZXJ0'
az bicep build --file bicep/main.bicep --outfile "$env:TEMP/sqllab-main.json"
az bicep lint --file bicep/main.bicep
az bicep build-params --file bicep/parameters/dev.bicepparam --outfile "$env:TEMP/sqllab-dev.parameters.json"
```

Delete the temporary parameter file after this check. Replace dummy values only in a protected shell or the Azure DevOps secret group for an actual deployment.

## Pipeline behavior

- A GitHub pull request into `main` runs build, lint, parameter compilation with dummy values, and contract tests. It does not load deployment secrets.
- A push does not deploy. A manual run from `main` defaults to `validate`.
- Manually select `what-if` to preview resource IDs and change types, then `create` to deploy. The create job displays only nonsensitive output names, addresses, and the database name. The pipeline never uploads the compiled parameters.

After deployment, follow [operations and teardown](cicd-lab-operations.md). The VPN Gateway, NAT Gateway, IPs, private endpoint, and disks can incur charges even when VM compute is stopped.
