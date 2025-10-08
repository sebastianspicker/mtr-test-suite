<# 
.SYNOPSIS
  Extended Windows network diagnostics with ICMP, traceroute, path loss, TCP 443 checks, and best‑effort UDP gaming port probes.

.DESCRIPTION
  - Uses built-in Windows tools:
      * ping for ICMP, MTU/DF, TTL and timeouts (-l, -f, -i, -w) 
      * tracert for fast path discovery with DNS disabled (-d) and timeouts (-w) 
      * pathping for hop-by-hop loss/latency with probe and timeout tuning (/q, /w)
      * Test-NetConnection for TCP 443 port checks and optional route trace
  - Adds best‑effort UDP gaming tests (Xbox Live UDP 3074, Steam UDP 27015–27030) via a lightweight UdpClient probe
  - Writes structured JSON and compact CSV for downstream analysis

.NOTES
  - Requires PowerShell 5.1+; Test-NetConnection usage aligns with Windows Server and current client releases
  - UDP "reachability" is inherently ambiguous without an application-level response; the probe reports "Likely reachable", "Likely filtered", or "Ambiguous"
  - Run in an elevated PowerShell if QoS/DSCP policies are later added (not required for this script)

.LICENSE
  MIT-licensed sample; adapt as needed.

#>

[CmdletBinding(SupportsShouldProcess)]
param(
  # Destination hosts for IPv4
  [string[]]$HostsIPv4 = @('netcologne.de','google.com','wikipedia.org','amazon.de'),

  # Destination hosts for IPv6
  [string[]]$HostsIPv6 = @('netcologne.de','google.com','wikipedia.org'),

  # Output directory for logs
  [string]$LogDirectory = (Join-Path $env:USERPROFILE 'logs'),

  # Total ICMP echo count per ping run
  [int]$PingCount = 5,

  # Traceroute hop limit
  [int]$TraceMaxHops = 30,

  # Traceroute timeout (ms)
  [int]$TraceTimeoutMs = 5000,

  # Pathping probe count per hop
  [int]$PathpingProbes = 50,

  # Pathping timeout (ms)
  [int]$PathpingTimeoutMs = 3000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Timestamped output files
$ts       = Get-Date -Format 'yyyyMMdd_HHmmss'
$jsonPath = Join-Path $LogDirectory "net_results_$ts.json"
$csvPath  = Join-Path $LogDirectory "net_summary_$ts.csv"

# Ensure output directory exists
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

# Define diagnostic "rounds" similar to the MTR concept (vary MTU/DF, TTL, timeouts)
$Rounds = @(
  # Standard baseline
  @{
    Name        = 'Standard'
    PingArgs4   = { param($h,$n) "-4 -n $n $h" }
    PingArgs6   = { param($h,$n) "-6 -n $n $h" }
    TracertArgs = { param($ipVer,$h) "$ipVer -d -h $($TraceMaxHops) -w $($TraceTimeoutMs) $h" }
    PathpingArgs= { param($ipVer,$h) "$ipVer /q $($PathpingProbes) /w $($PathpingTimeoutMs) $h" }
  }
  # MTU 1400; DF for IPv4 only (IPv6 PMTU doesn’t fragment in transit)
  @{
    Name        = 'MTU1400_DF'
    PingArgs4   = { param($h,$n) "-4 -f -l 1400 -n $n $h" }
    PingArgs6   = { param($h,$n) "-6 -l 1400 -n $n $h" }  # no -f for IPv6
    TracertArgs = { param($ipVer,$h) "$ipVer -d -h $($TraceMaxHops) -w $($TraceTimeoutMs) $h" }
    PathpingArgs= { param($ipVer,$h) "$ipVer /q $($PathpingProbes) /w $($PathpingTimeoutMs) $h" }
  }
  # TTL and timeout emphasis
  @{
    Name        = 'TTL64_Timeout5s'
    PingArgs4   = { param($h,$n) "-4 -i 64 -w 5000 -n $n $h" }
    PingArgs6   = { param($h,$n) "-6 -i 64 -w 5000 -n $n $h" }
    TracertArgs = { param($ipVer,$h) "$ipVer -d -h 64 -w 5000 $h" }
    PathpingArgs= { param($ipVer,$h) "$ipVer /q $($PathpingProbes) /w 5000 $h" }
  }
)

# Gaming-related UDP/TCP target ports (add or adjust as needed)
$GamingTargets = @(
  [pscustomobject]@{ Name='Xbox Live'; Protocol='UDP'; Port=3074 }
  [pscustomobject]@{ Name='Steam';     Protocol='UDP'; Port=27015 }
  [pscustomobject]@{ Name='Steam';     Protocol='UDP'; Port=27016 }
  [pscustomobject]@{ Name='Steam';     Protocol='UDP'; Port=27017 }
  [pscustomobject]@{ Name='Steam';     Protocol='UDP'; Port=27018 }
  [pscustomobject]@{ Name='HTTP';      Protocol='TCP'; Port=80    }
  [pscustomobject]@{ Name='HTTPS';     Protocol='TCP'; Port=443   }
)

# Resolve which IP version switch to pass to tracert/pathping
function Get-ToolIpSwitch {
  param([ValidateSet('IPv4','IPv6')]$Protocol)
  if ($Protocol -eq 'IPv6') { 
    return @{
      Tracert = '-6'
      Pathping= '/6'
    }
  } else {
    return @{
      Tracert = '-4'
      Pathping= '/4'
    }
  }
}

# Run Windows ping with supplied arguments; returns raw console text
function Invoke-PingRaw {
  param(
    [Parameter(Mandatory)][ValidateSet('IPv4','IPv6')]$Protocol,
    [Parameter(Mandatory)][string]$Host,
    [Parameter(Mandatory)][int]$Count,
    [Parameter(Mandatory)][scriptblock]$ArgBuilder4,
    [Parameter(Mandatory)][scriptblock]$ArgBuilder6
  )
  $args = if ($Protocol -eq 'IPv6') { & $ArgBuilder6 $Host $Count } else { & $ArgBuilder4 $Host $Count }
  $cmd  = "ping $args"
  return (cmd /c $cmd)
}

# Run Windows tracert with supplied arguments (DNS disabled by -d for speed); returns raw console text
function Invoke-TracertRaw {
  param(
    [Parameter(Mandatory)][ValidateSet('IPv4','IPv6')]$Protocol,
    [Parameter(Mandatory)][string]$Host,
    [Parameter(Mandatory)][scriptblock]$ArgBuilder
  )
  $sw   = Get-ToolIpSwitch -Protocol $Protocol
  $args = & $ArgBuilder $($sw.Tracert) $Host
  $cmd  = "tracert $args"
  return (cmd /c $cmd)
}

# Run pathping (hop-by-hop loss/latency); returns raw console text
function Invoke-PathpingRaw {
  param(
    [Parameter(Mandatory)][ValidateSet('IPv4','IPv6')]$Protocol,
    [Parameter(Mandatory)][string]$Host,
    [Parameter(Mandatory)][scriptblock]$ArgBuilder
  )
  $sw   = Get-ToolIpSwitch -Protocol $Protocol
  $args = & $ArgBuilder $($sw.Pathping) $Host
  $cmd  = "pathping $args"
  return (cmd /c $cmd)
}

# TCP probe with Test-NetConnection (returns object with success/trace)
function Test-TcpPort {
  param(
    [Parameter(Mandatory)][string]$Host,
    [Parameter(Mandatory)][int]$Port,
    [int]$Hops = 20
  )
  return (Test-NetConnection -ComputerName $Host -Port $Port -TraceRoute -InformationLevel Detailed -Hops $Hops)
}

# Best-effort UDP probe: attempt to send a zero-byte datagram and detect "ICMP Port Unreachable" quickly.
function Test-UdpPortBestEffort {
  param(
    [Parameter(Mandatory)][string]$Host,
    [Parameter(Mandatory)][int]$Port,
    [int]$TimeoutMs = 2000
  )

  $result = [ordered]@{
    Host      = $Host
    Port      = $Port
    Protocol  = 'UDP'
    Status    = 'Ambiguous'
    Detail    = ''
    DurationMs= 0
  }

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $addr = [System.Net.Dns]::GetHostAddresses($Host) | Select-Object -First 1
    $udp  = [System.Net.Sockets.UdpClient]::new()
    $udp.Client.ReceiveTimeout = $TimeoutMs
    $udp.Connect($addr, $Port)

    $bytes = [byte[]](0)
    [void]$udp.Send($bytes, $bytes.Length)

    $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any,0)
    try {
      [void]$udp.Receive([ref]$remote)
      $result.Status = 'Likely reachable'
      $result.Detail = 'Received datagram response'
    } catch [System.Net.Sockets.SocketException] {
      switch ($_.Exception.ErrorCode) {
        10054 { $result.Status = 'Path OK, port closed'; $result.Detail = 'ICMP Port Unreachable received' }
        10060 { $result.Status = 'Likely filtered';        $result.Detail = 'Receive timeout' }
        default { $result.Status = 'Likely filtered';       $result.Detail = "Socket error $($_.Exception.ErrorCode)" }
      }
    }

    $udp.Close()
  }
  catch {
    $result.Status = 'Error'
    $result.Detail = $_.Exception.Message
  }
  finally {
    $sw.Stop()
    $result.DurationMs = [int]$sw.Elapsed.TotalMilliseconds
  }

  return [pscustomobject]$result
}

