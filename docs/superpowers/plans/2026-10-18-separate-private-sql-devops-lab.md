# Separate Private SQL and Azure DevOps Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, deploy, validate, and tear down a second private Azure SQL Server lab with the reference project's Azure DevOps, Key Vault, managed identity, and automated SQL features.

**Architecture:** Add an independent subscription-scope Bicep stack under `bicep/` and keep the validated `infra/` lab untouched. Azure DevOps builds from this repository on GitHub, deploys with workload identity federation, and supplies passwords through restricted secret variables. The second lab uses its own resource group and nonoverlapping network; sanitized evidence remains after that group is deleted.

**Tech Stack:** Azure Bicep 0.48+, Azure CLI, PowerShell 7, SQL Server 2022 Developer on Windows Server 2022, Azure DevOps YAML pipelines, GitHub.

**Spec:** `docs/superpowers/specs/2026-10-18-separate-private-sql-devops-lab-design.md`

## Global Constraints

- Preserve `rg-sqllab-personal`, its deployed resources, and the existing `infra/` templates.
- Use Sweden Central, `rg-sqllab-cicd-dev`, VNet `10.60.0.0/16`, workload `10.60.1.0/24`, private endpoint `10.60.2.0/24`, gateway `10.60.255.0/27`, and P2S clients `172.17.0.0/24` as development defaults.
- Name the VM `vm-sqllab2-sql`; use `Standard_D2as_v5`, SQL Server 2022 Developer, a 128 GiB Standard SSD data disk, and no VM public IP.
- Keep Windows administrator and SQL administrator passwords distinct. Never commit or print passwords, private certificates, VPN profiles, tokens, or connection strings containing credentials.
- Name the SQL login `sqladmin`, sample database `AppDb`, and seeded table `dbo.HealthCheck`. Name the restricted Azure DevOps variables `windowsAdminPassword`, `sqlAdminPassword`, and `vpnRootCertData`.
- Keep Key Vault public access disabled; resolve it through `privatelink.vaultcore.azure.net`; grant the VM identity secret-read access only.
- PR validation cannot require secrets; `what-if` and `create` are manual; no push may automatically provision billable resources.
- Deploy the new lab only after a hosted Azure DevOps pipeline can run, and delete only its resource group after evidence collection.

## Review Focus

1. **Overlapping networks:** Task 1's contract test checks that the development defaults do not overlap the original lab; Task 8 repeats the check against deployed address ranges before creation.
2. **Unintended public access:** Tasks 1 and 3 test that SQL/RDP ingress is scoped to `172.17.0.0/24` and the SQL NIC has no public IP.
3. **Private vault bootstrap:** Task 5 tests managed-identity secret retrieval and private DNS from the VM after RBAC propagation; retry is bounded and failure is explicit.
4. **Secret exposure:** Tasks 5 and 7 test that script and pipeline output contain no secret values; sanitized evidence is reviewed before commit.
5. **Wrong teardown target:** Task 10 checks the exact new resource group name and inventories it before deletion, then confirms the original group still exists.

---

## File map

- `bicep/main.bicep` and `bicep/parameters/dev.bicepparam`: subscription deployment and development values.
- `bicep/modules/network.bicep`: VNet, subnets, NSG, NAT, and outbound public IP.
- `bicep/modules/keyvault.bicep` and `keyvault-rbac.bicep`: private vault, DNS, secrets, and VM secret-reader assignment.
- `bicep/modules/sql-vm.bicep`: NIC, Windows SQL VM, data disk, and SQL IaaS registration.
- `bicep/modules/vpn-gateway.bicep`: certificate-based P2S gateway.
- `bicep/modules/vm-runcommand.bicep` and `bicep/scripts/Configure-SqlServer.ps1`: guest SQL, database, and firewall setup.
- `scripts/New-P2SRootCertificate.ps1`: local root/client certificate generation and public root export.
- `azure-pipelines.yml`: PR validation and manual deployment.
- `tests/*.ps1` and `tests/test_pipeline_yaml.py`: focused infrastructure and script contracts.
- `docs/cicd-lab.md`, `docs/cicd-lab-operations.md`, `evidence/cicd-lab/README.md`, `README.md`, `.gitignore`: setup, operation, verification, evidence, and secret exclusions.

