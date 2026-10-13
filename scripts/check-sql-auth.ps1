$ErrorActionPreference = 'Stop'

$sql = @"
SET NOCOUNT ON;
SELECT
    SERVERPROPERTY('IsIntegratedSecurityOnly') AS WindowsOnly,
    IS_SRVROLEMEMBER('sysadmin') AS IsSysadmin,
    SYSTEM_USER AS CurrentLogin;
"@

sqlcmd.exe -S "tcp:127.0.0.1,1433" -E -d master -Q $sql -W -b

if ($LASTEXITCODE -ne 0) {
    throw "SQL check failed with exit code $LASTEXITCODE"
}
