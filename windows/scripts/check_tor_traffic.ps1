<#
 Leak check for Tor windows. Run it in PowerShell WHILE you browse in a Tor window.
 It finds every msedgewebview2.exe process that belongs to Tor windows (their user-data folder is under
 %LOCALAPPDATA%\Veil\TorSession) and lists their network sockets.

 PASS  = every TCP connection of those processes goes to 127.0.0.1 / ::1 (that is Tor's SOCKS port) and nothing else.
 FAIL  = any TCP connection to a non-loopback address, i.e. a direct connection that bypassed Tor.
 UDP sockets are listed too: Chromium may keep local sockets open, but with the Tor switches it must not send
 anything to the internet over UDP (QUIC and WebRTC are disabled); a non-loopback UDP *remote* cannot be shown by
 Windows, so use Wireshark/pktmon with the filter in windows\TOR-WINDOW.md if you need packet-level proof.

 Usage:  .\windows\scripts\check_tor_traffic.ps1 [-Seconds 30]
#>
param([int]$Seconds = 30)
$sess = (Join-Path $env:LOCALAPPDATA "Veil\TorSession").ToLowerInvariant()
$bad = @{}
$seen = 0
$end = (Get-Date).AddSeconds($Seconds)
Write-Host "Sampling for $Seconds s. Browse in the Tor window now (open several sites and tabs)..."
while ((Get-Date) -lt $end) {
  $procs = Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" |
           Where-Object { $_.CommandLine -and $_.CommandLine.ToLowerInvariant().Contains($sess) }
  foreach ($p in $procs) {
    foreach ($c in (Get-NetTCPConnection -OwningProcess $p.ProcessId -ErrorAction SilentlyContinue)) {
      if ($c.State -in 'Listen','Bound') { continue }
      $seen++
      $ra = $c.RemoteAddress
      if ($ra -notin '127.0.0.1','::1','0.0.0.0','::') { $bad["$($p.ProcessId) -> ${ra}:$($c.RemotePort) ($($c.State))"] = $true }
    }
  }
  Start-Sleep -Milliseconds 700
}
$procs = Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" |
         Where-Object { $_.CommandLine -and $_.CommandLine.ToLowerInvariant().Contains($sess) }
Write-Host ("Tor-window WebView2 processes found: {0}; TCP connections observed: {1}" -f @($procs).Count, $seen)
if (@($procs).Count -eq 0) { Write-Warning "No Tor window browser process found - is a Tor window open?"; exit 2 }
foreach ($p in $procs) {
  foreach ($u in (Get-NetUDPEndpoint -OwningProcess $p.ProcessId -ErrorAction SilentlyContinue)) {
    Write-Host ("  UDP socket (pid {0}): {1}:{2}" -f $p.ProcessId, $u.LocalAddress, $u.LocalPort)
  }
}
if ($bad.Count -gt 0) {
  Write-Host "`nFAIL: direct (non-loopback) TCP connections from Tor-window processes:" -ForegroundColor Red
  $bad.Keys | Sort-Object | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  exit 1
}
Write-Host "`nPASS: no direct TCP connections; everything went to the local Tor SOCKS port." -ForegroundColor Green
