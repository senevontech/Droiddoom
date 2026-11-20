<#
.SYNOPSIS
  Export the web build and serve it locally for testing in a browser.

.EXAMPLE
  .\tools\web.ps1            # export (debug) + serve on http://localhost:8060
  .\tools\web.ps1 -Release   # release export + serve
  .\tools\web.ps1 -NoExport  # just serve the last build
  .\tools\web.ps1 -Release -Lan   # also serve to phones on the same Wi-Fi (touch testing)
  .\tools\web.ps1 -Preset web_featurecheck   # P0-12 renderer feature-check build
#>
param(
    [string]$Preset = "web",
    [switch]$Release,
    [switch]$NoExport,
    [switch]$Lan,
    [int]$Port = 8060
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "build\$Preset"

# Make sure winget's godot aliases are visible even in old terminals
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

if (-not $NoExport) {
    New-Item -ItemType Directory -Force $out | Out-Null
    $mode = if ($Release) { "--export-release" } else { "--export-debug" }
    Write-Host "Exporting preset '$Preset' ($mode) ..."
    & godot_console --headless --path (Join-Path $root "game") $mode $Preset (Join-Path $out "index.html")
    if ($LASTEXITCODE -ne 0) { throw "Godot export failed (exit $LASTEXITCODE)" }
    $size = (Get-ChildItem $out -File | Measure-Object Length -Sum).Sum / 1MB
    Write-Host ("Build size: {0:N1} MB (uncompressed)" -f $size)
}

$bind = "127.0.0.1"
if ($Lan) {
    # Reachable from other devices on the local network (phone touch tests).
    $bind = "0.0.0.0"
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
        ForEach-Object { "http://$($_.IPAddress):$Port" }
    Write-Host "On your phone (same Wi-Fi) open: $($ips -join '  or  ')"
    Write-Host "If it does not load, allow Python through Windows Firewall for private networks."
}
Write-Host "Serving $out at http://localhost:$Port  (Ctrl+C to stop)"
& py -3 -m http.server $Port --bind $bind --directory $out
