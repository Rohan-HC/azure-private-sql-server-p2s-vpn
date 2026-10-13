Write-Output "=== SQL DIAGNOSTIC START ==="

$service = Get-Service MSSQLSERVER -ErrorAction SilentlyContinue

if ($service) {
    Write-Output "SQL_SERVICE=$($service.Status)"
} else {
    Write-Output "SQL_SERVICE_NOT_FOUND"
}

$listeners = @(Get-NetTCPConnection -LocalPort 1433 -State Listen -ErrorAction SilentlyContinue)

Write-Output "LISTENER_COUNT=$($listeners.Count)"

foreach ($listener in $listeners) {
    Write-Output "LISTENING_ON=$($listener.LocalAddress):$($listener.LocalPort)"
}

$instance = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction SilentlyContinue).MSSQLSERVER

if ($instance) {
    $path = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instance\MSSQLServer\SuperSocketNetLib\Tcp"
    $settings = Get-ItemProperty $path -ErrorAction SilentlyContinue

    if ($settings) {
        Write-Output "SQL_TCP_ENABLED=$($settings.Enabled)"
    } else {
        Write-Output "TCP_SETTINGS_NOT_FOUND"
    }
} else {
    Write-Output "INSTANCE_NOT_FOUND"
}

Write-Output "=== SQL DIAGNOSTIC END ==="
