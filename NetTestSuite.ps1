<#
.SYNOPSIS
  Extended Windows network diagnostics with ICMP, traceroute, path loss, TCP checks, and best-effort UDP probes.

.DESCRIPTION
  - Uses built-in Windows tools: ping, tracert, pathping, Test-NetConnection
  - Writes structured JSON and compact CSV for downstream analysis
  - Supports dry-run planning, protocol/round filtering, and quiet mode
#>

[CmdletBinding(SupportsShouldProcess)]
param(
  [string[]]$HostsIPv4,
  [string[]]$HostsIPv6,

  [string]$LogDirectory = '',

  [int]$PingCount = 5,
  [int]$TraceMaxHops = 30,
  [int]$TraceTimeoutMs = 5000,
  [int]$PathpingProbes = 50,
  [int]$PathpingTimeoutMs = 3000,

  [ValidateSet('IPv4', 'IPv6')]
  [string[]]$Protocols = @('IPv4', 'IPv6'),

  [string[]]$Rounds,

  [switch]$SkipPathping,
  [switch]$DryRun,
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $PSNativeCommandUseErrorActionPreference = $false
}

$IsWindowsRuntime = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
if (-not $IsWindowsRuntime -and -not $DryRun) {
  throw 'Full NetTestSuite diagnostics require Windows built-in tools (ping/tracert/pathping/Test-NetConnection). Use -DryRun on non-Windows hosts.'
}

$DefaultHostsConfig = Join-Path $PSScriptRoot 'config/hosts.conf'

function Resolve-HomePath {
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    return $env:USERPROFILE
  }
  if (-not [string]::IsNullOrWhiteSpace($HOME)) {
    return $HOME
  }
  return (Get-Location).Path
}

function Get-DefaultLogDirectory {
  return (Join-Path (Resolve-HomePath) 'logs')
}

function Write-Status {
  param(
    [Parameter(Mandatory)][ValidateSet('INFO', 'PLAN', 'OK', 'WARN', 'FAIL', 'ERROR', 'SUMMARY')][string]$Level,
    [Parameter(Mandatory)][string]$Message
  )

  if ($Quiet -and $Level -notin @('WARN', 'FAIL', 'ERROR', 'SUMMARY')) {
    return
  }

  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Write-Host "[$timestamp] [$Level] $Message"
}

function Test-HostNameSafe {
  param([string]$HostName)
  if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
  $trimmed = $HostName.Trim()
  if ($trimmed.StartsWith('-')) { return $false }
  if ($trimmed -match '\s') { return $false }
  if ($trimmed.Contains('/')) { return $false }
  if ($trimmed.Contains('|')) { return $false }
  if ($trimmed -match '[\x00-\x1F\x7F]') { return $false }
  return $true
}

function Test-PathSafe {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  $trimmed = $Path.Trim()
  if ($trimmed.StartsWith('-')) { return $false }
  if ($trimmed.Contains('|')) { return $false }
  if ($trimmed -match '[\x00-\x1F\x7F]') { return $false }
  if ($trimmed -match '[\\/]\.\.([\\/]|$)' -or $trimmed -match '^\.\.([\\/]|$)') { return $false }
  return $true
}

function Get-HostsFromConfig {
  param([Parameter(Mandatory)][string]$Path)

  $result = @{
    IPv4 = @()
    IPv6 = @()
  }

  if (-not (Test-Path -LiteralPath $Path)) {
    return $result
  }

  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { return }
    if ($line.StartsWith('#')) { return }
    if ($line -notmatch '=') { return }

    $parts = $line.Split('=', 2)
    $key = $parts[0].Trim().ToLowerInvariant()
    $value = $parts[1].Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return }

    switch ($key) {
      'ipv4' { $result.IPv4 += $value }
      'ipv6' { $result.IPv6 += $value }
    }
  }

  return $result
}

