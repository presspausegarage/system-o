#Requires -Version 7.0
<#
.SYNOPSIS
  Write and read loop ledger timestamps (spec §Loop manifest, Runner semantics).
.DESCRIPTION
  Dot-sourced by run-loop.ps1 and apply-loop-proposal.ps1 (writers) and by
  build-dawn-report.ps1 (reader). One place owns the ledger `ts` format so the
  writers cannot drift apart.

  Written form: local wall-clock time with an explicit UTC offset,
  yyyy-MM-ddTHH:mm:ss+HH:mm (ISO 8601). Local, not UTC, so the date prefix
  still names the same calendar day as the run log's filename and the dawn
  report's -Date; the offset makes the instant unambiguous.

  Legacy form: ledgers written before the offset was added carry
  yyyy-MM-ddTHH:mm:ss with no offset. Those are read as this host's local
  time, which is what the writer meant, so existing ledgers keep working.
#>

function Get-LedgerTimestamp {
  param([datetimeoffset]$At = [datetimeoffset]::Now)
  # Invariant culture: ':' in a .NET format string is the culture's time
  # separator, which is not ':' everywhere.
  return $At.ToString("yyyy-MM-dd'T'HH':'mm':'sszzz", [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-LedgerTimestamp {
  <#
    Returns the record's instant as a [datetimeoffset], or $null when the value
    is missing or unreadable. Accepts the raw string, or the [datetime] that
    PowerShell 7's ConvertFrom-Json produces when it coerces an ISO 8601
    string: an offset-less value comes back with Kind Unspecified (read as
    local), an offset value comes back already converted to local time.
  #>
  param($Value)
  if ($null -eq $Value) { return $null }
  if ($Value -is [datetimeoffset]) { return $Value }
  if ($Value -is [datetime]) {
    if ($Value.Kind -eq [System.DateTimeKind]::Unspecified) {
      $Value = [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Local)
    }
    return [datetimeoffset]::new($Value)
  }
  $text = ([string]$Value).Trim()
  if (-not $text) { return $null }
  $inv = [System.Globalization.CultureInfo]::InvariantCulture
  $parsed = [datetimeoffset]::MinValue
  if ($text -match '(Z|[+-]\d{2}:?\d{2})$') {
    if ([datetimeoffset]::TryParse($text, $inv, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $parsed }
    return $null
  }
  if ([datetimeoffset]::TryParse($text, $inv, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) { return $parsed }
  return $null
}
