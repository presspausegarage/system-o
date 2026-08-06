#Requires -Version 7.0
<#
.SYNOPSIS
  Shared configuration and SMTP helpers for the system-o dawn report.
.DESCRIPTION
  Email is optional. Environment variables take precedence over an external
  config file. Windows config files store the password as a DPAPI protected
  value. Unix config files are required to be outside the vault and mode 0600.
#>

function Get-DawnEmailConfigPath {
  param([string]$ConfigPath = '')
  if ($ConfigPath) { return [System.IO.Path]::GetFullPath($ConfigPath) }
  if ($env:SYSTEM_O_DAWN_EMAIL_CONFIG) {
    return [System.IO.Path]::GetFullPath($env:SYSTEM_O_DAWN_EMAIL_CONFIG)
  }
  $base = if ($IsWindows) {
    [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
  } elseif ($env:XDG_CONFIG_HOME) {
    $env:XDG_CONFIG_HOME
  } else {
    Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.config'
  }
  return Join-Path (Join-Path $base 'system-o') 'dawn-email.json'
}

function Test-DawnPathInsideRoot {
  param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
  $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
  $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  return $fullPath.Equals($fullRoot, $comparison) -or $fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, $comparison)
}

function Convert-DawnSecureStringToText {
  param([Parameter(Mandatory)][securestring]$SecureString)
  return ([System.Net.NetworkCredential]::new('', $SecureString)).Password
}

function Get-DawnEmailSettings {
  param([string]$ConfigPath = '')

  $envNames = @('SYSTEM_O_SMTP_HOST', 'SYSTEM_O_SMTP_USER', 'SYSTEM_O_SMTP_PASSWORD', 'SYSTEM_O_SMTP_RECIPIENT')
  $hasEnv = @($envNames | Where-Object { -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) }).Count
  if ($hasEnv -eq $envNames.Count) {
    return [pscustomobject]@{
      Host = $env:SYSTEM_O_SMTP_HOST
      Port = if ($env:SYSTEM_O_SMTP_PORT) { [int]$env:SYSTEM_O_SMTP_PORT } else { 587 }
      User = $env:SYSTEM_O_SMTP_USER
      Password = $env:SYSTEM_O_SMTP_PASSWORD
      Recipient = $env:SYSTEM_O_SMTP_RECIPIENT
      From = if ($env:SYSTEM_O_SMTP_FROM) { $env:SYSTEM_O_SMTP_FROM } else { $env:SYSTEM_O_SMTP_USER }
      EnableSsl = $env:SYSTEM_O_SMTP_SSL -notin @('0', 'false', 'False')
      Source = 'environment'
    }
  }
  if ($hasEnv -gt 0) {
    throw 'Partial SYSTEM_O_SMTP_* environment configuration found. Set host, user, password, and recipient together.'
  }

  $path = Get-DawnEmailConfigPath -ConfigPath $ConfigPath
  if (-not (Test-Path $path)) { return $null }
  $cfg = Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json
  $password = $null
  if ($cfg.storage -eq 'dpapi-current-user') {
    if (-not $IsWindows) { throw "DPAPI email config cannot be read on this platform: $path" }
    $password = Convert-DawnSecureStringToText (ConvertTo-SecureString ([string]$cfg.password_protected))
  } elseif ($cfg.storage -eq 'unix-0600') {
    if ($IsWindows) { throw "Unix email config cannot be read on Windows: $path" }
    $mode = [System.IO.File]::GetUnixFileMode($path)
    $allowed = [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite
    if (($mode -band (-bnot $allowed)) -ne 0) {
      throw "Email config permissions are too broad: $path. Required mode: 0600."
    }
    $password = [string]$cfg.password
  } else {
    throw "Unsupported email config storage '$($cfg.storage)' in $path"
  }

  foreach ($field in 'host', 'user', 'recipient') {
    if ([string]::IsNullOrWhiteSpace([string]$cfg.$field)) { throw "Email config is missing '$field': $path" }
  }
  if ([string]::IsNullOrWhiteSpace($password)) { throw "Email config has no usable password: $path" }
  return [pscustomobject]@{
    Host = [string]$cfg.host
    Port = if ($cfg.port) { [int]$cfg.port } else { 587 }
    User = [string]$cfg.user
    Password = $password
    Recipient = [string]$cfg.recipient
    From = if ($cfg.from) { [string]$cfg.from } else { [string]$cfg.user }
    EnableSsl = if ($null -eq $cfg.enable_ssl) { $true } else { [bool]$cfg.enable_ssl }
    Source = $path
  }
}

function Send-DawnMailMessage {
  param(
    [Parameter(Mandatory)]$Settings,
    [Parameter(Mandatory)][string]$Subject,
    [Parameter(Mandatory)][string]$PlainBody,
    [Parameter(Mandatory)][string]$HtmlBody
  )

  $message = [System.Net.Mail.MailMessage]::new()
  $htmlView = $null
  $smtp = $null
  try {
    $message.From = [string]$Settings.From
    $message.To.Add([string]$Settings.Recipient)
    $message.Subject = $Subject
    $message.SubjectEncoding = [System.Text.Encoding]::UTF8
    $message.Body = $PlainBody
    $message.BodyEncoding = [System.Text.Encoding]::UTF8
    $message.IsBodyHtml = $false
    $htmlView = [System.Net.Mail.AlternateView]::CreateAlternateViewFromString($HtmlBody, [System.Text.Encoding]::UTF8, 'text/html')
    $message.AlternateViews.Add($htmlView)

    $smtp = [System.Net.Mail.SmtpClient]::new([string]$Settings.Host, [int]$Settings.Port)
    $smtp.EnableSsl = [bool]$Settings.EnableSsl
    $smtp.Credentials = [System.Net.NetworkCredential]::new([string]$Settings.User, [string]$Settings.Password)
    $smtp.Send($message)
  } finally {
    if ($htmlView) { $htmlView.Dispose() }
    $message.Dispose()
    if ($smtp) { $smtp.Dispose() }
  }
}
