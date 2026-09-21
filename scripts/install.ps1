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
    [string]$OpenVpnMsi = "https://swupdate.openvpn.org/community/releases/OpenVPN-2.7.7-I001-amd64.msi"
)

$ErrorActionPreference = "Stop"
$repo = "nizmitz/openvpn-gui-custom"
$bin  = "C:\Program Files\OpenVPN\bin"

# 1. Official OpenVPN: install if missing, upgrade in place if older than the pinned MSI
$wanted = [version]([regex]::Match($OpenVpnMsi, 'OpenVPN-(\d+\.\d+\.\d+)-').Groups[1].Value)
$installed = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' |
    Get-ItemProperty | Where-Object { $_.DisplayName -like 'OpenVPN *' -and $_.UninstallString -like '*MsiExec*' } |
    Select-Object -First 1 -ExpandProperty DisplayVersion
if (-not (Test-Path "$bin\openvpn.exe") -or -not $installed -or [version]$installed -lt $wanted) {
    $msi = Join-Path $env:TEMP "openvpn.msi"
    Write-Host "Downloading official OpenVPN..."
    Invoke-WebRequest $OpenVpnMsi -OutFile $msi -UseBasicParsing
    Write-Host "Installing official OpenVPN (silent)..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) { throw "msiexec failed with exit code $($p.ExitCode)" }
}

# 2. Fetch custom build
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

# 3. Skip if already installed (same hash)
$files = @("openvpn-gui.exe", "libopenvpn_plap.dll") | Where-Object { Test-Path "$tmp\$_" }
$changed = $files | Where-Object {
    -not (Test-Path "$bin\$_") -or
    (Get-FileHash "$bin\$_").Hash -ne (Get-FileHash "$tmp\$_").Hash
}
if (-not $changed) {
    Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Custom OpenVPN GUI ($Version) already installed. Nothing to do."
    exit 0
}

# 4. Stop running GUI for all users, replace, relaunch
Get-Process openvpn-gui -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
foreach ($f in $changed) { Copy-Item "$tmp\$f" $bin -Force }
Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
Start-Process "$bin\openvpn-gui.exe"
Write-Host "Done. Custom OpenVPN GUI ($Version) installed to $bin"
