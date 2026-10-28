$ErrorActionPreference = 'Stop'

$packageName = 'forticlientvpn'

# FortiClient VPN's MSI ProductCode changes with every release, so rather
# than hardcoding one, look it up from the uninstall registry key instead.
$key = Get-UninstallRegistryKey -SoftwareName 'FortiClient VPN*'

if (-not $key) {
    Write-Warning 'FortiClient VPN is not installed (no matching uninstall registry key found) — nothing to do.'
    return
}

foreach ($app in $key) {
    $productCode = if ($app.UninstallString -match '\{[0-9A-Fa-f\-]+\}') { $Matches[0] } else { $app.PSChildName }

    # Unlike Install-ChocolateyInstallPackage's -File, Uninstall-ChocolateyPackage
    # does not insert -File after /x for MSI type — it just runs
    # `msiexec /x $SilentArgs`. Confirmed live: passing the ProductCode via
    # -File alone silently dropped it from the actual command line, leaving
    # a bare `/x` with nothing after it (msiexec exit 1619, "could not open
    # this installation package"). The ProductCode has to be the first
    # token of -SilentArgs itself.
    $packageArgs = @{
        packageName    = $packageName
        fileType       = 'MSI'
        silentArgs     = "$productCode /qn /norestart /l*v `"$($env:TEMP)\$packageName.$($app.DisplayVersion).MsiUninstall.log`""
        validExitCodes = @(0, 3010, 1605, 1614, 1641)
    }

    Uninstall-ChocolateyPackage @packageArgs
}
