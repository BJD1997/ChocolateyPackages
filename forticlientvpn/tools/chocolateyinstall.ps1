$ErrorActionPreference = 'Stop'
$packageName   = 'forticlientvpn'
$toolsDir      = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"
$url = 'https://filestore.fortinet.com/forticlient/FortiClientSetup_7.0.8.0427.zip'
$checksum = 'd75f6a13ffe09fe66ba20444bb947a5372c631e028f9fe39cb277823acf655ff'
$url64 = 'https://filestore.fortinet.com/forticlient/FortiClientSetup_7.0.8.0427_x64.zip'
$checksum64 = 'a133906891b5ebff7e5f69bf8a9ff76d865a36ddbd7895fd318f8379fb0ec079'
$fileLocation = Join-Path $toolsDir 'FortiClientVPN.msi'

$packageArgs = @{
  packageName   = $packageName
  unzipLocation = $toolsDir
  fileType      = 'MSI'
  url           = $url
  url64         = $url64
  file = $fileLocation
  silentArgs = "/qn /norestart /l*v `"$($env:TEMP)\$($packageName).$($env:chocolateyPackageVersion).MsiInstall.log`""
  softwareName  = 'FortiClient VPN' 
  checksum      = $checksum
  checksum64    = $checksum64
  checksumType  = 'sha256'
  }

Install-ChocolateyZipPackage @packageArgs
Install-ChocolateyInstallPackage @packageArgs
