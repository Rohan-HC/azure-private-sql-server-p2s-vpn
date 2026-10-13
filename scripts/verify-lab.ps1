<#
.SYNOPSIS
  Read-only verification of an existing Azure private SQL lab.
.DESCRIPTION
  Checks Azure CLI context, resource states, and optionally tests SQL TCP 1433
  from the current Windows machine. Does NOT create or modify resources.
.EXAMPLE
  .\scripts\verify-lab.ps1 -ResourceGroup rg-sqllab-personal
.EXAMPLE
  .\scripts\verify-lab.ps1 -PrivateIp 10.50.1.4 -TestSqlPort
#>
[CmdletBinding()]
param(
    [string]$ResourceGroup = 'rg-sqllab-personal',
    [string]$VmName = 'vm-sqllab-sql',
    [string]$VpnGatewayName = 'vpngw-sqllab-dev',
    [string]$NatGatewayName = 'nat-sqllab-dev',
    [string]$PrivateIp = '10.50.1.4',
    [switch]$TestSqlPort
)

$ErrorActionPreference = 'Stop'

function Invoke-AzJson {
    param([string[]]$Arguments)
    $out = & az @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: az $($Arguments -join ' ')" }
    return ($out | Out-String | ConvertFrom-Json)
}

Write-Host "`n=== Azure Private SQL Lab Verification ===" -ForegroundColor Cyan
$account = Invoke-AzJson -Arguments @('account','show','-o','json')
Write-Host ("Subscription: {0}" -f $account.name)
Write-Host ("Resource group: {0}" -f $ResourceGroup)

$vm = Invoke-AzJson -Arguments @('vm','show','-g',$ResourceGroup,'-n',$VmName,'--show-details','-o','json')
Write-Host ("VM: {0}; size: {1}; state: {2}; private IP: {3}; public IP: {4}" -f `
    $vm.name, $vm.hardwareProfile.vmSize, $vm.powerState, $vm.privateIps, $vm.publicIps)

$vpn = Invoke-AzJson -Arguments @('network','vnet-gateway','show','-g',$ResourceGroup,'-n',$VpnGatewayName,'-o','json')
Write-Host ("VPN gateway: {0}; SKU: {1}; provisioning: {2}" -f `
    $vpn.name,$vpn.sku.name,$vpn.provisioningState)

$nat = Invoke-AzJson -Arguments @('network','nat','gateway','show','-g',$ResourceGroup,'-n',$NatGatewayName,'-o','json')
Write-Host ("NAT gateway: {0}; provisioning: {1}" -f $nat.name,$nat.provisioningState)

if ($TestSqlPort) {
    if ($vm.powerState -ne 'VM running') {
        Write-Warning "VM is not running; skipping SQL TCP probe."
    } else {
        Write-Host ("Testing {0}:1433 (requires an authorised active VPN)" -f $PrivateIp)
        $result = Test-NetConnection -ComputerName $PrivateIp -Port 1433 -WarningAction SilentlyContinue
        Write-Host ("TcpTestSucceeded: {0}" -f $result.TcpTestSucceeded)
        if (-not $result.TcpTestSucceeded) { Write-Warning "TCP probe failed; see docs/troubleshooting.md" }
    }
} else {
    Write-Host "TCP probe skipped (add -TestSqlPort to enable)."
}

Write-Host "Read-only verification complete."
