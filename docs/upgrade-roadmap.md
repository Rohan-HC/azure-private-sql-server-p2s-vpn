# Secure SQL V2 — Incremental Upgrade Plan

This plan extends the existing successful SQL Server 2022 + Point-to-Site VPN lab. It is **not** a separate greenfield deployment. Keep the SQL VM and VPN Gateway that already work.

## Current baseline

- Resource group used for validated lab: `rg-sqllab-personal` (confirm it still exists before acting).
- VNet: `vnet-sqllab-dev` (`10.50.0.0/16`).
- Workload subnet: `snet-workload` (`10.50.1.0/24`).
- Reserved private endpoint subnet: `snet-private-endpoints` (`10.50.2.0/24`).
- VPN client pool: `172.16.0.0/24`.
- Private SQL VM: `vm-sqllab-sql` with a system-assigned managed identity **already declared** in `infra/sql-vm.bicep`.
- Existing Bicep entrypoints: `infra/main.bicep`, `infra/sql-vm.bicep`, `infra/vpn-gateway.bicep`.
- `scripts/` contains SQL/network diagnostic helpers, and `evidence/` records verified VPN/SSMS outcomes.

**Do not run a full redeployment until a `what-if` review shows no unintended replacement/deletion.** Resource naming, VM image/SKU, NIC and gateway identity must be preserved.

## Phase 1 — Bicep validation and infrastructure inventory (safe to implement first)

- [x] Add `.github/workflows/bicep-validate.yml` to compile and lint all existing `infra/*.bicep` on pull requests; no Azure authentication or resource writes.
- [ ] Observe the first workflow run, fix any build or lint failures, then merge.
- [ ] Collect read-only Azure inventory. Confirm the RG, VM, subnets, system-assigned identity, VPN gateway, P2S pool and billable resources before modifying anything.

Read-only Azure CLI inventory (run after `az login` and confirming the active subscription):

```powershell
$rg = 'rg-sqllab-personal'
az account show --query "{name:name,id:id}" -o json
az resource list -g $rg --query "[].{name:name,type:type,location:location}" -o table
az vm show -g $rg -n vm-sqllab-sql --query "{name:name,id:id,identity:identity.type,size:hardwareProfile.vmSize}" -o json
az network vnet subnet list -g $rg --vnet-name vnet-sqllab-dev --query "[].{name:name,prefix:addressPrefix}" -o table
```

## Phase 2 — Private Key Vault + managed identity

- [ ] Add **new** Bicep module for Azure Key Vault (RBAC mode; no public network access), a private endpoint in the existing reserved subnet, Private DNS zone `privatelink.vaultcore.azure.net`, DNS zone group and VNet link.
- [ ] Read the existing VM's principal ID rather than replacing the VM merely to set identity (system-assigned identity is already in its template).
- [ ] Grant that VM's principal `Key Vault Secrets User` scoped only to the intended vault.
- [ ] Store a **new application-specific SQL credential** in Key Vault through a secure provisioning process. Do not assume storing a different value rotates an existing Windows/SQL admin password.
- [ ] Prove private DNS resolution from inside the VM (vault hostname resolves to a private IP) and retrieve a harmless test secret using a managed identity token. Do not emit real secret values into CI logs, screenshots or documentation.
- [ ] Validate without requiring public Key Vault data-plane access from hosted GitHub runners.

**Acceptance:** private network resolution + authorised VM-managed-identity secret retrieval + public data-plane access disabled.

## Phase 3 — Idempotent SQL configuration with Azure Managed Run Command

- [ ] Turn current manual post-deployment commands into an idempotent PowerShell bootstrap script.
- [ ] Configure SQL static TCP 1433, Windows Defender Firewall restricted to `172.16.0.0/24`, ensure the SQL service is running, and provision a database/app principal idempotently.
- [ ] Avoid hardcoded passwords or credentials in source. Use the VM managed identity to fetch application credentials from private Key Vault only when required.
- [ ] Add `Microsoft.Compute/virtualMachines/runCommands` managed resource as an additive module; ensure prerequisite identity, DNS and RBAC are established before running.
- [ ] Verify rerun is safe and does not reset administrator access.

