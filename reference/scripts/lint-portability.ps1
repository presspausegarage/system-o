#Requires -Version 7.0
<#
.SYNOPSIS
  Portability conformance lint for system-o chain scripts (cross-runtime audit,
  July 2, 2026; distribution review D2).
.DESCRIPTION
  Scans PowerShell scripts for the Windows-lock patterns the audit found, in
  descending frequency: literal backslash separators in path contexts, Windows
  env vars, inline drive letters, and Windows-only cmdlets/executables.

  Deliberately heuristic and line-based: it flags the 90% mechanical pattern,
  it does not parse PowerShell. Regex-heavy lines outside path contexts are not
  flagged (path rules only fire on lines that call filesystem commands).
  Drive-letter findings are tagged review-only because overridable param
  defaults are exempt by audit convention.
.PARAMETER Path
  Directory containing scripts to lint.
.PARAMETER Scripts
  Optional explicit script names (the bundle's framework-generic set for
  conformance runs). Default: every *.ps1 in -Path.
.PARAMETER WarnOnly
  Report findings but exit 0 (default: exit 1 when hard findings exist).
.EXAMPLE
  lint-portability.ps1 -Path C:\dev\_meta\scripts -Scripts sweep-handoffs.ps1,bury.ps1
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Path,
  [string[]]$Scripts = @(),
  [switch]$WarnOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# pwsh -File passes array params as one comma-joined string — normalize.
$Scripts = @($Scripts | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { $_.Trim() })

# Path-context commands: backslash rules only fire on lines invoking these,
# which keeps regex patterns elsewhere from false-positiving.
$pathCmds = 'Join-Path|Test-Path|Resolve-Path|Get-ChildItem|Get-Content|Set-Content|Add-Content|Copy-Item|Move-Item|Remove-Item|New-Item|Out-File|Split-Path|Get-Item|Start-Process|\[System\.IO\.'

$rules = @(
  @{ Id = 'backslash-path';  Severity = 'hard';
     Test = { param($l) ($l -match $pathCmds) -and ($l -match "['`"][^'`"]*\\[A-Za-z_]") } ;
     Msg  = "literal '\' separator in a path context — use '/' or chained Join-Path" }
  @{ Id = 'windows-env-var'; Severity = 'hard';
     Test = { param($l) $l -match '\$env:(TEMP|TMP|APPDATA|LOCALAPPDATA|ProgramData|USERPROFILE|windir|SystemRoot)\b' } ;
     Msg  = 'Windows env var — use [IO.Path]::GetTempPath() / XDG-aware resolution' }
  @{ Id = 'windows-cmdlet';  Severity = 'hard';
     Test = { param($l) $l -match '\b(Get|New|Register|Unregister|Set)-ScheduledTask\w*\b|-ComObject\b' } ;
     Msg  = 'Windows-only cmdlet (scheduler/COM) — belongs in a per-OS registration layer' }
  @{ Id = 'windows-exe';     Severity = 'hard';
     Test = { param($l) $l -match '\b(robocopy|attrib|ie4uinit|rundll32|wscript|cscript|reg\.exe)\b|cmd(\.exe)?\s+/c' } ;
     Msg  = 'Windows-only executable — needs an engine seam or $IsWindows guard' }
  @{ Id = 'drive-letter';    Severity = 'review';
     Test = { param($l) $l -match "['`"][A-Za-z]:\\" } ;
     Msg  = 'inline drive letter — exempt if an overridable param default, else resolve from vault root' }
)

$targets = if ($Scripts.Count -gt 0) { $Scripts | ForEach-Object { Join-Path $Path $_ } }
           else { (Get-ChildItem -Path $Path -Filter '*.ps1' -File).FullName }

$findings = [System.Collections.Generic.List[object]]::new()
foreach ($file in $targets) {
  if (-not (Test-Path $file)) { Write-Warning "not found: $file"; continue }
  $n = 0
  foreach ($line in (Get-Content -Path $file -Encoding UTF8)) {
    $n++
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    foreach ($r in $rules) {
      if (& $r.Test $line) {
        $findings.Add([pscustomobject]@{
          Script = Split-Path $file -Leaf; Line = $n; Rule = $r.Id; Severity = $r.Severity
          Snippet = ($t.Length -gt 100 ? $t.Substring(0, 100) + '…' : $t); Fix = $r.Msg
        })
      }
    }
  }
}

if ($findings.Count -eq 0) { Write-Host 'LINT clean: no portability findings'; exit 0 }

$findings | Sort-Object Script, Line | Format-Table Script, Line, Rule, Severity, Snippet -AutoSize | Out-Host
$hard = @($findings | Where-Object Severity -eq 'hard')
Write-Host ("LINT findings={0} hard={1} review={2}" -f $findings.Count, $hard.Count, ($findings.Count - $hard.Count))
if ($hard.Count -gt 0 -and -not $WarnOnly) { exit 1 } else { exit 0 }