function Get-ToolIpSwitch {
  param([ValidateSet('IPv4', 'IPv6')]$Protocol)
  if ($Protocol -eq 'IPv6') {
    return @{ Tracert = '-6'; Pathping = '/6' }
  }
  return @{ Tracert = '-4'; Pathping = '/4' }
}

function Get-HostAddressesWithTimeout {
  param(
    [Parameter(Mandatory)][string]$HostName,
    [int]$TimeoutMs = 5000
  )

  try {
    $task = [System.Net.Dns]::GetHostAddressesAsync($HostName)
    if (-not $task.Wait($TimeoutMs)) {
      return $null, "DNS resolution timed out after ${TimeoutMs}ms"
    }
    return $task.Result, $null
  } catch {
    return $null, "DNS resolution failed: $($_.Exception.Message)"
  }
}

function Invoke-PingRaw {
  param(
    [Parameter(Mandatory)][ValidateSet('IPv4', 'IPv6')]$Protocol,
    [Parameter(Mandatory)][string]$HostName,
    [Parameter(Mandatory)][int]$Count,
    [Parameter(Mandatory)][scriptblock]$ArgBuilder4,
    [Parameter(Mandatory)][scriptblock]$ArgBuilder6
  )

  $toolArgs = if ($Protocol -eq 'IPv6') { & $ArgBuilder6 $HostName $Count } else { & $ArgBuilder4 $HostName $Count }
  if ($toolArgs -isnot [System.Array]) { $toolArgs = @($toolArgs) }
  $raw = ping @toolArgs
  return [pscustomobject]@{ Raw = $raw; ExitCode = $LASTEXITCODE }
}

function Invoke-TracertRaw {
  param(
    [Parameter(Mandatory)][ValidateSet('IPv4', 'IPv6')]$Protocol,
    [Parameter(Mandatory)][string]$HostName,
    [Parameter(Mandatory)][scriptblock]$ArgBuilder
  )

  $sw = Get-ToolIpSwitch -Protocol $Protocol
  $toolArgs = & $ArgBuilder $($sw.Tracert) $HostName
  if ($toolArgs -isnot [System.Array]) { $toolArgs = @($toolArgs) }
  $raw = tracert @toolArgs
  return [pscustomobject]@{ Raw = $raw; ExitCode = $LASTEXITCODE }
}

function Invoke-PathpingRaw {
  param(
    [Parameter(Mandatory)][ValidateSet('IPv4', 'IPv6')]$Protocol,
    [Parameter(Mandatory)][string]$HostName,
    [Parameter(Mandatory)][scriptblock]$ArgBuilder
  )

  $sw = Get-ToolIpSwitch -Protocol $Protocol
  $toolArgs = & $ArgBuilder $($sw.Pathping) $HostName
  if ($toolArgs -isnot [System.Array]) { $toolArgs = @($toolArgs) }
  $raw = pathping @toolArgs
  return [pscustomobject]@{ Raw = $raw; ExitCode = $LASTEXITCODE }
}

function Test-TcpPort {
  param(
    [Parameter(Mandatory)][string]$HostName,
    [Parameter(Mandatory)][int]$Port,
    [int]$Hops = 20,
    [ValidateSet('IPv4', 'IPv6')]
    [string]$Protocol = 'IPv4',
    [int]$DnsTimeoutMs = 5000
  )

  $family = if ($Protocol -eq 'IPv6') { [System.Net.Sockets.AddressFamily]::InterNetworkV6 } else { [System.Net.Sockets.AddressFamily]::InterNetwork }
  $addrs, $dnsError = Get-HostAddressesWithTimeout -HostName $HostName -TimeoutMs $DnsTimeoutMs
  if ($dnsError) {
    return [pscustomobject]@{ TcpTestSucceeded = $false; TraceRoute = $null; DnsError = $dnsError }
  }

  $addr = $addrs | Where-Object { $_.AddressFamily -eq $family } | Select-Object -First 1
  if (-not $addr) {
    return [pscustomobject]@{ TcpTestSucceeded = $false; TraceRoute = $null; DnsError = "No $Protocol address for $HostName" }
  }

  $target = $addr.ToString()
  return (Test-NetConnection -ComputerName $target -Port $Port -TraceRoute -InformationLevel Detailed -Hops $Hops)
}