**Acceptance:** fresh/repeated execution produces the intended SQL configuration without manual RDP, and private VPN SQL connectivity continues working.

## Phase 4 — GitHub Actions OIDC and gated Azure deployment

- [ ] Configure Microsoft Entra federated identity for the exact repository/environment or branch; use OIDC rather than a long-lived service principal secret.
- [ ] Split workflows: automatic PR Bicep build/lint (phase 1), authenticated `az deployment group what-if` with read-only review, and **manual/approved** `workflow_dispatch` apply for the development environment.
- [ ] Use `permissions: { contents: read, id-token: write }` on the login job and `azure/login@v2`; scope Azure RBAC to the deployment's required permissions.
- [ ] Protect the deployment environment and use a separate credential provisioning mechanism that never passes real secret values through action logs. Avoid auto-recreating the costly VPN Gateway on every push.
- [ ] Review `what-if` output for replacements/deletions and stop if unexpected.

**Acceptance:** a pull request validates cleanly; an authorised manual deployment succeeds via OIDC, with no static Azure client secret in GitHub.

## Phase 5 — Monitoring, alerting and cost limits

- [ ] Bicep-provision a Log Analytics workspace, Azure Monitor Agent on the Windows VM, and a Data Collection Rule (Windows events and selected CPU, memory, disk counters).
- [ ] Associate the DCR to the existing VM; validate Heartbeat and data arrival.
- [ ] Add a CPU threshold and an appropriate SQL availability check, with Azure Monitor Action Group notifications.
- [ ] Add Azure Cost Management budget alerts and document cleanup/retention policy. Evaluate alert and log ingestion pricing before enabling broad diagnostics.
- [ ] Distinguish planned VM deallocation from an incident to avoid false monitoring alarms.

**Acceptance:** dashboards show real data, a deliberately triggered test condition generates a notification, and budget alerts are configured.

## Phase 6 — SQL least privilege, trusted TLS, restore validation

- [ ] Create a dedicated app login/user with **only** required permissions on the demo schema/table; demonstrate a forbidden operation fails.
- [ ] Configure SQL Server TLS with a suitable certificate whose identity matches the SSMS hostname. Install/trust the CA on the client, turn OFF `Trust Server Certificate`, and verify connection succeeds.
- [ ] Test connection rejection with a mismatched/untrusted certificate.
- [ ] Set up database backups with protected storage and perform a **documented restore test**. State measured RPO/RTO targets appropriate to a lab.
- [ ] Capture screenshots/test output, redact credentials and sensitive endpoint data, and update README/architecture/security runbooks.

**Acceptance:** VPN+SQL connectivity preserved; least-privilege tests, TLS certificate validation, backup-and-restore, and monitoring evidence are documented.

## Design and cost guardrails

1. A deallocated VM does not incur VM compute hours, but disks, NAT Gateway, VPN Gateway, public IPs, private endpoint, monitoring and other services can still cost money.
2. Never assume this lab is covered by Azure free credits/free-tier. Estimate and cap cost before deploying additional services.
3. Avoid VM/VNet/VPN gateway renames and unreviewed `what-if` differences. Keep existing verified resource IDs.
4. Do not commit certificate private keys, downloaded VPN profiles, admin passwords, managed identity tokens, GitHub secrets or connection strings with credentials.
5. GitHub Actions **validation** uses no Azure credentials. Azure `what-if` and apply will be introduced later with deliberately restricted OIDC permissions.
6. **No resource deployment is performed by this roadmap or the phase-1 workflow.**

## Reference implementation guidance

- Bicep CLI: https://learn.microsoft.com/en-us/cli/azure/bicep
- Key Vault Private Link: https://learn.microsoft.com/en-us/azure/key-vault/general/private-link-service
- Managed VM Run Command: https://learn.microsoft.com/en-us/azure/virtual-machines/run-command-overview
- GitHub OIDC with Azure Login: https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect
- Azure Monitor VM DCRs: https://learn.microsoft.com/en-us/azure/azure-monitor/vm/monitor-virtual-machine-data-collection
- SSMS certificate validation: https://learn.microsoft.com/en-us/sql/ssms/quickstarts/ssms-connect
