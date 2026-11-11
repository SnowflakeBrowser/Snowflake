<#
 Builds Veil for Windows (x64).  Requires the .NET 8 SDK:  winget install Microsoft.DotNet.SDK.8
 Usage:   .\windows\scripts\build_windows.ps1 [-Version 1.0.0] [-FrameworkDependent]
 Output:  windows\dist\Veil-<version>-win-x64\Veil.exe  (+ a .zip next to it)
 Default is self-contained (no .NET install needed, ~150 MB). -FrameworkDependent is much smaller but
 needs the ".NET 8 Desktop Runtime" installed on the PC.
#>
param(
  [string]$Version = "0.1.0",
  [switch]$FrameworkDependent,
  [switch]$NoTor             # skip the automatic download of the official Tor Expert Bundle
)
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$proj = Join-Path $root "Veil.Windows\Veil.Windows.csproj"
$out  = Join-Path $root "dist\Veil-$Version-win-x64"
$sc   = if ($FrameworkDependent) { "false" } else { "true" }

$torDir = Join-Path $root "Veil.Windows\ThirdParty\tor"
$hasTor = [bool](Get-ChildItem $torDir -Recurse -Filter tor.exe -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $hasTor -and -not $NoTor) {
  # Fetch the official Tor Expert Bundle automatically (hash + signature checked). Git for Windows ships gpg.
  $env:PATH += ";C:\Program Files\Git\usr\bin"
  try { & (Join-Path $PSScriptRoot "fetch_tor.ps1") }
  catch { Write-Warning "Could not fetch Tor: $($_.Exception.Message)`nContinuing WITHOUT Tor; 'New Tor window' will explain how to add it." }
  $hasTor = [bool](Get-ChildItem $torDir -Recurse -Filter tor.exe -ErrorAction SilentlyContinue | Select-Object -First 1)
}
if (-not $hasTor) { Write-Warning "No tor.exe in Veil.Windows\ThirdParty\tor: this build has no Tor." }

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
dotnet publish $proj -c Release -r win-x64 --self-contained $sc `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:Version=$Version -o $out
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

Copy-Item (Join-Path $PSScriptRoot "register_default_browser.ps1") $out
Compress-Archive -Path "$out\*" -DestinationPath "$out.zip" -Force

# Self-check: is tor.exe really inside what we built?
if (-not $NoTor) {
  $inFolder = Get-ChildItem (Join-Path $out "tor") -Recurse -Filter tor.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [System.IO.Compression.ZipFile]::OpenRead("$out.zip")
  $inZip = $z.Entries | Where-Object { $_.Name -eq "tor.exe" } | Select-Object -First 1
  $count = @($z.Entries | Where-Object { $_.FullName -like "tor/*" -or $_.FullName -like "tor\*" }).Count
  $z.Dispose()
  $report = "tor.exe in output folder: $([bool]$inFolder) ($($inFolder.FullName)); in zip: $([bool]$inZip) ($($inZip.FullName), $($inZip.Length) bytes); files under tor/ in zip: $count"
  if ($inFolder -and $inZip) { Write-Host "::notice title=Tor check::$report" }
  else { Write-Host "::error title=Tor missing from build::$report"; throw "tor.exe is missing from the build: $report" }
}
Write-Host "`nBuilt $out\Veil.exe`nZip:   $out.zip"