function Test-UdpPortBestEffort {
  param(
    [Parameter(Mandatory)][string]$HostName,
    [Parameter(Mandatory)][int]$Port,
    [Parameter(Mandatory)][ValidateSet('IPv4', 'IPv6')]$Protocol,
    [int]$TimeoutMs = 2000,
    [int]$DnsTimeoutMs = 5000
  )

  $result = [ordered]@{
    Host       = $HostName
    Port       = $Port
    Protocol   = 'UDP'
    Status     = 'Ambiguous'
    Detail     = ''
    DurationMs = 0
  }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $udp = $null
  try {
    $family = if ($Protocol -eq 'IPv6') { [System.Net.Sockets.AddressFamily]::InterNetworkV6 } else { [System.Net.Sockets.AddressFamily]::InterNetwork }
    $addrs, $dnsError = Get-HostAddressesWithTimeout -HostName $HostName -TimeoutMs $DnsTimeoutMs
    if ($dnsError) {
      $result.Detail = $dnsError
      return [pscustomobject]$result
    }

    $addr = $addrs | Where-Object { $_.AddressFamily -eq $family } | Select-Object -First 1
    if (-not $addr) {
      $result.Detail = "No $Protocol address for $HostName"
      return [pscustomobject]$result
    }

    $udp = [System.Net.Sockets.UdpClient]::new($family)
    $udp.Client.ReceiveTimeout = $TimeoutMs
    $udp.Connect($addr, $Port)

    $bytes = [byte[]]::new(0)
    [void]$udp.Send($bytes, 0)

    $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    try {
      [void]$udp.Receive([ref]$remote)
      $result.Status = 'Likely reachable'
      $result.Detail = 'Received datagram response'
    } catch [System.Net.Sockets.SocketException] {
      switch ($_.Exception.ErrorCode) {
        10054 { $result.Status = 'Path OK, port closed'; $result.Detail = 'ICMP Port Unreachable received' }
        10060 { $result.Status = 'Likely filtered'; $result.Detail = 'Receive timeout' }
        default { $result.Status = 'Likely filtered'; $result.Detail = "Socket error $($_.Exception.ErrorCode)" }
      }
    }
  }
  catch {
    $result.Status = 'Error'
    $result.Detail = $_.Exception.Message
  }
  finally {
    if ($udp) {
      try { $udp.Close() } catch { $null = $_ }
    }
    $sw.Stop()
    $result.DurationMs = [int]$sw.Elapsed.TotalMilliseconds
  }

  return [pscustomobject]$result
}

function Save-DiagnosticResults {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
    [Parameter(Mandatory)][string]$JsonPath,
    [Parameter(Mandatory)][string]$CsvPath
  )

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  $jsonContent = $Results | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText($JsonPath, $jsonContent, $utf8NoBom)

  $csvLines = $Results | Select-Object Timestamp, Round, Protocol, Host, PingOk, TracertOk, PathpingOk, Tcp443OK | ConvertTo-Csv -NoTypeInformation
  $csvContent = $csvLines -join [Environment]::NewLine
  [System.IO.File]::WriteAllText($CsvPath, $csvContent, $utf8NoBom)

  Write-Status -Level SUMMARY -Message "JSON: $JsonPath"
  Write-Status -Level SUMMARY -Message "CSV : $CsvPath"
}

