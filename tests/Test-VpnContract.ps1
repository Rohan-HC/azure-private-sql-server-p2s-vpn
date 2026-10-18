$ErrorActionPreference = 'Stop'

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$modulePath = Join-Path $PSScriptRoot '..\bicep\modules\vpn-gateway.bicep'
$out = & az bicep build --file $modulePath --stdout 2>&1
Assert-That ($LASTEXITCODE -eq 0) "VPN module does not compile: $($out -join ' ')"
$template = $out -join "`n" | ConvertFrom-Json
Assert-That ($template.parameters.vpnClientAddressPool.defaultValue -eq '172.17.0.0/24') 'Wrong VPN pool'
Assert-That ($template.parameters.rootCertificatePublicData.type -eq 'secureString') 'Root public data parameter is not protected'
$resources = @($template.resources)
$gateway = $resources | Where-Object type -eq 'Microsoft.Network/virtualNetworkGateways' | Select-Object -First 1
Assert-That ($null -ne $gateway) 'P2S gateway missing'
Assert-That ($gateway.properties.gatewayType -eq 'Vpn') 'Wrong gateway type'
Assert-That ($gateway.properties.vpnType -eq 'RouteBased') 'P2S gateway is not route based'
Assert-That ('OpenVPN' -in @($gateway.properties.vpnClientConfiguration.vpnClientProtocols)) 'OpenVPN missing'
Assert-That ('Certificate' -in @($gateway.properties.vpnClientConfiguration.vpnAuthenticationTypes)) 'Certificate authentication missing'
Assert-That ($gateway.properties.vpnClientConfiguration.vpnClientAddressPool.addressPrefixes[0] -match 'vpnClientAddressPool') 'VPN pool input not used'
Assert-That ($gateway.properties.vpnClientConfiguration.vpnClientRootCertificates[0].properties.publicCertData -match 'rootCertificatePublicData') 'Public root data not configured'
Assert-That ($null -ne ($resources | Where-Object type -eq 'Microsoft.Network/publicIPAddresses' | Select-Object -First 1)) 'VPN gateway public endpoint missing'

$certScript = Join-Path $PSScriptRoot '..\scripts\New-P2SRootCertificate.ps1'
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($certScript, [ref]$tokens, [ref]$errors)
Assert-That ($errors.Count -eq 0) 'Certificate script has PowerShell parse errors'

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $existingPfx = Join-Path $temp 'SqlLabCicd-client.pfx'
    Set-Content -LiteralPath $existingPfx -Value 'existing-private-key' -NoNewline
    $rejected = $false
    $rejectionMessage = ''
    try {
        & $certScript -OutputFolder $temp -NamePrefix SqlLabCicd -ErrorAction Stop
    }
    catch {
        $rejected = $true
        $rejectionMessage = $_.Exception.Message
    }
    Assert-That $rejected 'Certificate script overwrote an existing PFX without -Force'
    Assert-That ($rejectionMessage -match 'Certificate files already exist') 'Certificate script did not explain the overwrite refusal'
    Assert-That ((Get-Content -LiteralPath $existingPfx -Raw) -eq 'existing-private-key') 'Existing PFX was modified'
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}

Write-Output 'VPN contract passed.'