### Task 1: Network module

**Files:** Create `bicep/modules/network.bicep`, `tests/Test-NetworkContract.ps1`.

**Interfaces:** Consume `location`, `namePrefix`, `vnetAddressPrefix`, three subnet prefixes, `vpnClientAddressPool`, and `sqlPort`. Produce `workloadSubnetId`, `privateEndpointSubnetId`, `gatewaySubnetId`, `vnetId`, `natGatewayPublicIp`, and `nsgId`.

- [ ] Write `tests/Test-NetworkContract.ps1` to compile the module and assert the exact development CIDRs, NAT association, and SQL/RDP/ICMP inbound rules sourced only from `172.17.0.0/24`; reject overlap with `10.50.0.0/16` and `172.16.0.0/24`.
- [ ] Run `pwsh -NoProfile -File tests/Test-NetworkContract.ps1`; expect failure because the module is absent.
- [ ] Implement `bicep/modules/network.bicep` with parameterized resources and outputs. Keep the gateway subnet conditional on `deployVpnGateway`.
- [ ] Rerun the contract test and `az bicep lint --file bicep/modules/network.bicep`; both must pass.
- [ ] Commit only this task's files as `Add isolated SQL lab network module`.

### Task 2: Private Key Vault and VM authorization

**Files:** Create `bicep/modules/keyvault.bicep`, `bicep/modules/keyvault-rbac.bicep`, `tests/Test-KeyVaultContract.ps1`.

**Interfaces:** Consume the private endpoint subnet and VNet IDs from Task 1, secure Windows/SQL passwords, public VPN root data, and later the VM principal ID. Produce `keyVaultName`, `keyVaultUri`, `sqlPasswordSecretName`, `windowsPasswordSecretName`, `vpnRootCertificateSecretName`, and `privateEndpointId`.

- [ ] Write a contract test for disabled public network access, RBAC mode, private endpoint and DNS zone/link, password and root-public-data secret resources, and a vault-scoped `Key Vault Secrets User` role assignment.
- [ ] Run `pwsh -NoProfile -File tests/Test-KeyVaultContract.ps1`; expect failure with missing modules.
- [ ] Implement the two modules. Use a deterministic globally unique vault suffix, and send passwords only through `@secure()` parameters into vault secret resources.
- [ ] Run the contract test and Bicep lint on both modules; both must pass.
- [ ] Commit only this task's files as `Add private Key Vault and VM secret access`.

### Task 3: SQL VM and SQL IaaS registration

**Files:** Create `bicep/modules/sql-vm.bicep`, `tests/Test-SqlVmContract.ps1`.

**Interfaces:** Consume Task 1's `workloadSubnetId`, secure Windows password, VM name/size, and disk size. Produce `vmId`, `vmName`, `vmPrincipalId`, and `privateIpAddress`.

- [ ] Write a contract test for the `vm-sqllab2-sql` default, system identity, SQL 2022 Developer image, 128 GiB Standard SSD disk, SQL IaaS resource, and NIC with no public IP reference.
- [ ] Run `pwsh -NoProfile -File tests/Test-SqlVmContract.ps1`; expect failure with missing module.
- [ ] Implement the VM module with `Standard_D2as_v5` as default and SQL IaaS PAYG/Developer registration.
- [ ] Run the contract test and Bicep lint; both must pass.
- [ ] Commit only this task's files as `Add private SQL VM and IaaS registration`.

### Task 4: P2S VPN and certificate generation

**Files:** Create `bicep/modules/vpn-gateway.bicep`, `scripts/New-P2SRootCertificate.ps1`, `tests/Test-VpnContract.ps1`.

**Interfaces:** Consume Task 1's `gatewaySubnetId`, secure public root certificate data, VPN pool, and gateway SKU. Produce `vpnGatewayName` and `vpnGatewayPublicIp`. The certificate script accepts `-OutputFolder` and `-NamePrefix`, exporting root public Base64 and client PFX outside Git.

