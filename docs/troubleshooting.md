# Troubleshooting Notes — What Actually Happened

This log captures observed issues and resolutions, rather than generic guesses.

## 1. VM size restriction in a new subscription

- **Observed:** `Standard_D2as_v4` had `NotAvailableForSubscription` in Sweden Central despite a nonzero regional quota.
- **Resolution:** Selected `Standard_D2as_v5` and updated the VM Bicep parameter default.
- **Lesson:** vCPU quotas, SKU eligibility and actual regional capacity are separate checks.

## 2. Azure VM and SQL service were healthy, but laptop TCP 1433 failed

- **Observed:** VPN client IP `172.16.0.2`, route `10.50.0.0/16`, and `MSSQLSERVER` listening on `0.0.0.0:1433` were all confirmed.
- **Observed failure:** `Test-NetConnection 10.50.1.4 -Port 1433` returned `False`.
- **Resolution:** Added `SqlLab-Allow-SQL-From-VPN` Windows Defender Firewall rule permitting inbound TCP 1433 from `172.16.0.0/24`.
- **Verified:** Same laptop TCP test subsequently returned `True`.
- **Lesson:** Azure NSG permission does not replace guest OS firewall policy.

## 3. Windows SYSTEM was not a SQL administrator

- **Observed:** Remote Run Command executed as `NT AUTHORITY\SYSTEM`; SQL query returned `WindowsOnly = 1` and `IsSysadmin = 0`.
- **Resolution:** Connected with SSMS using network-only Windows credentials for `vm-sqllab-sql\labadmin`.
- **Verified:** `ORIGINAL_LOGIN()` returned `vm-sqllab-sql\labadmin`, `IsSysadmin = 1` and `CanCreateDatabase = 1`.
- **Lesson:** Windows VM administrator, SYSTEM service context and SQL login permissions are not interchangeable.

## 4. PowerShell → Azure CLI → SQL inline quoting failure

- **Observed:** `AS was unexpected at this time` when nesting quoted SQL text into a one-line `az vm run-command invoke`.
- **Resolution:** Wrote SQL logic to a `.ps1` script and sent it with the `@file` argument, avoiding nested shell quoting.
- **Lesson:** Use script files for multi-layer CLI commands.

## 5. SSMS executable was not found

- **Observed:** `runas /netonly` returned error `2: The system cannot find the file specified`.
- **Cause:** The executable path omitted the `Release` directory.
- **Resolution:** Used `C:\Program Files\Microsoft SQL Server Management Studio 22\Release\Common7\IDE\SSMS.exe`.

## 6. SSMS pre-login handshake timeout

- **Observed:** Initial SSMS attempt timed out in the pre-login handshake.
- **Follow-up:** The user subsequently showed a successful SSMS connection and database operations.
- **Causality caution:** A temporary change to SSMS Encrypt settings was suggested during diagnosis, but evidence does **not** establish it as the definitive cause or fix.
- **Verified security result:** Later DMV check showed `encrypt_option = TRUE` for the successful session.

## 7. Managed endpoint filtering in the old environment

- **Observed in the prior university Azure setup:** A GlobalProtect transport filter was identified during network diagnostics and suspected of blocking outbound SQL traffic even when P2S VPN routes looked correct.
- **Resolution for this project:** Moved the lab to a personal Azure subscription and recreated all core resources using Bicep; final SQL connectivity succeeded.
- **Caution:** Do not disable or bypass organisation-managed endpoint controls. Changing Azure subscription alone does not guarantee local endpoint filtering policy has changed.

## Quick diagnostic decision tree

```text
VPN says Connected?
  ├─ No → Check Azure VPN Client profile and certificate
  └─ Yes → VPN IP and route present?
             ├─ No → Inspect VPN client addressing/routing
             └─ Yes → SQL VM running and TCP 1433 listening?
                        ├─ No → Inspect SQL service/TCP protocol
                        └─ Yes → TCP 1433 reachable from laptop?
                                   ├─ No → NSG, guest firewall, endpoint/network filtering
                                   └─ Yes → SSMS login/permissions/TLS diagnosis
```
