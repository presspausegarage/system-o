#Requires -Version 7.0
<#
.SYNOPSIS
  Build and optionally email the system-o dawn report.
.DESCRIPTION
  The builder always writes HTML and plain-text evidence before this script
  reads email configuration. With no email configuration, this command exits
  cleanly in file-only mode and says so. Use -NoSend to rehearse the complete
  build path without reading any credentials.
.PARAMETER Root
  Vault root.
.PARAMETER ConfigPath
  Optional external email config path. Never place it inside the vault.
.PARAMETER NoSend
  Build evidence and stop before configuration lookup or SMTP delivery.
.PARAMETER SkipBuild
  Send already-built evidence for -Date.
#>
[CmdletBinding()]
param(
  [string]$Root = '.',
  [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
  [string]$VaultName = '',
  [string]$ConfigPath = '',
  [string]$OutPath = '',
  [string]$TextOutPath = '',
  [switch]$NoSend,
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path
$logsDir = Join-Path $Root '_meta/logs'
if (-not $OutPath) { $OutPath = Join-Path $logsDir "dawn-report-$Date.html" }
if (-not $TextOutPath) { $TextOutPath = Join-Path $logsDir "dawn-report-$Date.txt" }

if (-not $SkipBuild) {
  $buildArgs = @{
    Root = $Root
    Date = $Date
    OutPath = $OutPath
    TextOutPath = $TextOutPath
  }
  if ($VaultName) { $buildArgs['VaultName'] = $VaultName }
  & (Join-Path $PSScriptRoot 'build-dawn-report.ps1') @buildArgs
}

if (-not (Test-Path $OutPath) -or -not (Test-Path $TextOutPath)) {
  throw "Dawn evidence is incomplete. Expected $OutPath and $TextOutPath"
}
if ($NoSend) {
  Write-Host "STATUS dawn-email delivery=file-only reason=no-send html=$OutPath text=$TextOutPath"
  exit 0
}

. (Join-Path $PSScriptRoot '_dawn-email.ps1')
$settings = Get-DawnEmailSettings -ConfigPath $ConfigPath
if (-not $settings) {
  $resolvedConfig = Get-DawnEmailConfigPath -ConfigPath $ConfigPath
  Write-Host "STATUS dawn-email delivery=file-only reason=unconfigured config=$resolvedConfig html=$OutPath text=$TextOutPath"
  exit 0
}

$htmlBody = Get-Content -Path $OutPath -Raw -Encoding UTF8
$plainBody = Get-Content -Path $TextOutPath -Raw -Encoding UTF8
$subjectLine = @($plainBody -split "`r?`n" | Where-Object { $_ -match '^subject:\s+' } | Select-Object -First 1)
$subject = if ($subjectLine.Count -gt 0) { $subjectLine[0] -replace '^subject:\s+', '' } else { "dawn: report for $Date" }
Send-DawnMailMessage -Settings $settings -Subject $subject -PlainBody $plainBody -HtmlBody $htmlBody
Write-Host "STATUS dawn-email delivery=sent recipient=$($settings.Recipient) source=$($settings.Source) html=$OutPath text=$TextOutPath"
