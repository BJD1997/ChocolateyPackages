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
    $packageArgs = @{
        packageName    = $packageName
        fileType       = 'MSI'
        silentArgs     = "/qn /norestart /l*v `"$($env:TEMP)\$packageName.$($app.DisplayVersion).MsiUninstall.log`""
        validExitCodes = @(0, 3010, 1605, 1614, 1641)
    }

    if ($app.UninstallString -match '\{[0-9A-Fa-f\-]+\}') {
        $packageArgs['file'] = $Matches[0]
    } else {
        $packageArgs['file'] = $app.PSChildName
    }

    Uninstall-ChocolateyPackage @packageArgs
}
