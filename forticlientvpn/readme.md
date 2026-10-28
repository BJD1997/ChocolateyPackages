# forticlientvpn — package notes

## Why this package doesn't use a static download URL

Fortinet does not publish a stable, version-specific download link for FortiClient VPN.
The only official distribution mechanism is a self-updating online installer
(`FortiClientVPNInstaller.exe`) that fetches the real MSI over Fortinet's own
update protocol (FDS) at run time. There is nothing to pin a `-Checksum` to —
the bootstrap EXE itself changes independently of the VPN client version
whenever Fortinet republishes it.

`tools/Get-FortiClientVpnMsi.ps1` runs that official installer just long
enough to capture the real MSI it downloads, then stops the installer before
it installs anything itself. `chocolateyinstall.ps1` calls this, verifies
Fortinet's Authenticode signature on both the bootstrap and the captured MSI,
confirms the MSI's real `ProductVersion` matches this package's declared
version (failing loudly on a mismatch), and only then installs it via
`Install-ChocolateyInstallPackage`.

## Automated update checks

`.github/workflows/forticlientvpn-update.yml` runs weekly (and on manual
dispatch). It runs the same capture script to find Fortinet's real current
version, and if it's newer than this package's `<version>`:

1. Bumps `forticlientvpn.nuspec`'s version and commits it.
2. Builds the `.nupkg` with `choco pack`.
3. Uploads it as a workflow artifact and attaches it to a **draft** GitHub
   Release tagged `forticlientvpn-v<version>`.

**It never runs `choco pack`'s install script and never runs `choco push`.**
Packing a nuspec doesn't execute `chocolateyinstall.ps1` — it only bundles
the files — so a successful build here says nothing about whether the
install script actually works for that version.

## Before you push a new version

1. Download the `.nupkg` from the workflow run's artifact, or from the
   draft release it creates.
2. On a real (ideally disposable/VM) Windows machine, elevated:
   ```powershell
   choco install forticlientvpn -source "<folder containing the .nupkg>"
   ```
3. Confirm it installs cleanly, then confirm `choco uninstall forticlientvpn`
   removes it cleanly too.
4. Only once that's verified, run `choco push <path-to-nupkg> --source https://push.chocolatey.org/`
   yourself (needs your own chocolatey.org API key) and publish/delete the
   draft GitHub release as you see fit.
