$ErrorActionPreference = 'Stop'

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$path = Join-Path $PSScriptRoot '..\bicep\modules\sql-vm.bicep'
$out = & az bicep build --file $path --stdout 2>&1
Assert-That ($LASTEXITCODE -eq 0) "SQL VM module does not compile: $($out -join ' ')"
$template = $out -join "`n" | ConvertFrom-Json

Assert-That ($template.parameters.vmName.defaultValue -eq 'vm-sqllab2-sql') 'Wrong SQL VM name'
Assert-That ($template.parameters.vmSize.defaultValue -eq 'Standard_D2as_v5') 'Wrong SQL VM size'
Assert-That ($template.parameters.dataDiskSizeGb.defaultValue -eq 128) 'Wrong SQL data disk size'
Assert-That ($template.parameters.adminPassword.type -eq 'secureString') 'Windows admin password is not secure'

$resources = @($template.resources)
$nic = $resources | Where-Object type -eq 'Microsoft.Network/networkInterfaces' | Select-Object -First 1
Assert-That ($null -ne $nic) 'SQL VM NIC missing'
$ipConfig = @($nic.properties.ipConfigurations)[0]
Assert-That ($null -eq $ipConfig.properties.publicIPAddress) 'SQL VM NIC has a public IP'
Assert-That ($ipConfig.properties.subnet.id -match 'subnetId') 'SQL VM NIC does not use workload subnet input'

$vm = $resources | Where-Object type -eq 'Microsoft.Compute/virtualMachines' | Select-Object -First 1
Assert-That ($null -ne $vm) 'SQL VM resource missing'
Assert-That ($vm.identity.type -eq 'SystemAssigned') 'SQL VM lacks system-assigned identity'
Assert-That ($vm.properties.storageProfile.imageReference.publisher -eq 'MicrosoftSQLServer') 'Wrong SQL image publisher'
Assert-That ($vm.properties.storageProfile.imageReference.sku -eq 'sqldev-gen2') 'Wrong SQL edition image'
Assert-That ($vm.properties.storageProfile.imageReference.offer -match 'SQL2022-WS2022') 'Wrong SQL/Windows version'
$dataDisk = @($vm.properties.storageProfile.dataDisks)[0]
Assert-That ($null -ne $dataDisk) 'SQL data disk missing'
Assert-That ($dataDisk.diskSizeGB -match 'dataDiskSizeGb') 'SQL disk size is not parameterized'
Assert-That ($dataDisk.managedDisk.storageAccountType -eq 'StandardSSD_LRS') 'SQL data disk is not Standard SSD'

$sqlVm = $resources | Where-Object type -eq 'Microsoft.SqlVirtualMachine/sqlVirtualMachines' | Select-Object -First 1
Assert-That ($null -ne $sqlVm) 'SQL IaaS Agent registration missing'
Assert-That ($sqlVm.properties.sqlImageSku -eq 'Developer') 'SQL IaaS edition mismatch'
Assert-That ($sqlVm.properties.sqlServerLicenseType -eq 'PAYG') 'SQL IaaS license type mismatch'

Write-Output 'SQL VM contract passed.'