- [ ] Write a contract test for OpenVPN, certificate authentication, `172.17.0.0/24`, the root public data property, and absence of private key material in Bicep.
- [ ] Run `pwsh -NoProfile -File tests/Test-VpnContract.ps1`; expect failure with missing module.
- [ ] Implement the VPN module and idempotent certificate script. The script must refuse overwriting an existing private key without an explicit `-Force` switch.
- [ ] Run the contract test, Bicep lint, and a PowerShell AST parse of the script; all must pass. Actual certificate generation occurs in Task 8.
- [ ] Commit only this task's files as `Add certificate VPN and local certificate tool`.

### Task 5: Idempotent guest SQL configuration

**Files:** Create `bicep/modules/vm-runcommand.bicep`, `bicep/scripts/Configure-SqlServer.ps1`, `tests/Test-GuestScript.ps1`.

**Interfaces:** Consume `vmName`, `keyVaultUri`, `sqlPasswordSecretName`, `sqlAdminUsername`, `databaseName`, `sqlPort`, and `allowedSourceCidr`. Produce `runCommandId` and provisioning state. The guest script receives only the vault URI and secret name, not the password.

- [ ] Write a script test that parses the PowerShell AST, checks parameters contain no password value, and verifies a bounded IMDS/Key Vault retry path plus redacted output. Add an integration check that will rerun the command and compare the health-table row count after deployment.
- [ ] Run `pwsh -NoProfile -File tests/Test-GuestScript.ps1`; expect failure with missing script.
- [ ] Implement the script and Run Command module. Use SQL identifier/value quoting, rerunnable login/database/table creation, `sa` disablement, SQL TCP/mixed-auth configuration, and firewall rules scoped to `172.17.0.0/24`.
- [ ] Run the script test and Bicep lint; both must pass. Keep the live integration assertion for Task 9.
- [ ] Commit only this task's files as `Automate private SQL guest configuration`.

### Task 6: Subscription deployment and full template contract

**Files:** Create `bicep/main.bicep`, `bicep/parameters/dev.bicepparam`, `tests/Test-MainContract.ps1`; modify `.gitignore`.

**Interfaces:** Wire the outputs of Tasks 1–5. Accept secure `windowsAdminPassword`, `sqlAdminPassword`, and `vpnRootCertificatePublicData`; expose nonsensitive resource names, VM private IP, VPN address pool, and gateway/NAT IPs.

- [ ] Write a full-template contract test for the separate resource group, exact CIDRs, secure parameter declarations, module dependencies, and no reference to `rg-sqllab-personal`.
- [ ] Run `pwsh -NoProfile -File tests/Test-MainContract.ps1`; expect failure with missing entry point.
- [ ] Implement the subscription entry point and development parameter file. Read the three deployment inputs from `WINDOWS_ADMIN_PASSWORD`, `SQL_ADMIN_PASSWORD`, and `VPN_ROOT_CERT_DATA` only at deployment time. Add ignores for generated Bicep JSON and all new local certificate/profile paths.
- [ ] Run `az bicep build --file bicep/main.bicep`, `az bicep lint --file bicep/main.bicep`, `az bicep build-params --file bicep/parameters/dev.bicepparam` with disposable dummy environment values, and all contract tests; all must pass without real secret values.
- [ ] Commit only this task's files as `Compose separate SQL lab deployment`.

### Task 7: Azure DevOps pipeline and operator documentation

**Files:** Create `azure-pipelines.yml`, `tests/test_pipeline_yaml.py`, `docs/cicd-lab.md`, `docs/cicd-lab-operations.md`, `evidence/cicd-lab/README.md`; modify `README.md`.

**Interfaces:** Pipeline uses `bicep/main.bicep`, `bicep/parameters/dev.bicepparam`, service connection `sc-sqllab-subscription`, and variable group `sql-p2s-lab-secrets`; actions are `what-if` and `create`.

