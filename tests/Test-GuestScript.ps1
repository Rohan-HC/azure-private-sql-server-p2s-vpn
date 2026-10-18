param(
    [switch]$Integration,
    [string]$ResourceGroup = 'rg-sqllab-cicd-dev',
    [string]$VmName = 'vm-sqllab2-sql'
)

$ErrorActionPreference = 'Stop'

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$scriptPath = Join-Path $PSScriptRoot '..\bicep\scripts\Configure-SqlServer.ps1'
Assert-That (Test-Path -LiteralPath $scriptPath) 'Guest SQL script missing'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
Assert-That ($errors.Count -eq 0) 'Guest SQL script has PowerShell parse errors'
$parameterNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach ($name in @('KeyVaultUri', 'PasswordSecretName', 'SqlAdminUsername', 'DatabaseName', 'SqlPort', 'AllowedSourceCidr')) {
    Assert-That ($name -in $parameterNames) "Guest script parameter $name missing"
}
Assert-That ('SqlAdminPassword' -notin $parameterNames) 'Guest script accepts a password value instead of reading Key Vault'
$scriptText = Get-Content -LiteralPath $scriptPath -Raw
Assert-That ($scriptText -match '169\.254\.169\.254') 'Managed identity token endpoint missing'
Assert-That ($scriptText -match 'api-version=7\.4') 'Key Vault secret request missing'
Assert-That ($scriptText -notmatch 'Write-(Output|Host)\s+\$sqlAdminPassword') 'Guest script prints the SQL password'

$modulePath = Join-Path $PSScriptRoot '..\bicep\modules\vm-runcommand.bicep'
$out = & az bicep build --file $modulePath --stdout 2>&1
Assert-That ($LASTEXITCODE -eq 0) "Run Command module does not compile: $($out -join ' ')"
$runTemplate = $out -join "`n" | ConvertFrom-Json
$runCommand = @($runTemplate.resources) | Where-Object type -eq 'Microsoft.Compute/virtualMachines/runCommands' | Select-Object -First 1
Assert-That ($null -ne $runCommand) 'Run Command resource missing'
Assert-That ($runCommand.properties.treatFailureAsDeploymentFailure -eq $true) 'Guest script failure does not fail deployment'
$runParameters = @($runCommand.properties.parameters | ForEach-Object name)
foreach ($name in $parameterNames) {
    Assert-That ($name -in $runParameters) "Run Command does not pass $name"
}
Assert-That ('SqlAdminPassword' -notin $runParameters) 'Run Command passes the SQL password directly'

$sqlPath = Join-Path $PSScriptRoot '..\bicep\modules\sql-vm.bicep'
$sqlOut = & az bicep build --file $sqlPath --stdout 2>&1
Assert-That ($LASTEXITCODE -eq 0) "SQL VM module does not compile: $($sqlOut -join ' ')"
$sqlTemplate = $sqlOut -join "`n" | ConvertFrom-Json
Assert-That ($sqlTemplate.parameters.sqlAdminPassword.type -eq 'secureString') 'SQL bootstrap password is not secure'
$sqlVm = @($sqlTemplate.resources) | Where-Object type -eq 'Microsoft.SqlVirtualMachine/sqlVirtualMachines' | Select-Object -First 1
$connectivity = $sqlVm.properties.serverConfigurationsManagementSettings.sqlConnectivityUpdateSettings
Assert-That ($connectivity.connectivityType -eq 'PRIVATE') 'SQL IaaS connectivity is not private'
Assert-That ($connectivity.sqlAuthUpdateUserName -match 'sqlAdminUsername') 'SQL IaaS login bootstrap missing'
Assert-That ($connectivity.sqlAuthUpdatePassword -match 'sqlAdminPassword') 'SQL IaaS password bootstrap missing'

if ($Integration) {
    $vaults = & az keyvault list --resource-group $ResourceGroup -o json | ConvertFrom-Json
    Assert-That ($LASTEXITCODE -eq 0 -and @($vaults).Count -eq 1) 'Expected exactly one lab Key Vault'
    $vaultUri = $vaults[0].properties.vaultUri
    $counts = @()
    foreach ($run in 1..2) {
        $message = & az vm run-command invoke --resource-group $ResourceGroup --name $VmName `
            --command-id RunPowerShellScript --scripts "@$scriptPath" `
            --parameters "KeyVaultUri=$vaultUri" 'PasswordSecretName=sql-admin-password' `
                'SqlAdminUsername=sqladmin' 'DatabaseName=AppDb' 'SqlPort=1433' `
                'AllowedSourceCidr=172.17.0.0/24' --query 'value[].message' -o tsv
        Assert-That ($LASTEXITCODE -eq 0) "Guest configuration rerun $run failed"
        $match = [regex]::Match(($message -join "`n"), 'Health rows:\s*(\d+)')
        Assert-That $match.Success "Guest configuration rerun $run lacked a health-row result"
        $counts += [int]$match.Groups[1].Value
    }
    Assert-That ($counts[0] -eq 1 -and $counts[1] -eq 1) 'Guest configuration inserted duplicate health rows'
}

Write-Output 'Guest SQL contract passed.'
