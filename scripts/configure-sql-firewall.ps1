$ruleName = "SqlLab-Allow-SQL-From-VPN"

$existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue

if (-not $existing) {
    New-NetFirewallRule `
        -Name $ruleName `
        -DisplayName "SQL Server - VPN Clients Only" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 1433 `
        -RemoteAddress "172.16.0.0/24" `
        -Action Allow `
        -Profile Any | Out-Null

    Write-Output "FIREWALL_RULE_CREATED"
} else {
    Write-Output "FIREWALL_RULE_ALREADY_EXISTS"
}

Get-NetFirewallRule -Name $ruleName |
    Get-NetFirewallAddressFilter |
    Select-Object RemoteAddress |
    Format-List

Get-NetFirewallRule -Name $ruleName |
    Get-NetFirewallPortFilter |
    Select-Object Protocol,LocalPort |
    Format-List
