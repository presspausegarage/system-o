#Requires -Version 7.0
<#
.SYNOPSIS
  Install Obsidian on a Linux host — the spec's "Obsidian-augmented" optional
  layer (§System architecture layer 4), resolved dynamically and verified.
.DESCRIPTION
  Never hardcodes a version or URL: queries GitHub's official release API
  for whatever is CURRENT at run time, so this script doesn't go stale the
  way a pinned download link would. Downloads the asset matching the host's
  architecture, then verifies it against the SHA256 GitHub's API reports for
  that exact asset before installing anything.

  What that verification does and does NOT prove: GitHub computes this
  digest server-side when the asset is uploaded to the release. Matching it
  proves the bytes you received are identical to what's recorded against
  that official release — protecting against a corrupted download or a
  swapped file at some other point in the chain. It is NOT a cryptographic
  signature from Obsidian's own signing key (they do not currently publish
  one) — be precise about this distinction rather than overclaim it.

  Prefers the AppImage: Obsidian does not publish a native .rpm at all
  (checked directly against the release API — only AppImage, .deb, and a
  handful of non-Linux formats exist), so branching on rpm-vs-deb package
  families would be incomplete for rpm-based hosts regardless of effort.
  The AppImage runs identically on any distro with FUSE (present by default
  on most). The .deb path is offered as an option on Debian-family hosts for
  adopters who want real package-manager integration (uninstall via apt,
  appears in desktop menus) instead of a loose executable.
.PARAMETER PreferDeb
  On a non-ARM Debian-family host, install the .deb package instead of the
  AppImage. Falls back to AppImage (with a warning) everywhere else.
.PARAMETER InstallDir
  Where the AppImage lands. Default: $HOME/Applications.
.EXAMPLE
  pwsh -File install-obsidian.ps1
  pwsh -File install-obsidian.ps1 -PreferDeb
#>
[CmdletBinding()]
param(
  [switch]$PreferDeb,
  [string]$InstallDir = (Join-Path $HOME 'Applications')
)

$ErrorActionPreference = 'Stop'
function Say { param([string]$m) Write-Host "[install-obsidian] $m" }

if ($IsWindows) { throw "This installer targets Linux hosts. Obsidian for Windows ships its own installer from obsidian.md/download." }

# --- 1. Resolve the CURRENT release dynamically — never a pinned version/URL ---
Say "querying GitHub's official release API for the current version..."
$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest' -Headers @{ 'User-Agent' = 'system-o-install-obsidian' }
Say "current release: $($release.tag_name)"

# --- 2. Detect architecture + pick the matching asset ---
$arch = & uname -m
$isArm = $arch -match 'aarch64|arm64'
$isDebFamily = (Test-Path /etc/debian_version) -or [bool](Get-Command dpkg -ErrorAction SilentlyContinue)

$installMode = 'appimage'
$asset = $null
if ($PreferDeb) {
  if ($isDebFamily -and -not $isArm) {
    $asset = $release.assets | Where-Object { $_.name -match '^obsidian_[\d.]+_amd64\.deb$' } | Select-Object -First 1
    if ($asset) { $installMode = 'deb' }
  }
  if (-not $asset) { Say "WARN -PreferDeb requested but host isn't a non-ARM Debian-family system (or no .deb asset published this release) — falling back to AppImage" }
}
if (-not $asset) {
  $pattern = if ($isArm) { '^Obsidian-[\d.]+-arm64\.AppImage$' } else { '^Obsidian-[\d.]+\.AppImage$' }
  $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
}
if (-not $asset) { throw "No matching asset found in release $($release.tag_name) for arch=$arch" }
Say ("selected asset: {0} ({1} MB)" -f $asset.name, [math]::Round($asset.size / 1MB, 1))

# --- 3. Download + verify against GitHub's own recorded digest ---
$tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) $asset.name
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpFile
$expected = ($asset.digest -replace '^sha256:', '').ToLower()
$actual = (Get-FileHash -Path $tmpFile -Algorithm SHA256).Hash.ToLower()
if ($expected) {
  if ($actual -ne $expected) {
    Remove-Item $tmpFile -Force
    throw "CHECKSUM MISMATCH for $($asset.name) — expected $expected, got $actual. Refusing to install; re-run, and if this repeats, treat it as a real integrity problem, not a fluke."
  }
  Say "checksum verified: sha256:$actual matches GitHub's release record for $($asset.name)"
} else {
  Say "WARN release API returned no digest for this asset — proceeding unverified (should not normally happen; worth checking manually if it does)"
}

# --- 4. Install ---
if ($installMode -eq 'deb') {
  Say "installing via dpkg (Debian-family)..."
  & sudo dpkg -i $tmpFile
  & sudo apt-get install -f -y   # resolve any deps dpkg couldn't
  Remove-Item $tmpFile -Force
  Say "installed. Launch: obsidian"
} else {
  if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
  $dest = Join-Path $InstallDir 'Obsidian.AppImage'
  Move-Item -Path $tmpFile -Destination $dest -Force
  & chmod +x $dest
  Say "installed to $dest"
  Say "launch: $dest  (add --no-sandbox if it fails to start on a minimal desktop — a common Electron/AppImage gotcha, not a sign anything is wrong)"
}
