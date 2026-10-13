Write-Output "=== SQL CONNECTION TEST ==="
Write-Output "WINDOWS_IDENTITY=$(whoami)"

$query = "SET NOCOUNT ON; SELECT @@SERVERNAME AS ServerName, SYSTEM_USER AS LoginName, IS_SRVROLEMEMBER('sysadmin') AS IsSysadmin;"

& sqlcmd.exe -S "tcp:127.0.0.1,1433" -E -d master -l 10 -b -W -Q $query 2>&1 | ForEach-Object { Write-Output $_ }

Write-Output "SQLCMD_EXIT_CODE=$LASTEXITCODE"
