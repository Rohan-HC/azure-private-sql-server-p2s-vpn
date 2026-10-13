-- Demo script. Idempotent for the three test employee IDs.
-- Requires a login with permissions to create databases, tables and insert rows.
-- Used to reproduce the observed SqlLabDemo proof of functionality.

IF DB_ID(N'SqlLabDemo') IS NULL
BEGIN
    EXEC(N'CREATE DATABASE [SqlLabDemo]');
END;
GO

USE [SqlLabDemo];
GO

IF OBJECT_ID(N'dbo.Employees', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Employees
    (
        EmployeeID INT NOT NULL PRIMARY KEY,
        EmployeeName NVARCHAR(100) NOT NULL,
        Department NVARCHAR(50) NOT NULL
    );
END;
GO

INSERT INTO dbo.Employees (EmployeeID, EmployeeName, Department)
SELECT v.EmployeeID, v.EmployeeName, v.Department
FROM (VALUES
    (1, N'Rohan', N'Cloud Engineering'),
    (2, N'Alex', N'DevOps'),
    (3, N'Sam', N'Database Administration')
) AS v(EmployeeID, EmployeeName, Department)
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.Employees AS e
    WHERE e.EmployeeID = v.EmployeeID
);
GO

SELECT EmployeeID, EmployeeName, Department
FROM dbo.Employees
ORDER BY EmployeeID;
GO

-- Open a new SSMS query or run this in same connection to validate transport.
SELECT
    encrypt_option AS IsEncrypted,
    auth_scheme AS AuthenticationMethod,
    client_net_address AS ClientIPAddress
FROM sys.dm_exec_connections
WHERE session_id = @@SPID;
GO
