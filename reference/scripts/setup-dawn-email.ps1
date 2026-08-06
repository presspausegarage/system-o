#Requires -Version 7.0
<#
.SYNOPSIS
  Guided email setup for the system-o dawn report.
.DESCRIPTION
  Prompts for SMTP host, port, user, password, sender, and recipient. The
  config is always outside the vault. Windows protects the password with
  current-user DPAPI. Unix stores it in a mode-0600 file, suitable for a
  root-owned Docker secret mount. A test message verifies the settings.

  DPAPI is current-user scoped: run this under the same account that runs the
  schedule. A config written interactively cannot be decrypted by a service
  account, and the sender degrades to file-only when that happens.

  Environment-only configuration is also supported by the sender. Set
  SYSTEM_O_SMTP_HOST, SYSTEM_O_SMTP_PORT, SYSTEM_O_SMTP_USER,
  SYSTEM_O_SMTP_PASSWORD, SYSTEM_O_SMTP_RECIPIENT, and optional
  SYSTEM_O_SMTP_FROM or SYSTEM_O_SMTP_SSL.
.PARAMETER NonInteractive
  Decline the wizard without prompting or writing. Intended for automation.
.PARAMETER SkipTest
  Save the config without sending the closing test message.
#>
[CmdletBinding()]
param(
  [string]$Root = '.',
  [string]$ConfigPath = '',
  [switch]$NonInteractive,
  [switch]$SkipTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($NonInteractive) {
  Write-Host 'STATUS dawn-email-setup state=skipped reason=non-interactive'
  exit 0
}

$Root = (Resolve-Path $Root).Path
. (Join-Path $PSScriptRoot '_dawn-email.ps1')
$path = Get-DawnEmailConfigPath -ConfigPath $ConfigPath
if (Test-DawnPathInsideRoot -Path $path -Root $Root) {
  throw "Refusing to store email credentials inside the vault: $path"
}

Write-Host 'system-o dawn email setup'
Write-Host "Config destination: $path"
$hostName = Read-Host 'SMTP host'
$portText = Read-Host 'SMTP port [587]'
$port = if ($portText) { [int]$portText } else { 587 }
$user = Read-Host 'SMTP user'
$password = Read-Host 'SMTP password or app password' -AsSecureString
$recipient = Read-Host 'Recipient email'
$from = Read-Host "From email [$user]"
if (-not $from) { $from = $user }
$sslText = Read-Host 'Use TLS/SSL? [Y/n]'
$enableSsl = $sslText -notmatch '^(n|no)$'

foreach ($pair in @(
  [pscustomobject]@{ Name = 'SMTP host'; Value = $hostName },
  [pscustomobject]@{ Name = 'SMTP user'; Value = $user },
  [pscustomobject]@{ Name = 'recipient'; Value = $recipient }
)) {
  if ([string]::IsNullOrWhiteSpace($pair.Value)) { throw "$($pair.Name) is required" }
}
if ([string]::IsNullOrWhiteSpace((Convert-DawnSecureStringToText $password))) { throw 'SMTP password is required' }

$configDir = Split-Path $path -Parent
if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
$config = [ordered]@{
  version = 1
  host = $hostName
  port = $port
  user = $user
  recipient = $recipient
  from = $from
  enable_ssl = $enableSsl
}
if ($IsWindows) {
  $config['storage'] = 'dpapi-current-user'
  $config['password_protected'] = ConvertFrom-SecureString $password
} else {
  $config['storage'] = 'unix-0600'
  $config['password'] = Convert-DawnSecureStringToText $password
}
$configText = $config | ConvertTo-Json
if ($IsWindows) {
  [System.IO.File]::WriteAllText($path, $configText, [System.Text.UTF8Encoding]::new($false))
} else {
  $mode = [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite
  if (Test-Path $path) { [System.IO.File]::SetUnixFileMode($path, $mode) }
  $options = [System.IO.FileStreamOptions]::new()
  $options.Mode = [System.IO.FileMode]::Create
  $options.Access = [System.IO.FileAccess]::Write
  $options.Share = [System.IO.FileShare]::None
  $options.UnixCreateMode = $mode
  $stream = [System.IO.File]::Open($path, $options)
  try {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($configText)
    $stream.Write($bytes, 0, $bytes.Length)
  } finally {
    $stream.Dispose()
  }
  [System.IO.File]::SetUnixFileMode($path, $mode)
}
Write-Host "Saved protected email config outside the vault: $path"

if ($SkipTest) {
  Write-Host "STATUS dawn-email-setup state=configured test=skipped config=$path"
  exit 0
}

$settings = Get-DawnEmailSettings -ConfigPath $path -Root $Root
$testSubject = 'system-o dawn email test'
$testPlain = "system-o dawn email is configured.`r`n`r`nNo vault content is included in this test."
$testHtml = '<!DOCTYPE html><html><body style="font-family: Arial, sans-serif;"><p><strong>system-o dawn email is configured.</strong></p><p>No vault content is included in this test.</p></body></html>'
Send-DawnMailMessage -Settings $settings -Subject $testSubject -PlainBody $testPlain -HtmlBody $testHtml
Write-Host "STATUS dawn-email-setup state=configured test=sent recipient=$recipient config=$path"
