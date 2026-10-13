# Evidence of Successful Validation

These **cropped** screenshots were generated from screenshots supplied during the project walkthrough. They show factual verification output, not mockups.

- [`sql-demo-results.png`](sql-demo-results.png): successful SQL connection and database result rows, including SQL administrator/database creation checks.
- [`encrypted-connection.png`](encrypted-connection.png): `IsEncrypted = TRUE`, `AuthenticationMethod = NTLM`, `ClientIPAddress = 172.16.0.2`.

Additional evidence worth capturing locally before teardown:

- Azure deployment overview showing `Succeeded` (avoid exposing full subscription IDs).
- Azure VM Overview showing **no public IP** and private IP under workload subnet.
- VPN client *Connected* status, plus `Find-NetRoute`.
- PowerShell `Test-NetConnection ... -Port 1433` returning `True`.
- Azure NSG and Windows Firewall rule details.

**Privacy check:** Review screenshots closely before publishing. Even cropped evidence may disclose machine names, local logins or private IPs. The public endpoints, certificate serials/thumbprints, passwords, access tokens, downloaded VPN profiles and private certificate material should not be published.

**Provenance:** Screenshots represent one successful test session from 13 October 2026 and do not imply the VM remains running.
