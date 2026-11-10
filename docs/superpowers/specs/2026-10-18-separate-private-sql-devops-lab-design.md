# Separate private SQL and Azure DevOps lab design

## Intent and success

Build and validate a second Azure private SQL Server lab in this repository, with the capabilities demonstrated by [the reference project](https://github.com/Anupama-A16/Azure-Private-Sql-VM-via-P2S-VPN). The existing `rg-sqllab-personal` deployment and its source files remain intact. The new lab uses the existing public GitHub repository as its pipeline source, and a new Azure DevOps organization and project. After validation, delete only the new lab's billable Azure resource group. Keep the code, Azure DevOps pipeline definition, and sanitized evidence as a reproducible portfolio project.

This is a development lab, not a production SQL service. Success means that the Bicep build and lint pass, an Azure DevOps pipeline runs its validation and deployment paths, the new resources provision successfully, a certificate-authenticated P2S client connects to the private SQL VM, SQL and Key Vault controls are verified, and the new resource group is confirmed absent after teardown.

## Chosen approach

Add an independent, modular Bicep stack beside `infra/`, rather than copying the reference verbatim or refactoring the already validated lab. A separate stack gives the new deployment a distinct resource group and nonoverlapping address space while keeping the first lab reproducible. The new stack targets the same subscription and Sweden Central region. Its names and addresses are parameterized; the development defaults are:

| Item | Development value |
| --- | --- |
| Resource group | `rg-sqllab-cicd-dev` |
| VNet | `10.60.0.0/16` |
| Workload subnet | `10.60.1.0/24` |
| Private endpoint subnet | `10.60.2.0/24` |
| Gateway subnet | `10.60.255.0/27` |
| P2S client pool | `172.17.0.0/24` |
| SQL VM | `vm-sqllab2-sql`, `Standard_D2as_v5` |

The currently listed regional quota is four vCPUs, with two in use. The new two-vCPU VM fits that quota on paper; SKU availability and resource-provider permissions still need a deployment preflight. The current VM is deallocated and must stay untouched.

## Azure resources and data flow

A subscription-scope Bicep entry point creates the new resource group and invokes focused modules for network, Key Vault, SQL VM, RBAC, Run Command, and VPN Gateway. A development parameter file carries nonsecret names, addresses, sizes, and feature flags. Secret values are supplied at deployment time and are never committed.

1. The VNet has workload, private endpoint, and gateway subnets. The workload subnet uses a NAT Gateway for outbound traffic. Its NSG permits SQL TCP 1433, private RDP TCP 3389, and diagnostic ICMP only from the new P2S client pool. The SQL VM NIC has no public IP.
2. A Key Vault has public network access disabled and uses Azure RBAC. A private endpoint, `privatelink.vaultcore.azure.net` zone, zone group, and VNet link resolve the vault to its private address inside the VNet.
3. The Windows Server 2022 and SQL Server 2022 Developer VM has a system-assigned managed identity, a 128 GiB Standard SSD data disk, and SQL IaaS Agent registration. Use separate local Windows administrator and SQL administrator passwords. Store both as Key Vault secrets; give the VM identity only the secret-read role it needs.
4. A managed VM Run Command runs an idempotent PowerShell script after the VM, private DNS, Key Vault secrets, and RBAC assignment exist. The script obtains a managed-identity token from IMDS, reads the SQL password from the private Key Vault endpoint with bounded retries for RBAC propagation, enables SQL TCP 1433 and mixed authentication if needed, creates or updates the SQL administrator login, disables `sa`, creates a sample database and health table, and scopes Windows Firewall SQL/RDP/ICMP rules to the P2S range. It logs stages and outcomes but never secret values.
5. A certificate-authenticated OpenVPN P2S gateway provides the only remote path to the SQL VM. A new root and client certificate pair is generated locally for this lab. Only the root certificate's public data enters Azure; private keys and VPN client profiles remain outside Git.

The design improves on the reference by separating Windows and SQL passwords. The SQL administrator remains privileged for this lab's validation; it is not an application identity. SQL transport encryption must be measured separately from certificate trust. A successful encrypted session with `Trust Server Certificate` enabled does not establish server-certificate validation.

## Repository and pipeline

Create a `bicep/` stack with a subscription-scope entry point, modules, development parameters, and the guest configuration script; add a certificate script under `scripts/`. Keep the original `infra/` templates and scripts in place. Add setup, operations, validation, teardown, architecture, and cost documentation. New evidence must come from this deployment and must omit passwords, private keys, tokens, and other credentials.

The new Azure DevOps organization and project connect to the existing GitHub repository. Use an Azure Resource Manager service connection with workload identity federation, scoped only as broadly as subscription-scope resource-group creation and role assignment require. The pipeline uses a restricted variable group for the Windows password, SQL password, and public P2S root certificate data. Pull requests run Bicep build/lint without secrets. Manual runs expose `what-if` and `create` actions; no push automatically creates billable resources. The create run publishes only nonsensitive connection metadata. The pipeline must never print or publish secret values.

Azure DevOps organizations are created through the web portal. If the new organization lacks Microsoft-hosted job capacity, request its free grant before deploying the billable lab; use local Bicep compilation and Azure CLI preflight while that grant is pending. The acceptance target is a successful hosted pipeline run, not merely a YAML file.

## Validation and teardown

1. Compile and lint every Bicep entry point; check scripts for parse errors; review the compiled deployment and `what-if` output for the expected new resource group and no changes to `rg-sqllab-personal`.
2. Run the Azure DevOps validation, `what-if`, and manual create paths. Confirm successful provisioning of the new VNet, private SQL VM, NAT, Key Vault private endpoint/DNS, SQL IaaS resource, Run Command, and VPN Gateway.
3. From the VM, verify that the Key Vault name resolves to a private address and that its managed identity can read the intended secret. Verify that Key Vault public network access is disabled. Do not print the secret.
4. Connect the new P2S client certificate, confirm the assigned `172.17.0.0/24` address and route, then verify SQL TCP 1433, SQL authentication, seeded health data, encryption status, and client address. Check that the VM has no public IP and that the NSG and guest firewall source ranges match the P2S pool. Record sanitized screenshots and command results.
5. Inventory the exact new resource group, delete only `rg-sqllab-cicd-dev`, and poll until it no longer exists. Confirm `rg-sqllab-personal` and its resources still exist. Remove the now-unused secret values from the Azure DevOps variable group while retaining the pipeline definition and documentation.

## Dependencies and risks

- Creating the Azure DevOps organization, GitHub connection, and workload identity service connection may require interactive sign-in. The user may need to complete account challenges in the browser.
- The subscription needs permission to create resource groups, role assignments, Key Vault, networking, and SQL VM resources, plus the required providers. The preflight checks these before deployment.
- VPN Gateway, NAT Gateway, private endpoint, disks, and VM operation incur charges until the new resource group is deleted. The new lab is deployed only when the pipeline can run and validation can follow promptly.
- The Bicep and guest script must tolerate reruns. A failed run leaves the new resource group available for diagnosis; the teardown procedure still targets only the new group.

## Sources

- [Reference project and feature list](https://github.com/Anupama-A16/Azure-Private-Sql-VM-via-P2S-VPN)
- [Azure DevOps workload identity service connections](https://learn.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure?view=azure-devops)
- [Azure DevOps organization creation](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/create-organization?view=azure-devops)
- [Microsoft-hosted pipeline job limits](https://learn.microsoft.com/en-us/azure/devops/pipelines/licensing/concurrent-jobs?view=azure-devops)
- [SQL IaaS Agent registration](https://learn.microsoft.com/en-us/azure/azure-sql/virtual-machines/windows/sql-agent-extension-manually-register-single-vm?view=azuresql)
- [Key Vault private endpoint DNS](https://learn.microsoft.com/en-us/azure/networking/design-guide/private-platform-as-a-service)
