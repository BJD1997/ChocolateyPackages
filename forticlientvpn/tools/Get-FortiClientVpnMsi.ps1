<#
.SYNOPSIS
    Runs Fortinet's FortiClient VPN online installer only long enough to capture the real MSI it downloads.

.DESCRIPTION
    Fortinet publishes no stable, version-specific download URL for FortiClient VPN — only a
    self-updating online installer (FortiClientVPNInstaller.exe) that requests the real package
    through Fortinet's own FDS protocol (POST /fdsupdate to forticlient.fortinet.net), unpacks a
    FortiClientVPN.exe, which writes the MSI to
    %ProgramData%\Applications\Cache\{ProductCode}\<version>\FortiClientVPN.msi and starts
    msiexec. This script starts the installer, watches that folder (plus the temp folders) for new
    .msi/.mst/.cab files, copies them once they are stable, then stops the installer before it
    installs anything — so Chocolatey (not Fortinet's own installer) owns the actual
    install/uninstall lifecycle.

    The installer and the captured MSI must both be validly signed by Fortinet, or this throws.
    Must run elevated (as a Chocolatey install script already does).

    Not fully silent: the installer has no silent/quiet switch at all (checked by decompiling
    its entry point), so its own window is briefly visible, and msiexec may flash briefly too
    before being stopped. The script stops the whole tree the instant msiexec appears (proof the
    MSI is already fully written) rather than waiting out a longer file-stability check, to keep
    that window as short as a single polling interval instead of several seconds.
#>
[CmdletBinding()]
param(
    [string]$InstallerPath,

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated session.'
}

$watchRoots = @(
    "$env:ProgramData\Applications\Cache"
    $env:TEMP
    [IO.Path]::GetTempPath()
    'C:\FortiClient_temp'
    "$env:SystemRoot\Temp"
) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique

function Assert-FortinetSignature {
    param([string]$Path)
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O="?Fortinet, Inc\."?') {
        throw "Signature check failed for ${Path}: $($sig.Status) / $($sig.SignerCertificate.Subject)"
    }
    $sig
}

function Get-MsiProperty {
    param([string]$Path, [string]$Property)
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $db = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @([string]$Path, [int]0))
    $view = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db, @("SELECT Value FROM Property WHERE Property='$Property'"))
    # Execute and Close are void COM methods, but InvokeMember still surfaces their marshaled
    # $null return to the pipeline if it isn't suppressed — left unsuppressed, this function
    # returns a 2-or-3-element array instead of a clean string. Suppress both and release the
    # COM objects before returning so a caller can safely delete the MSI right afterward.
    $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null) | Out-Null
    $record = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
    $value = if ($record) { $record.GetType().InvokeMember('StringData', 'GetProperty', $null, $record, 1) }
    $view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null) | Out-Null
    foreach ($o in @($record, $view, $db, $installer)) {
        if ($null -ne $o) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) }
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    return $value
}

function Stop-ProcessTree {
    param([int]$ProcessId)
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" |
        ForEach-Object { Stop-ProcessTree -ProcessId $_.ProcessId }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Find-NewPackageFiles {
    param([datetime]$Since)
    foreach ($root in $watchRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Recurse -File -Include *.msi, *.mst, *.cab -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $Since -or $_.CreationTime -ge $Since }
    }
}

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

if (-not $InstallerPath) {
    $InstallerPath = Join-Path ([IO.Path]::GetTempPath()) 'FortiClientVPNInstaller.exe'
    Write-Host 'Downloading FortiClientVPNInstaller.exe from filestore.fortinet.com'
    Invoke-WebRequest -Uri 'https://filestore.fortinet.com/forticlient/downloads/FortiClientVPNInstaller.exe' -OutFile $InstallerPath -UseBasicParsing
}
$installerSig = Assert-FortinetSignature -Path $InstallerPath
Write-Host "Installer signed by: $($installerSig.SignerCertificate.Subject)"

$startTime = (Get-Date).AddSeconds(-5)