# Aggregate results
$all = New-Object System.Collections.Generic.List[object]

Write-Host "Starting diagnostics → logs will be saved to:`n  JSON: $jsonPath`n  CSV : $csvPath" -ForegroundColor Cyan

foreach ($round in $Rounds) {
  foreach ($proto in @('IPv4','IPv6')) {

    $hosts = if ($proto -eq 'IPv6') { $HostsIPv6 } else { $HostsIPv4 }
    if (-not $hosts -or $hosts.Count -eq 0) { continue }

    foreach ($h in $hosts) {
      Write-Host "[$($round.Name)] [$proto] → $h" -ForegroundColor Yellow

      # ICMP ping (single correct call per protocol)
      $pingRaw = Invoke-PingRaw -Protocol $proto -Host $h -Count $PingCount -ArgBuilder4 $round.PingArgs4 -ArgBuilder6 $round.PingArgs6

      # Traceroute (DNS disabled for speed)
      $trRaw = Invoke-TracertRaw -Protocol $proto -Host $h -ArgBuilder $round.TracertArgs

      # Pathping (hop-by-hop loss/latency)
      $ppRaw = Invoke-PathpingRaw -Protocol $proto -Host $h -ArgBuilder $round.PathpingArgs

      # TCP 443 test with optional route trace
      $tnc = Test-TcpPort -Host $h -Port 443 -Hops 20

      # UDP/TCP gaming probes (best-effort UDP)
      $portFindings = foreach ($t in $GamingTargets) {
        if ($t.Protocol -eq 'TCP') {
          $tcp = Test-TcpPort -Host $h -Port $t.Port -Hops 10
          [pscustomobject]@{
            Name     = $t.Name
            Protocol = 'TCP'
            Port     = $t.Port
            Success  = [bool]$tcp.TcpTestSucceeded
            Note     = 'Test-NetConnection'
          }
        } else {
          $udp = Test-UdpPortBestEffort -Host $h -Port $t.Port -TimeoutMs 2000
          [pscustomobject]@{
            Name     = $t.Name
            Protocol = 'UDP'
            Port     = $t.Port
            Success  = ($udp.Status -eq 'Likely reachable')
            Note     = "$($udp.Status): $($udp.Detail)"
          }
        }
      }

      # Build a structured object per host/round/protocol
      $obj = [pscustomobject]@{
        Timestamp   = (Get-Date).ToString('o')
        Round       = $round.Name
        Protocol    = $proto
        Host        = $h
        PingRaw     = $pingRaw
        TracertRaw  = $trRaw
        PathpingRaw = $ppRaw
        Tcp443OK    = [bool]$tnc.TcpTestSucceeded
        TraceRoute  = $tnc.TraceRoute
        Ports       = $portFindings
      }

      $all.Add($obj)

      # Console summary with separate color variable (PowerShell 5.1 friendly)
      $color = if ($obj.Tcp443OK) { 'Green' } else { 'Red' }
      Write-Host ("  TCP:443 → {0}" -f ($(if ($obj.Tcp443OK) { 'OK' } else { 'FAIL' }))) -ForegroundColor $color
    }
  }
}

# Persist artifacts (JSON for details, CSV for quick diff)
$all | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -Path $jsonPath
$all |
  Select-Object Timestamp,Round,Protocol,Host,Tcp443OK |
  Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csvPath

Write-Host "Diagnostics complete." -ForegroundColor Cyan
Write-Host "JSON: $jsonPath"
Write-Host "CSV : $csvPath"
