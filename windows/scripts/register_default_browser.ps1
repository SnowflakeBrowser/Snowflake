<#
 Makes Veil show up in  Settings > Apps > Default apps  so you can choose it as your default browser.
 No administrator rights needed (writes only to HKEY_CURRENT_USER).
 Usage:   .\register_default_browser.ps1                (uses Veil.exe next to this script)
          .\register_default_browser.ps1 -Remove        (undo)
#>
param(
  [string]$Exe = (Join-Path $PSScriptRoot "Veil.exe"),
  [switch]$Remove
)
$ErrorActionPreference = "Stop"
$cap  = "HKCU:\Software\Clients\StartMenuInternet\Veil"
$cls  = "HKCU:\Software\Classes\VeilURL"
$reg  = "HKCU:\Software\RegisteredApplications"

if ($Remove) {
  Remove-Item $cap -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $cls -Recurse -Force -ErrorAction SilentlyContinue
  Remove-ItemProperty $reg -Name "Veil" -ErrorAction SilentlyContinue
  Write-Host "Veil unregistered."; return
}

if (-not (Test-Path $Exe)) { throw "Veil.exe not found at $Exe  (use -Exe <path>)" }
$Exe = (Resolve-Path $Exe).Path

New-Item "$cap\Capabilities\URLAssociations" -Force | Out-Null
Set-ItemProperty $cap "(default)" "Veil"
Set-ItemProperty "$cap\Capabilities" "ApplicationName" "Veil"
Set-ItemProperty "$cap\Capabilities" "ApplicationDescription" "A small, private browser."
Set-ItemProperty "$cap\Capabilities" "ApplicationIcon" "`"$Exe`",0"
Set-ItemProperty "$cap\Capabilities\URLAssociations" "http" "VeilURL"
Set-ItemProperty "$cap\Capabilities\URLAssociations" "https" "VeilURL"
New-Item "$cap\shell\open\command" -Force | Out-Null
Set-ItemProperty "$cap\shell\open\command" "(default)" "`"$Exe`""

New-Item "$cls\shell\open\command" -Force | Out-Null
Set-ItemProperty $cls "(default)" "Veil URL"
Set-ItemProperty $cls "URL Protocol" ""
Set-ItemProperty "$cls\shell\open\command" "(default)" "`"$Exe`" `"%1`""

if (-not (Test-Path $reg)) { New-Item $reg -Force | Out-Null }
Set-ItemProperty $reg "Veil" "Software\Clients\StartMenuInternet\Veil\Capabilities"

Write-Host "Registered. Opening Default apps - choose Veil for HTTP and HTTPS."
Start-Process "ms-settings:defaultapps"
