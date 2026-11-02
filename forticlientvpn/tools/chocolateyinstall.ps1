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
    throw "Fortinet is now serving FortiClient VPN $($msi.ProductVersion), but this package " +
          "($packageVersion) hasn't caught up yet — the automated update check runs weekly, so " +
          "a newer forticlientvpn package should appear within a few days. In the meantime, check " +
          "https://community.chocolatey.org/packages/forticlientvpn for a newer version (choco upgrade forticlientvpn " +
          "once one is published), or install directly from https://www.fortinet.com/support/product-downloads " +
          "if you need it right away."
}

# Fortinet's own installer always installs this MSI with
# REBOOT=r REINSTALL=ALL REINSTALLMODE=vomus MSIFASTINSTALL=7 (confirmed by
# decompiling its entry point) - REINSTALLMODE=vomus in particular forces
# Windows Installer to overwrite files even if it thinks nothing changed,
# which matters for upgrading over the same ProductCode. Match that string
# here, swapping REBOOT=r for ReallySuppress so choco controls the reboot
# instead of an unprompted one.
$packageArgs = @{
    packageName    = $packageName
    fileType       = 'MSI'
    file           = $msi.MsiPath
    silentArgs     = "/qn /norestart /l*v `"$($env:TEMP)\$packageName.$packageVersion.MsiInstall.log`" REBOOT=ReallySuppress REINSTALL=ALL REINSTALLMODE=vomus MSIFASTINSTALL=7"
    validExitCodes = @(0, 3010, 1641)
}

Install-ChocolateyInstallPackage @packageArgs

Remove-Item -LiteralPath $captureDir -Recurse -Force -ErrorAction SilentlyContinue
