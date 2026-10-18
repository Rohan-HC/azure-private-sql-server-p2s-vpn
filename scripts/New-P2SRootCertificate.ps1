<#
.SYNOPSIS
  Create a local root and client certificate pair for the separate P2S lab.
.DESCRIPTION
  Exports a public root CER and Base64 text plus password-protected root and
  client PFX files. The output folder must remain outside Git. An intact pair
  is reused on a second run; -Force is required to replace existing files.
#>
[CmdletBinding()]
param(
    [string]$OutputFolder = (Join-Path $PSScriptRoot '..\certs\cicd-lab'),
    [string]$NamePrefix = 'SqlLabCicd',
    [SecureString]$PfxPassword,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
    throw 'New-SelfSignedCertificate is required on Windows.'
}

$rootCerPath = Join-Path $OutputFolder "$NamePrefix-root.cer"
$rootBase64Path = Join-Path $OutputFolder "$NamePrefix-root.base64.txt"
$rootPfxPath = Join-Path $OutputFolder "$NamePrefix-root.pfx"
$clientPfxPath = Join-Path $OutputFolder "$NamePrefix-client.pfx"
$paths = @($rootCerPath, $rootBase64Path, $rootPfxPath, $clientPfxPath)
$existingPaths = @($paths | Where-Object { Test-Path -LiteralPath $_ })

if ($existingPaths.Count -gt 0 -and -not $Force) {
    $root = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -eq "CN=$NamePrefix-Root" -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } |
        Sort-Object NotAfter -Descending | Select-Object -First 1
    $client = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -eq "CN=$NamePrefix-Client" -and $_.Issuer -eq $root.Subject -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } |
        Sort-Object NotAfter -Descending | Select-Object -First 1
    $allFilesExist = @($paths | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -eq 0
    $publicMatches = $false
    if ($root -and $allFilesExist) {
        $publicMatches = ([Convert]::ToBase64String($root.RawData) -eq (Get-Content -LiteralPath $rootBase64Path -Raw))
    }
    if ($root -and $client -and $allFilesExist -and $publicMatches) {
        Write-Output "Reusing existing P2S certificates. Root public data: $rootBase64Path"
        return
    }
    throw 'Certificate files already exist but do not form an intact pair. Inspect them, or use -Force to replace them.'
}

if (-not $PfxPassword) {
    $PfxPassword = Read-Host 'Password to protect both PFX exports' -AsSecureString
}
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null

$root = New-SelfSignedCertificate `
    -Type Custom `
    -Subject "CN=$NamePrefix-Root" `
    -KeySpec Signature `
    -KeyExportPolicy Exportable `
    -HashAlgorithm SHA256 `
    -KeyLength 2048 `
    -KeyUsageProperty Sign `
    -KeyUsage CertSign `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -NotAfter (Get-Date).AddYears(2) `
    -TextExtension @('2.5.29.19={critical}{text}ca=true')

$client = New-SelfSignedCertificate `
    -Type Custom `
    -Subject "CN=$NamePrefix-Client" `
    -KeySpec Signature `
    -KeyExportPolicy Exportable `
    -HashAlgorithm SHA256 `
    -KeyLength 2048 `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -Signer $root `
    -NotAfter (Get-Date).AddYears(2) `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.2')

Export-Certificate -Cert $root -FilePath $rootCerPath -Force | Out-Null
[Convert]::ToBase64String($root.RawData) |
    Set-Content -LiteralPath $rootBase64Path -Encoding ascii -NoNewline
Export-PfxCertificate -Cert $root -FilePath $rootPfxPath -Password $PfxPassword -Force | Out-Null
Export-PfxCertificate -Cert $client -FilePath $clientPfxPath -Password $PfxPassword -Force | Out-Null

Write-Output "Root public data: $rootBase64Path"
Write-Output "Root PFX: $rootPfxPath"
Write-Output "Client PFX: $clientPfxPath"
Write-Output "Root thumbprint: $($root.Thumbprint)"
Write-Output "Client thumbprint: $($client.Thumbprint)"
