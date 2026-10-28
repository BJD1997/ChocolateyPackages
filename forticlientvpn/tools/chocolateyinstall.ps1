$ErrorActionPreference = 'Stop'

$packageName    = 'forticlientvpn'
$packageVersion = $env:ChocolateyPackageVersion
$toolsDir       = Split-Path -Parent $MyInvocation.MyCommand.Definition
$captureDir     = Join-Path $toolsDir 'capture'

# Fortinet publishes no stable, version-specific download URL for FortiClient
# VPN — only a self-updating online installer that fetches the real MSI over
# its own update protocol at run time (see Get-FortiClientVpnMsi.ps1 for how
# that capture works). There's no static file to pin a -Checksum against:
# the "latest" bootstrap EXE itself changes independently of the VPN client
# version whenever Fortinet republishes it. Integrity is verified instead by
# checking Fortinet's own Authenticode signature on both the bootstrap and
# the real MSI it downloads, and by confirming the captured MSI's real
# ProductVersion matches this package's own version before installing —
# together giving the same guarantee a checksum would (untampered content,
# and the version you asked for is the version you get).
$msi = & (Join-Path $toolsDir 'Get-FortiClientVpnMsi.ps1') -OutputPath $captureDir -TimeoutSeconds 900

Write-Host "Captured $($msi.ProductName) $($msi.ProductVersion) (signed by $($msi.Signer))"

if ($msi.ProductVersion -ne $packageVersion) {
    throw "Fortinet currently serves $($msi.ProductVersion), but this package is $packageVersion. " +
          "Run the package's update check first so the declared version matches what Fortinet actually serves."
}

$packageArgs = @{
    packageName    = $packageName
    fileType       = 'MSI'
    file           = $msi.MsiPath
    silentArgs     = "/qn /norestart /l*v `"$($env:TEMP)\$packageName.$packageVersion.MsiInstall.log`""
    validExitCodes = @(0, 3010, 1641)
}

Install-ChocolateyInstallPackage @packageArgs

Remove-Item -LiteralPath $captureDir -Recurse -Force -ErrorAction SilentlyContinue
