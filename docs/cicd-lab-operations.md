# Separate private SQL lab: validation and teardown

These commands target **only** `rg-sqllab-cicd-dev`. Verify the selected subscription before running them. The original lab is `rg-sqllab-personal`.

## Validate Azure resources

1. In Azure DevOps, run `validate`, then `what-if`, then `create` manually from `main`. Check the `what-if` list contains only the new lab's resources. Record the run links and result in [`evidence/cicd-lab/README.md`](../evidence/cicd-lab/README.md).
2. Check the deployment output and inventory. The VM NIC must have no public IP. The VNet and P2S pools must match the plan. Key Vault public network access must be disabled, its private endpoint approved, and its private DNS zone linked to the VNet. Verify the VM managed identity has the Key Vault Secrets User role, the SQL IaaS resource exists, and `Configure-SqlServer` completed.
3. Run the guest script's integration check after the VM is ready: `pwsh -NoProfile -File tests/Test-GuestScript.ps1 -Integration`. It invokes the same Run Command twice and expects exactly one health row. It must not print secret values.
4. On the VM, resolve `<vault-name>.vault.azure.net` to a private address and validate that the managed identity can read the intended secret without displaying its value. Inspect Run Command output only for stages and row count.

## Validate the private path

1. Import the new client PFX into the current user's certificate store. Download the new gateway's VPN client package and import its OpenVPN profile into Azure VPN Client. Keep the package and profile outside Git.
2. Connect the VPN. Confirm an address from `172.17.0.0/24` and a route to `10.60.0.0/16`. From the client, run `Test-NetConnection <vm-private-ip> -Port 1433`. It should succeed only through the VPN.
3. In SSMS, connect to `<vm-private-ip>,1433` with SQL authentication (`sqladmin`). Use the SQL password from the secret group through a secure operator workflow. Query `AppDb.dbo.HealthCheck` and confirm one row. Check `sys.dm_exec_connections` for the current session's `encrypt_option` and `client_net_address` (the latter should be in the VPN pool). Record whether **Trust Server Certificate** was enabled; encryption alone does not prove server-certificate trust.
4. Confirm NSG and Windows Firewall SQL/RDP/ICMP rules have the P2S pool as source. Save screenshots or redacted command output only after removing usernames, tokens, certificates, passwords, and connection strings.

## Teardown

1. Record the new group's inventory and the final validation evidence. Confirm the exact name `rg-sqllab-cicd-dev` and the selected subscription.
2. Delete **only** `rg-sqllab-cicd-dev`:

   ```powershell
   az group delete --name rg-sqllab-cicd-dev --yes --no-wait
   az group wait --name rg-sqllab-cicd-dev --deleted
   ```

3. Confirm `az group exists --name rg-sqllab-cicd-dev` returns `false` and `az group exists --name rg-sqllab-personal` returns `true`. Check the original VM remains deallocated.
4. Remove the three now-unused secret values from the Azure DevOps variable group. Keep the pipeline definition and sanitized evidence. Protect or remove local PFX and client profile files according to the intended future reuse.

If deployment fails, inspect the new group's operation details and rerun the idempotent configuration only after identifying the cause. The same exact-group teardown applies to a failed deployment.
