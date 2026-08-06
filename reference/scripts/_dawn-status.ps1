#Requires -Version 7.0
<#
.SYNOPSIS
  Parse system-o darkloop evidence for the dawn report.
.DESCRIPTION
  Dot-sourced by build-dawn-report.ps1. Each parser returns a stable object
  with Name, State, Detail, and Evidence fields. State uses the dawn report
  vocabulary: clean, applied, proposed, held, finding, or silence.
#>

function New-DawnStatus {
  param(
    [string]$Name,
    [ValidateSet('clean', 'applied', 'proposed', 'held', 'finding', 'silence')]
    [string]$State,
    [string]$Detail,
    [string[]]$Evidence = @()
  )
  [pscustomobject]@{
    Name = $Name
    State = $State
    Detail = $Detail
    Evidence = @($Evidence)
  }
}

function Read-DawnTaskStatus {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Type,
    [Parameter(Mandatory)][string]$LogPath
  )

  if (-not (Test-Path $LogPath)) {
    return New-DawnStatus -Name $Name -State silence -Detail 'log missing'
  }

  $body = Get-Content -Path $LogPath -Raw -Encoding UTF8
  switch ($Type) {
    'triage' {
      if ($body -notmatch 'triage-inbox:\s*done\.\s*junk=(\d+)\s+proposed=(\d+)\s+stale=(\d+)\s+skipped=(\d+)') {
        return New-DawnStatus -Name $Name -State finding -Detail 'ran but emitted no completion evidence'
      }
      $changed = [int]$Matches[1] + [int]$Matches[2] + [int]$Matches[3]
      $detail = "junk=$($Matches[1]) proposed=$($Matches[2]) stale=$($Matches[3]) skipped=$($Matches[4])"
      return New-DawnStatus -Name $Name -State $(if ($changed -gt 0) { 'applied' } else { 'clean' }) -Detail $detail
    }
    'purge' {
      if ($body -notmatch 'purge-sewerpipe:\s*done\.\s*deleted=(\d+)\s+total=([^\r\n\s]+)') {
        return New-DawnStatus -Name $Name -State finding -Detail 'ran but emitted no completion evidence'
      }
      $detail = "deleted=$($Matches[1]) total=$($Matches[2])"
      return New-DawnStatus -Name $Name -State $(if ([int]$Matches[1] -gt 0) { 'applied' } else { 'clean' }) -Detail $detail
    }
    'sweep' {
      if ($body -notmatch 'sweep-handoffs:\s*done\.\s*swept=(\d+)\s+kept=(\d+)\s+skipped=(\d+)') {
        return New-DawnStatus -Name $Name -State finding -Detail 'ran but emitted no completion evidence'
      }
      $swept = [int]$Matches[1]
      $kept = [int]$Matches[2]
      $skipped = [int]$Matches[3]
      $detail = "swept=$swept kept=$kept skipped=$skipped"
      $findings = @($body -split "`r?`n" | Where-Object {
        $_ -match 'lint:\s+WARN findings present|\bERROR:'
      })
      if ($findings.Count -gt 0) {
        return New-DawnStatus -Name $Name -State finding -Detail "$detail; downstream findings present" -Evidence $findings
      }
      return New-DawnStatus -Name $Name -State $(if ($swept -gt 0) { 'applied' } else { 'clean' }) -Detail $detail
    }
    'extensions' {
      $line = @($body -split "`r?`n" | Where-Object { $_ -match '^STATUS\s+extensions=' } | Select-Object -Last 1)
      if ($line.Count -eq 0 -or $line[0] -notmatch '^STATUS\s+extensions=(\d+)\s+flagged=(\d+)(?:\s+\[([^\]]+)\])?') {
        return New-DawnStatus -Name $Name -State finding -Detail 'ran but emitted no STATUS evidence'
      }
      $total = [int]$Matches[1]
      $flagged = [int]$Matches[2]
      $names = $Matches[3]
      if ($flagged -gt 0) {
        $evidence = if ($names) { @($names -split ',' | ForEach-Object { $_.Trim() }) } else { @() }
        return New-DawnStatus -Name $Name -State finding -Detail "$flagged of $total extensions flagged" -Evidence $evidence
      }
      return New-DawnStatus -Name $Name -State clean -Detail "$total extensions checked, none flagged"
    }
    'loop' {
      $line = @($body -split "`r?`n" | Where-Object { $_ -match '^STATUS\s+loop=' } | Select-Object -Last 1)
      if ($line.Count -eq 0 -or $line[0] -notmatch '^STATUS\s+loop=(\S+).*?findings=(\d+)\s+proposals_new=(\d+)\s+auto_applied=(\d+)\s+verifier_fail=(\d+)\s+scope_fail=(\d+)') {
        return New-DawnStatus -Name $Name -State finding -Detail 'ran but emitted no STATUS evidence'
      }
      $findings = [int]$Matches[2]
      $proposed = [int]$Matches[3]
      $applied = [int]$Matches[4]
      $verifierFail = [int]$Matches[5]
      $scopeFail = [int]$Matches[6]
      $detail = "findings=$findings proposed=$proposed applied=$applied verifier_fail=$verifierFail scope_fail=$scopeFail"
      if ($verifierFail -gt 0 -or $scopeFail -gt 0) {
        return New-DawnStatus -Name $Name -State finding -Detail $detail
      }
      if ($findings -eq 0) {
        return New-DawnStatus -Name $Name -State clean -Detail $detail
      }
      if ($proposed -gt $applied) {
        return New-DawnStatus -Name $Name -State proposed -Detail $detail
      }
      if ($applied -gt 0) {
        return New-DawnStatus -Name $Name -State applied -Detail $detail
      }
      return New-DawnStatus -Name $Name -State held -Detail "$detail; no new repair was written"
    }
    default {
      throw "Unknown dawn status type: $Type"
    }
  }
}

function Get-DawnLastBeat {
  param(
    [Parameter(Mandatory)][string]$LogsDir,
    [Parameter(Mandatory)][string]$Prefix,
    [Parameter(Mandatory)][string]$BeforeDate
  )
  $dates = @(Get-ChildItem -Path $LogsDir -Filter "$Prefix-*.log" -File -ErrorAction SilentlyContinue |
    ForEach-Object {
      if ($_.Name -match '(\d{4}-\d{2}-\d{2})\.log$' -and $Matches[1] -lt $BeforeDate) {
        $Matches[1]
      }
    } | Sort-Object)
  if ($dates.Count -gt 0) { return $dates[-1] }
  return $null
}