- [ ] Write `tests/test_pipeline_yaml.py` to parse YAML and assert PR build/lint has no secret-group dependency, push does not deploy, manual actions are restricted to `what-if`/`create`, and create publishes only approved outputs.
- [ ] Run `python -m unittest discover -s tests -p test_pipeline_yaml.py`; expect failure with missing YAML.
- [ ] Implement the pipeline and documentation for organization creation, GitHub connection, workload identity, secret group, certificates, deployment, SSMS, evidence, and costs. Distinguish the original and new labs in `README.md`.
- [ ] Run `python -m unittest discover -s tests -p test_pipeline_yaml.py`, all PowerShell contracts, Bicep build/lint, and `git diff --check`; all must pass.
- [ ] Commit only this task's files as `Add Azure DevOps deployment workflow and runbook`.

### Task 8: External setup and deployment preflight

**Files:** Update `docs/cicd-lab-operations.md` only if actual setup reveals a necessary correction.

**Interfaces:** New Azure DevOps organization `rohan-hc-sqllab-2026` (append a short suffix only if unavailable), project `PrivateSqlLab`, GitHub repository `Rohan-HC/azure-private-sql-server-p2s-vpn`.

- [ ] Create the organization and project in the Azure DevOps web portal, connect the GitHub repository, and enable or request the free Microsoft-hosted parallel job grant. Confirm a hosted validation job can start before Azure resource creation.
- [ ] Create the workload identity service connection at subscription scope and authorize only this pipeline; grant Contributor and User Access Administrator only as required for resource-group creation and VM-to-vault role assignment.
- [ ] Generate the second lab's root/client certificate with `scripts/New-P2SRootCertificate.ps1 -OutputFolder certs/cicd-lab -NamePrefix SqlLabCicd`, store its private artifacts outside Git, and put the two distinct passwords plus public root data into the restricted variable group.
- [ ] Confirm provider registrations, Sweden Central `Standard_D2as_v5` availability, four-vCPU quota, no overlap with deployed network ranges, and that `rg-sqllab-cicd-dev` does not exist. Push the reviewed branch to GitHub, create a PR, and verify its secret-free hosted validation run passes.

### Task 9: Deploy and verify the new lab

**Files:** Add sanitized outputs/screenshots under `evidence/cicd-lab/`; update operations notes if findings change instructions.

**Interfaces:** Consume the Task 8 pipeline, certificates, and secret group. Produce a deployment record and evidence for each acceptance check in the spec.

- [ ] Run the hosted manual `what-if`; inspect its full resource and permission changes, confirming only `rg-sqllab-cicd-dev` is targeted.
- [ ] Run the hosted manual `create`; confirm its Azure deployment and SQL Run Command succeed without secret values in logs.
- [ ] Verify Azure VM private IP/no public IP, Key Vault public access disabled, private DNS and managed-identity secret read, SQL IaaS resource, VPN gateway, and scoped NSG/guest firewall. Rerun SQL configuration and confirm it remains idempotent.
- [ ] Confirm TCP 1433 is unreachable from the laptop before connecting the new VPN; then connect the new P2S profile and use SSMS plus SQL queries to verify TCP 1433, SQL login, health table, session encryption, and VPN client address. Redact and save evidence; review every staged image/file for credentials before commit.
- [ ] Commit only sanitized evidence and corrected docs as `Document validated SQL DevOps lab`.

### Task 10: Teardown and final repository review

**Files:** Update `evidence/cicd-lab/README.md` and `docs/cicd-lab-operations.md` with the deletion result.

**Interfaces:** Consume the exact Task 9 deployment resource-group name; preserve the original group, GitHub repo, and Azure DevOps pipeline.

- [ ] Run a guard that requires the exact literal `rg-sqllab-cicd-dev`, list every resource in it, and confirm `rg-sqllab-personal` exists before deletion.
- [ ] Delete only `rg-sqllab-cicd-dev`; poll `az group exists` until false. Confirm `rg-sqllab-personal` still exists and its VM remains deallocated.
- [ ] Remove the three now-unused variable-group secret values, while keeping the pipeline and project. Record teardown evidence without secret values.
- [ ] Run the local contract suite, YAML test, Bicep build/lint, `git diff --check`, and a whole-branch review. Commit the final evidence and docs, then integrate the reviewed branch into the GitHub repository.
