<#
 Builds Veil for Windows (x64).  Requires the .NET 8 SDK:  winget install Microsoft.DotNet.SDK.8
 Usage:   .\windows\scripts\build_windows.ps1 [-Version 1.0.0] [-FrameworkDependent]
 Output:  windows\dist\Veil-<version>-win-x64\Veil.exe  (+ a .zip next to it)
 Default is self-contained (no .NET install needed, ~150 MB). -FrameworkDependent is much smaller but
 needs the ".NET 8 Desktop Runtime" installed on the PC.
#>
param(
  [string]$Version = "0.1.0",
  [switch]$FrameworkDependent
)
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$proj = Join-Path $root "Veil.Windows\Veil.Windows.csproj"
$out  = Join-Path $root "dist\Veil-$Version-win-x64"
$sc   = if ($FrameworkDependent) { "false" } else { "true" }

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
dotnet publish $proj -c Release -r win-x64 --self-contained $sc `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:Version=$Version -o $out
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

Copy-Item (Join-Path $PSScriptRoot "register_default_browser.ps1") $out
Compress-Archive -Path "$out\*" -DestinationPath "$out.zip" -Force
Write-Host "`nBuilt $out\Veil.exe`nZip:   $out.zip"
