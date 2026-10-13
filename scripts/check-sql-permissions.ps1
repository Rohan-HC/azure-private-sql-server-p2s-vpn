Write-Output "=== SQL PERMISSION CHECK ==="

$query = @"
SET NOCOUNT ON;
SELECT
    SYSTEM_USER AS LoginName,
    IS_SRVROLEMEMBER('sysadmin') AS IsSysadmin,
    IS_SRVROLEMEMBER('dbcreator') AS IsDbCreator,
    HAS_PERMS_BY_NAME(NULL, NULL, 'CREATE ANY DATABASE') AS CanCreateDatabase,
    CONVERT(int, SERVERPROPERTY('IsIntegratedSecurityOnly')) AS WindowsAuthOnly;
"@

& sqlcmd.exe -S "tcp:127.0.0.1,1433" -E -d master -l 10 -b -W -Q $query 2>&1 | ForEach-Object { Write-Output $_ }

Write-Output "SQLCMD_EXIT_CODE=$LASTEXITCODE"
