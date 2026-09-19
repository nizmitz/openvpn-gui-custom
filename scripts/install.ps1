#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Install official OpenVPN (if missing) and replace its GUI with the custom build.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1
  powershell -ExecutionPolicy Bypass -File install.ps1 -Version v11.66.0.0-custom.1

.NOTES
  Re-run after any official OpenVPN upgrade/repair: the MSI restores the stock GUI.
#>
param(
    [string]$Version = "latest",
    [string]$OpenVpnMsi = "https://swupdate.openvpn.org/community/releases/OpenVPN-2.6.14-I001-amd64.msi"
)

$ErrorActionPreference = "Stop"
$repo = "nizmitz/openvpn-gui-custom"
$bin  = "C:\Program Files\OpenVPN\bin"

# 1. Official OpenVPN (skip if already present)
if (-not (Test-Path "$bin\openvpn.exe")) {
    $msi = Join-Path $env:TEMP "openvpn.msi"
    Write-Host "Downloading official OpenVPN..."
    Invoke-WebRequest $OpenVpnMsi -OutFile $msi -UseBasicParsing
    Write-Host "Installing official OpenVPN (silent)..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) { throw "msiexec failed with exit code $($p.ExitCode)" }
}

# 2. Stop running GUI for all users
Get-Process openvpn-gui -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# 3. Fetch custom build
$url = if ($Version -eq "latest") {
    "https://github.com/$repo/releases/latest/download/openvpn-gui-x64.zip"
} else {
    "https://github.com/$repo/releases/download/$Version/openvpn-gui-x64.zip"
}
$zip = Join-Path $env:TEMP "openvpn-gui-x64.zip"
$tmp = Join-Path $env:TEMP "openvpn-gui-custom"
Write-Host "Downloading custom GUI ($Version)..."
Invoke-WebRequest $url -OutFile $zip -UseBasicParsing
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive $zip -DestinationPath $tmp

# 4. Replace
Copy-Item "$tmp\openvpn-gui.exe" $bin -Force
if (Test-Path "$tmp\libopenvpn_plap.dll") {
    Copy-Item "$tmp\libopenvpn_plap.dll" $bin -Force
}
Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue

# 5. Relaunch
Start-Process "$bin\openvpn-gui.exe"
Write-Host "Done. Custom OpenVPN GUI ($Version) installed to $bin"
