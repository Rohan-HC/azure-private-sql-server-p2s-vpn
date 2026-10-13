# Cost Management and Teardown

Azure resources in this project are **billable**. A free trial/credit balance, where present, does not remove the need to monitor consumption.

| Resource | After VM deallocation |
|---|---|
| SQL VM compute | Compute charges generally stop |
| Managed OS disk | Storage charges continue |
| NAT Gateway | Gateway charges continue while provisioned |
| VPN Gateway (`VpnGw1AZ`) | Gateway charges continue while provisioned |
| Standard public IP addresses | May continue to incur charges |
| VNet/NSG | No comparable hourly gateway compute charge for basic resource existence; ancillary services/traffic may cost |

## When pausing the lab

```powershell
az vm deallocate -g rg-sqllab-personal -n vm-sqllab-sql
az vm show -g rg-sqllab-personal -n vm-sqllab-sql --show-details --query powerState -o tsv
```

`VM deallocated` stops the VM compute meter; it does not stop the VPN and NAT gateway meters. There is no general "deallocate" action for those gateways.

## When finished collecting evidence

If every resource in the lab resource group is disposable, you have backed up any SQL data you want, and the Bicep/certificate files required for recreation are preserved:

```powershell
# First verify the subscription:
az account show --query "{Name:name,Subscription:id}" -o table

# Inspect what's going to be deleted:
az resource list -g rg-sqllab-personal --query "[].{Name:name,Type:type}" -o table

# DESTRUCTIVE, IRREVERSIBLE resource-group deletion:
az group delete -n rg-sqllab-personal

# Verify deletion completed:
az group exists -n rg-sqllab-personal
```

Expected final existence result: `false`. **Never execute deletion without confirming the subscription, group, and any data you need to retain.** Deleting the resource group will also delete the SQL VM's OS disk and database data in that group; rebuilding from Bicep recreates infrastructure but does **not** restore previous SQL records automatically.

## Old university subscription

The prior university resource group `rg-sqllab-dev` was inventoried and its VM deallocation requested. **Final deletion was not demonstrated in the available outputs**. It must be checked under that subscription separately. Avoid unintentionally deleting institution-owned resources.

## Additional practices

- Use Azure Cost Management → **Cost analysis** and **Budgets** in the portal.
- Track the billing scope/subscription explicitly.
- Treat gateway creation and destruction as billable lifecycle decisions, not as no-cost pause/resume operations.