Write-Host "Starting $InstallerPath"
# -WindowStyle Hidden suppresses the window for installers that honor the
# process's requested show-state; it does not reliably do so for every GUI
# app (some force their own window visible regardless), so this is a
# best-effort reduction, not a guarantee — see the msiexec fast-kill below
# for the part that actually matters most.
$proc = Start-Process -FilePath $InstallerPath -WindowStyle Hidden -PassThru
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastSizes = @{}
$stableSince = $null
$captured = $null
$msiexecSeen = $false

try {
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500

        # The wrapper only ever launches msiexec once its MSI is fully
        # written to disk — msiexec appearing is itself proof the file is
        # complete. Kill the whole tree the instant it's seen rather than
        # waiting out the file-stability check below, so its installer
        # window gets at most one polling interval on screen instead of
        # several seconds.
        if (-not $msiexecSeen) {
            $newMsiexec = @(Get-CimInstance Win32_Process -Filter "Name='msiexec.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CreationDate -ge $startTime })
            if ($newMsiexec) {
                $msiexecSeen = $true
                Write-Host 'msiexec started — the MSI is complete, stopping the installer tree now'
                if (-not $proc.HasExited) { Stop-ProcessTree -ProcessId $proc.Id }
                foreach ($p in $newMsiexec) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
            }
        }

        $files = @(Find-NewPackageFiles -Since $startTime)
        $msi = $files | Where-Object Extension -eq '.msi' | Sort-Object Length -Descending | Select-Object -First 1

        if ($msi) {
            $sizes = @{}
            foreach ($f in $files) { $sizes[$f.FullName] = $f.Length }
            $unchanged = ($sizes.Count -eq $lastSizes.Count) -and
                -not ($sizes.Keys | Where-Object { $lastSizes[$_] -ne $sizes[$_] })
            $lastSizes = $sizes

            # Once msiexec has already been stopped, the file can no longer
            # be mid-write, so there's nothing left to wait out.
            if (($unchanged -or $msiexecSeen) -and $msi.Length -gt 0) {
                if (-not $stableSince) { $stableSince = Get-Date }
                $settleSeconds = if ($msiexecSeen) { 0 } else { 6 }
                if (((Get-Date) - $stableSince).TotalSeconds -ge $settleSeconds) {
                    try {
                        $fs = [IO.File]::Open($msi.FullName, 'Open', 'Read', 'ReadWrite')
                        $fs.Close()
                        $captured = $files | Where-Object DirectoryName -eq $msi.DirectoryName
                        break
                    } catch {
                        $stableSince = $null
                    }
                }
            } else {
                $stableSince = $null
            }
        }

        if ($proc.HasExited -and -not $msi) {
            throw "Installer exited (code $($proc.ExitCode)) before an MSI appeared."
        }
    }

    if (-not $captured) { throw "No MSI captured within $TimeoutSeconds seconds." }

    foreach ($f in $captured) {
        Copy-Item -LiteralPath $f.FullName -Destination $OutputPath -Force
        Write-Host "Captured $($f.FullName)"
    }
}
finally {
    if (-not $proc.HasExited) {
        Write-Host 'Stopping installer process tree'
        Stop-ProcessTree -ProcessId $proc.Id
    }
}

$msiOut = Join-Path $OutputPath ($captured | Where-Object Extension -eq '.msi' | Sort-Object Length -Descending | Select-Object -First 1).Name
$sig = Assert-FortinetSignature -Path $msiOut

[pscustomobject]@{
    MsiPath        = $msiOut
    ProductName    = Get-MsiProperty -Path $msiOut -Property 'ProductName'
    ProductVersion = Get-MsiProperty -Path $msiOut -Property 'ProductVersion'
    ProductCode    = Get-MsiProperty -Path $msiOut -Property 'ProductCode'
    Signer         = $sig.SignerCertificate.Subject
    SHA256         = (Get-FileHash -LiteralPath $msiOut -Algorithm SHA256).Hash
}
