# Security Posture and Hardening Backlog

## Demonstrated controls

| Control | Evidence | Limitations |
|---|---|---|
| Private SQL VM | `PublicIP` was blank; SQL address `10.50.1.4` | Confirm again after every redeploy |
| Certificate-authenticated VPN | OpenVPN P2S client assigned `172.16.0.2` | Client private key must remain protected |
| Azure NSG ingress restriction | TCP 1433 allow from `172.16.0.0/24` | Verify effective NSG policy before production |
| Windows Defender Firewall | Inbound TCP 1433 allow scoped to VPN client pool | Firewall state can change independently from IaC |
| Windows SQL authentication | Login `vm-sqllab-sql\labadmin` connected | Lab uses highly privileged local admin |
| SQL transport encryption | `encrypt_option = TRUE` | Does **not** prove trusted server-certificate validation |
| SQL query and role validation | `IsSysadmin = 1`; demo database created | No least-privilege app/database login demonstrated |
| Cost containment | SQL VM deallocated | Gateway/disk/public IP charges may persist |

## Recommended hardening (not claimed as completed)

1. **Trusted TLS:** Provision a SQL Server certificate with valid DNS identity, configure SQL Server to present it and connect with `Encrypt=Mandatory` and `Trust Server Certificate=Off`. Validate the negotiated TLS configuration.
2. **Least privilege:** Create a dedicated SQL/Windows login mapped to `SqlLabDemo`, granting only necessary database roles/permissions. Do not use `labadmin` for routine application access.
3. **Secret management:** Avoid checked-in private certificates, passwords and VPN profile artifacts. Use appropriate secret handling mechanisms for future automation.
4. **Monitoring and auditing:** Enable SQL auditing/diagnostics and Azure Monitor as appropriate, with budget alerts.
5. **Patch, backup and recovery:** Define OS/SQL patch process, backups, restore tests and an RPO/RTO for a real workload.
6. **Administrative access:** Avoid internet-exposed RDP; use controlled private management when necessary.
7. **Certificate lifecycle:** Track expiration, revocation, renewal and distribution to authorised clients.
8. **Identity choice:** NTLM was observed for this non-domain-joined lab; production environments should consider a more robust centrally governed identity model.
9. **Network model:** Review gateway and subnet NSG effective rules, route tables and optional logging.

## Key distinction

`IsEncrypted = TRUE` shows encrypted TDS transport for the observed session. If SSMS accepted an untrusted/self-signed server certificate via **Trust Server Certificate**, server identity authentication was not fully validated by the client. The project therefore should not claim *end-to-end production-grade certificate validation*.