function Get-RoundDefinitions {
  return @(
    @{
      Name = 'Standard'
      PingArgs4 = { param($h, $n) @('-4', '-n', "$n", $h) }
      PingArgs6 = { param($h, $n) @('-6', '-n', "$n", $h) }
      TracertArgs = { param($ipVer, $h) @($ipVer, '-d', '-h', "$TraceMaxHops", '-w', "$TraceTimeoutMs", $h) }
      PathpingArgs = { param($ipVer, $h) @($ipVer, '/q', "$PathpingProbes", '/w', "$PathpingTimeoutMs", $h) }
    }
    @{
      Name = 'MTU1400_DF'
      PingArgs4 = { param($h, $n) @('-4', '-f', '-l', '1400', '-n', "$n", $h) }
      PingArgs6 = { param($h, $n) @('-6', '-l', '1400', '-n', "$n", $h) }
      TracertArgs = { param($ipVer, $h) @($ipVer, '-d', '-h', "$TraceMaxHops", '-w', "$TraceTimeoutMs", $h) }
      PathpingArgs = { param($ipVer, $h) @($ipVer, '/q', "$PathpingProbes", '/w', "$PathpingTimeoutMs", $h) }
    }
    @{
      Name = 'TTL64_Timeout5s'
      PingArgs4 = { param($h, $n) @('-4', '-i', '64', '-w', '5000', '-n', "$n", $h) }
      PingArgs6 = { param($h, $n) @('-6', '-i', '64', '-w', '5000', '-n', "$n", $h) }
      TracertArgs = { param($ipVer, $h) @($ipVer, '-d', '-h', '64', '-w', '5000', $h) }
      PathpingArgs = { param($ipVer, $h) @($ipVer, '/q', "$PathpingProbes", '/w', '5000', $h) }
    }
  )
}

function Get-DiagnosticPlan {
  param(
    [Parameter(Mandatory)][array]$RoundDefinitions,
    [Parameter(Mandatory)][string[]]$SelectedProtocols,
    [Parameter(Mandatory)][string[]]$ResolvedHostsIPv4,
    [Parameter(Mandatory)][string[]]$ResolvedHostsIPv6
  )

  $plan = New-Object System.Collections.Generic.List[object]

  foreach ($round in $RoundDefinitions) {
    foreach ($proto in $SelectedProtocols) {
      $hosts = if ($proto -eq 'IPv6') { @($ResolvedHostsIPv6) } else { @($ResolvedHostsIPv4) }
      if (@($hosts).Count -eq 0) { continue }

      foreach ($h in $hosts) {
        if (-not (Test-HostNameSafe $h)) { continue }
        $plan.Add([pscustomobject]@{
          RoundName    = $round.Name
          RoundDef     = $round
          Protocol     = $proto
          Host         = $h
        })
      }
    }
  }

  return $plan
}

function Invoke-HostDiagnostics {
  param(
    [Parameter(Mandatory)][object]$PlanItem,
    [Parameter(Mandatory)][array]$PortTargets
  )

  $round = $PlanItem.RoundDef
  $proto = $PlanItem.Protocol
  $h = $PlanItem.Host

  $pingResult = Invoke-PingRaw -Protocol $proto -HostName $h -Count $PingCount -ArgBuilder4 $round.PingArgs4 -ArgBuilder6 $round.PingArgs6
  $trResult = Invoke-TracertRaw -Protocol $proto -HostName $h -ArgBuilder $round.TracertArgs

  $ppResult = if ($SkipPathping) {
    [pscustomobject]@{ Raw = @('Pathping skipped'); ExitCode = 0 }
  } else {
    Invoke-PathpingRaw -Protocol $proto -HostName $h -ArgBuilder $round.PathpingArgs
  }

  $tnc = Test-TcpPort -HostName $h -Port 443 -Hops 20 -Protocol $proto

  $portFindings = foreach ($t in $PortTargets) {
    if ($t.Protocol -eq 'TCP') {
      $tcp = Test-TcpPort -HostName $h -Port $t.Port -Hops 10 -Protocol $proto
      [pscustomobject]@{
        Name = $t.Name
        Protocol = 'TCP'
        Port = $t.Port
        Success = [bool]$tcp.TcpTestSucceeded
        Note = 'Test-NetConnection'
      }
    } else {
      $udp = Test-UdpPortBestEffort -HostName $h -Port $t.Port -Protocol $proto -TimeoutMs 2000
      [pscustomobject]@{
        Name = $t.Name
        Protocol = 'UDP'
        Port = $t.Port
        Success = ($udp.Status -eq 'Likely reachable')
        Note = "$($udp.Status): $($udp.Detail)"
      }
    }
  }

  return [pscustomobject]@{
    Timestamp = (Get-Date).ToString('o')
    Round = $round.Name
    Protocol = $proto
    Host = $h
    PingRaw = $pingResult.Raw
    PingOk = ($pingResult.ExitCode -eq 0)
    TracertRaw = $trResult.Raw
    TracertOk = ($trResult.ExitCode -eq 0)
    PathpingRaw = $ppResult.Raw
    PathpingOk = ($ppResult.ExitCode -eq 0)
    Tcp443OK = [bool]$tnc.TcpTestSucceeded
    TraceRoute = $tnc.TraceRoute
    Ports = $portFindings
  }
}

