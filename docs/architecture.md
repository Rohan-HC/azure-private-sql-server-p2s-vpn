# Architecture and Data Flow

The project implements a private Windows SQL Server VM accessible from a remote workstation via an Azure **Point-to-Site (P2S) VPN**.

![Architecture](../diagrams/architecture.svg)

## Address plan

| Segment | CIDR / address | Function |
|---|---|---|
| Virtual network | `10.50.0.0/16` | Azure private address space |
| Workload subnet | `10.50.1.0/24` | SQL VM NIC and NAT association |
| Private endpoints subnet | `10.50.2.0/24` | Reserved for possible future private endpoints; none demonstrated |
| Gateway subnet | `10.50.255.0/27` | Azure VPN Gateway |
| VPN client pool | `172.16.0.0/24` | Addresses assigned to remote VPN clients |
| Tested laptop | `172.16.0.2` | VPN-assigned IP during validation |
| Tested VM | `10.50.1.4` | Private SQL VM IP during validation; not assumed static |

## Connection lifecycle

1. Azure VPN Client establishes a **certificate-authenticated OpenVPN** tunnel to the public endpoint of the `VpnGw1AZ` gateway.
2. The remote client obtains an IP from `172.16.0.0/24` and installs a route for `10.50.0.0/16`.
3. SSMS targets `tcp:10.50.1.4,1433`, entering the VNet over the VPN tunnel.
4. The workload subnet NSG allows inbound TCP 1433 from `172.16.0.0/24`.
5. Windows Defender Firewall on the VM has a corresponding scoped inbound allow rule.
6. SQL Server listens on TCP 1433; Windows authentication authorises `vm-sqllab-sql\labadmin`.
7. The SQL connection DMV reported `encrypt_option = TRUE`, `auth_scheme = NTLM`, and `client_net_address = 172.16.0.2`.

The NAT Gateway is attached to the workload subnet for **outbound SNAT connectivity**; it is not used for the inbound VPN-to-SQL path. There is no public IP on the SQL VM.

## Control boundaries

- **Azure control plane:** Bicep deploys network, compute and gateway resources.
- **Azure data plane:** VPN Gateway routes P2S traffic into the VNet.
- **Network access:** Azure NSG + Windows Defender Firewall restrict inbound SQL access.
- **Identity:** SQL Server Windows Authentication and SQL role membership grant database privileges.
- **Transport protection:** The tested session was encrypted; certificate-chain validation was not established as trusted.

## Operational notes

- Existing templates create a high-cost `VpnGw1AZ` gateway and NAT Gateway. These are not automatically paused with the VM.
- VM private IP was dynamic. Discover the actual IP after a redeployment; do not hardcode it as guaranteed.
- The NAT egress IP and VPN Gateway public IP are distinct public IP resources.
- The architecture does not include Azure Private Link, Azure SQL Database PaaS, ExpressRoute or Kubernetes. The `snet-private-endpoints` subnet is currently an unused placeholder.
