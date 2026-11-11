<#
 Downloads the official Tor Expert Bundle (the tor.exe the Tor Project builds for Tor Browser) into
 windows\Veil.Windows\ThirdParty\tor so that the build copies it next to Veil.exe.

 Usage:   .\windows\scripts\fetch_tor.ps1                 # newest stable release
          .\windows\scripts\fetch_tor.ps1 -Version 15.0.5 # a specific Tor Browser release number

 What it checks, and it stops on any mismatch:
   1. SHA-256 of the download against sha256sums-signed-build.txt from the Tor Project
   2. the OpenPGP signature (.asc) of the download, made by the "Tor Browser Developers" key
      (needs GnuPG: winget install GnuPG.GnuPG).  -SkipSignature skips this and ONLY keeps the hash check,
      which proves nothing against someone who controls the download server. Don't ship that way.
 The version number is the Tor Browser release; the bundle contains the matching tor daemon.
#>
param(
  [string]$Version = "",
  [switch]$SkipSignature
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Fingerprint of the Tor Browser Developers signing key (https://support.torproject.org/tbb/how-to-verify-signature/)
$ExpectedFpr = "EF6E286DDA85EA2A4BA7DE684E2C6E8793298290"

$dest = Join-Path $PSScriptRoot "..\Veil.Windows\ThirdParty\tor"
$work = Join-Path ([IO.Path]::GetTempPath()) ("veil-tor-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $work | Out-Null

try {
  if (-not $Version) {
    $meta = Invoke-RestMethod "https://aus1.torproject.org/torbrowser/update_3/release/downloads.json"
    $Version = [string]$meta.version
    if (-not $Version) { throw "Could not read the current version from downloads.json. Pass -Version (see https://www.torproject.org/download/tor/)." }
  }
  Write-Host "Tor Expert Bundle for Tor Browser $Version (windows-x86_64)"

  $file = "tor-expert-bundle-windows-x86_64-$Version.tar.gz"
  $bases = @("https://dist.torproject.org/torbrowser/$Version", "https://archive.torproject.org/tor-package-archive/torbrowser/$Version")

  function Get-First($name, $out) {
    foreach ($b in $bases) {
      try { Invoke-WebRequest "$b/$name" -OutFile $out -UseBasicParsing; return $true } catch { }
    }
    return $false
  }

  $tgz = Join-Path $work $file
  if (-not (Get-First $file $tgz)) { throw "Could not download $file from dist.torproject.org or archive.torproject.org." }
  $sums = Join-Path $work "sha256sums-signed-build.txt"
  if (-not (Get-First "sha256sums-signed-build.txt" $sums)) { throw "Could not download sha256sums-signed-build.txt." }

  # 1. hash
  $line = Get-Content $sums | Where-Object { $_ -match [regex]::Escape($file) + "\s*$" } | Select-Object -First 1
  if (-not $line) { throw "$file is not listed in sha256sums-signed-build.txt." }
  $want = ($line -split "\s+")[0].ToLowerInvariant()
  $got = (Get-FileHash $tgz -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($want -ne $got) { throw "SHA-256 mismatch for $file`n  expected $want`n  got      $got" }
  Write-Host "SHA-256 OK  ($got)"

  # 2. signature
  if ($SkipSignature) {
    Write-Warning "Signature check skipped. Only the SHA-256 from the same server was verified."
  } else {
    $gpg = Get-Command gpg -ErrorAction SilentlyContinue
    if (-not $gpg) { throw "GnuPG (gpg) is required to verify the signature. Install it (winget install GnuPG.GnuPG) or pass -SkipSignature (not recommended)." }
    $asc = "$tgz.asc"
    if (-not (Get-First "$file.asc" $asc)) { throw "Could not download $file.asc." }
    $home_ = Join-Path $work "gnupg"; New-Item -ItemType Directory -Force $home_ | Out-Null
    # Git for Windows' gpg is an MSYS program: it needs /c/Users/... paths, not C:\Users\... (native gpg4win needs the normal form).
    $msys = $gpg.Source -like "*\usr\bin\*"
    function P($p) { if ($msys -and $p -match '^([A-Za-z]):[\\/](.*)$') { return "/" + $Matches[1].ToLower() + "/" + ($Matches[2] -replace '\\', '/') }; return $p }
    $gh = P $home_
    $diag = @()
    $diag += (& gpg --version 2>&1 | Select-Object -First 1)
    function Get-Fprs { (& gpg --homedir $gh --batch --with-colons --fingerprint 2>$null) | Where-Object { $_ -like "fpr:*" } | ForEach-Object { ($_ -split ":")[9] } }
    function Has-Key { return ((Get-Fprs) -contains $ExpectedFpr) }
    # 1. gpg's own web-key-directory lookup
    $diag += (& gpg --homedir $gh --batch --auto-key-locate "nodefault,wkd" --locate-keys torbrowser@torproject.org 2>&1)
    # 2. the same key file, downloaded directly from the Tor Project
    if (-not (Has-Key)) {
      try {
        $kf = Join-Path $work "tor-key.bin"
        Invoke-WebRequest "https://openpgpkey.torproject.org/.well-known/openpgpkey/torproject.org/hu/kounek7zrdx745qydx6p59t9mqjpuhdf?l=torbrowser" -OutFile $kf -UseBasicParsing
        $diag += (& gpg --homedir $gh --batch --import (P $kf) 2>&1)
      } catch { $diag += "direct key download failed: $($_.Exception.Message)" }
    }
    # 3. public key servers, asking for the pinned fingerprint
    foreach ($ks in @("hkps://keys.openpgp.org", "hkps://keyserver.ubuntu.com")) {
      if (Has-Key) { break }
      $diag += (& gpg --homedir $gh --batch --keyserver $ks --recv-keys $ExpectedFpr 2>&1)
    }
    if (-not (Has-Key)) {
      throw "Could not obtain the Tor Browser Developers key with fingerprint $ExpectedFpr (found: $((Get-Fprs) -join ', ')). gpg said: $(($diag | Out-String) -replace '[\r\n]+', ' | ')"
    }
    $out = & gpg --homedir $gh --batch --status-fd 1 --verify (P $asc) (P $tgz) 2>&1
    if (-not (($out -match "VALIDSIG") -and ($out -match $ExpectedFpr))) { throw "Signature verification FAILED:`n$out" }
    Write-Host "OpenPGP signature OK (key $ExpectedFpr)"
  }

  # extract
  $x = Join-Path $work "x"; New-Item -ItemType Directory -Force $x | Out-Null
  & tar -xzf $tgz -C $x
  if ($LASTEXITCODE -ne 0) { throw "tar failed to extract the bundle." }
  $exe = Get-ChildItem $x -Recurse -Filter tor.exe | Select-Object -First 1
  if (-not $exe) { throw "tor.exe not found inside the bundle." }

  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  New-Item -ItemType Directory -Force $dest | Out-Null
  Copy-Item (Join-Path $x "*") $dest -Recurse -Force
  Set-Content (Join-Path $dest "VERSION.txt") "Tor Browser $Version / $file`nsha256 $got`nFetched $(Get-Date -Format s)"
  Write-Host "`nInstalled to $dest`nNow build:  .\windows\scripts\build_windows.ps1"
}
finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