function Invoke-DiagnosticsMatrix {
  param(
    [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Plan,
    [Parameter(Mandatory)][array]$PortTargets,
    [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Results
  )

  $index = 0
  $total = $Plan.Count

  foreach ($item in $Plan) {
    $index++
    Write-Status -Level INFO -Message "RUN [$index/$total] round=$($item.RoundName) protocol=$($item.Protocol) host=$($item.Host)"

    $obj = Invoke-HostDiagnostics -PlanItem $item -PortTargets $PortTargets
    $Results.Add($obj)

    if ($obj.Tcp443OK) {
      Write-Status -Level OK -Message "round=$($item.RoundName) protocol=$($item.Protocol) host=$($item.Host) tcp443=OK"
    } else {
      Write-Status -Level FAIL -Message "round=$($item.RoundName) protocol=$($item.Protocol) host=$($item.Host) tcp443=FAIL"
    }
  }
}

if ([string]::IsNullOrWhiteSpace($LogDirectory)) {
  $LogDirectory = Get-DefaultLogDirectory
}

if (-not (Test-PathSafe $LogDirectory)) {
  throw "LogDirectory must not be empty, start with '-', contain '|', control chars, or path traversal (..): $LogDirectory"
}

$defaultHosts4 = @('netcologne.de', 'google.com', 'wikipedia.org', 'amazon.de')
$defaultHosts6 = @('netcologne.de', 'google.com', 'wikipedia.org')

$configHosts = Get-HostsFromConfig -Path $DefaultHostsConfig

if (-not $PSBoundParameters.ContainsKey('HostsIPv4')) {
  $HostsIPv4 = if (@($configHosts.IPv4).Count -gt 0) { @($configHosts.IPv4) } else { @($defaultHosts4) }
}
if (-not $PSBoundParameters.ContainsKey('HostsIPv6')) {
  $HostsIPv6 = if (@($configHosts.IPv6).Count -gt 0) { @($configHosts.IPv6) } else { @($defaultHosts6) }
}

$badHosts = @(@($HostsIPv4) + @($HostsIPv6) | Where-Object { -not (Test-HostNameSafe $_) })
if (@($badHosts).Count -gt 0) {
  throw "Host names must not start with '-', contain whitespace, '/', '|', or control characters: $($badHosts -join ', ')"
}

$roundDefinitions = @(Get-RoundDefinitions)
if ($null -ne $Rounds) {
  $requestedRounds = @($Rounds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
} else {
  $requestedRounds = @()
}
if (@($requestedRounds).Count -gt 0) {
  $selectedRoundDefs = @($roundDefinitions | Where-Object { $_.Name -in $requestedRounds })
  $missingRounds = @($requestedRounds | Where-Object { $_ -notin @($roundDefinitions.Name) })
  if (@($missingRounds).Count -gt 0) {
    throw "Unknown rounds: $($missingRounds -join ', '). Allowed: $($roundDefinitions.Name -join ', ')"
  }
  $roundDefinitions = $selectedRoundDefs
}

$selectedProtocols = @($Protocols | Select-Object -Unique)

$portTargets = @(
  [pscustomobject]@{ Name = 'Xbox Live'; Protocol = 'UDP'; Port = 3074 }
  [pscustomobject]@{ Name = 'Steam'; Protocol = 'UDP'; Port = 27015 }
  [pscustomobject]@{ Name = 'Steam'; Protocol = 'UDP'; Port = 27016 }
  [pscustomobject]@{ Name = 'Steam'; Protocol = 'UDP'; Port = 27017 }
  [pscustomobject]@{ Name = 'Steam'; Protocol = 'UDP'; Port = 27018 }
  [pscustomobject]@{ Name = 'HTTP'; Protocol = 'TCP'; Port = 80 }
  [pscustomobject]@{ Name = 'HTTPS'; Protocol = 'TCP'; Port = 443 }
)

$plan = Get-DiagnosticPlan -RoundDefinitions $roundDefinitions -SelectedProtocols $selectedProtocols -ResolvedHostsIPv4 @($HostsIPv4) -ResolvedHostsIPv6 @($HostsIPv6)
if ($plan.Count -eq 0) {
  throw 'No diagnostic runs planned. Check selected rounds/protocols/hosts.'
}

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$jsonPath = Join-Path $LogDirectory "net_results_$ts.json"
$csvPath = Join-Path $LogDirectory "net_summary_$ts.csv"

Write-Status -Level INFO -Message "Planned runs: $($plan.Count)"
Write-Status -Level INFO -Message "Protocols: $($selectedProtocols -join ', ')"
Write-Status -Level INFO -Message "Rounds: $($roundDefinitions.Name -join ', ')"
Write-Status -Level INFO -Message "IPv4 hosts: $(@($HostsIPv4) -join ', ')"
Write-Status -Level INFO -Message "IPv6 hosts: $(@($HostsIPv6) -join ', ')"

if ($DryRun) {
  Write-Status -Level SUMMARY -Message "Dry-run only. Planned runs: $($plan.Count)"
  Write-Status -Level SUMMARY -Message "Would write JSON: $jsonPath"
  Write-Status -Level SUMMARY -Message "Would write CSV : $csvPath"
  if (-not $Quiet) {
    $i = 0
    foreach ($item in $plan) {
      $i++
      Write-Status -Level PLAN -Message "[$i/$($plan.Count)] round=$($item.RoundName) protocol=$($item.Protocol) host=$($item.Host)"
    }
  }
  return
}

New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

$results = New-Object System.Collections.Generic.List[object]
$script:DiagnosticsCompletedNormally = $false
$start = Get-Date

Write-Status -Level INFO -Message "Starting diagnostics"

try {
  Invoke-DiagnosticsMatrix -Plan $plan -PortTargets $portTargets -Results $results
  Save-DiagnosticResults -Results @($results) -JsonPath $jsonPath -CsvPath $csvPath
  $script:DiagnosticsCompletedNormally = $true

  $elapsed = [int]((Get-Date) - $start).TotalSeconds
  $tcpFailures = @($results | Where-Object { -not $_.Tcp443OK }).Count
  $okCount = $results.Count - $tcpFailures
  Write-Status -Level SUMMARY -Message "Diagnostics complete. Passed: $okCount Failed: $tcpFailures Elapsed: ${elapsed}s"
}
finally {
  $resultsCount = $results.Count
  if ((-not [bool]$script:DiagnosticsCompletedNormally) -and ($resultsCount -gt 0)) {
    Write-Status -Level WARN -Message 'Interrupted or error: saving partial results.'
    Save-DiagnosticResults -Results @($results) -JsonPath $jsonPath -CsvPath $csvPath
  }
}

$anyTcpFail = $results | Where-Object { -not $_.Tcp443OK } | Select-Object -First 1
if ($anyTcpFail) {
  exit 1
}
