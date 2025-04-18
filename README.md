# mtr-test-suite

A comprehensive, automated MTR‑based network path testing suite with JSON logging, DSCP/QoS, MTU & TTL variations, and live console output.

## Table of Contents

1. [Overview](#overview)  
2. [Features](#features)  
3. [Prerequisites](#prerequisites)  
4. [Installation](#installation)  
5. [Usage](#usage)  
6. [Configuration](#configuration)  
7. [Logging & Output](#logging--output)  
8. [Advanced Integration](#advanced-integration)  
9. [Contributing](#contributing)  
10. [License](#license)

## Overview

`mtr-test-suite` is a Bash script that automates advanced network path analysis using MTR. It runs multiple test rounds against a predefined list of hosts, capturing latency, packet loss, jitter, and routing behavior under a variety of protocols and conditions. All results are output in JSON format with timestamps, displayed live on your console, and archived to datestamped log files for later inspection or automated processing.

## Features

- **Protocol Coverage**  
  - ICMP (IPv4 & IPv6)  
  - UDP (IPv4 & IPv6)  
  - TCP on port 443 (IPv4 & IPv6)
- **MTU / Fragmentation Tests**  
  - 1400‑byte packet sizing to detect MTU mismatches
- **QoS / DSCP Marking**  
  - DSCP CS5 (high priority)  
  - DSCP AF11 (lower priority)
- **TTL Variations**  
  - TTL limit to 10 hops  
  - TTL extension to 64 hops
- **Machine‑Readable JSON Output**  
  - Ideal for `jq` parsing or ingestion into time‑series databases
- **Live Console Logging**  
  - Real‑time progress and results via `tee`
- **Robust Error Handling**  
  - `set -euo pipefail` with per‑test fallback logic ensures uninterrupted suite execution

## Prerequisites

- **Bash** (v4.x or later)  
- **MTR** (with JSON support)  
- **jq**  

**Debian / Ubuntu**:
```bash
sudo apt update
sudo apt install bash mtr jq
```
**CentOS / RHEL**:
```bash
sudo yum install epel-release
sudo yum install bash mtr jq
```

## Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/<your-org>/mtr-test-suite.git
   cd mtr-test-suite
   ```
2. **Make the script executable**:
   ```bash
   chmod +x mtr-tests-enhanced.sh
   ```

## Usage

Run the suite directly:
```bash
./mtr-tests-enhanced.sh
```
Or explicitly via Bash:
```bash
bash mtr-tests-enhanced.sh
```

Press **Ctrl+C** to abort at any time—partial results will remain in the log.

By default, results are written to:
```bash
$HOME/logs/mtr_results_YYYYMMDD_HHMMSS.log
```

## Configuration

### Host Lists

At the top of the script, configure your target hosts:
```bash
HOSTS_IPV4=( netcologne.de google.com wikipedia.org amazon.de )
HOSTS_IPV6=( netcologne.de google.com wikipedia.org )
```

### Test Scenarios

Adjust the `ROUNDS` associative array for custom test rounds:
```bash
declare -A ROUNDS=(
  [Standard]=""
  [MTU1400]="-s 1400"
  [DSCP_CS5]="--dscp 40"
  [DSCP_AF11]="--dscp 10"
  [TTL10]="-m 10"
  [TTL64]="-m 64"
)
```

### Protocol Types

Modify the `TESTS` mapping to add or remove protocols:
```bash
declare -A TESTS=(
  [ICMP4]="-4 -n -b -i 1 -c 300 -r --json"
  [ICMP6]="-6 -n -b -i 1 -c 300 -r --json"
  [UDP4]="-u -4 -n -b -i 1 -c 300 -r --json"
  [UDP6]="-u -6 -n -b -i 1 -c 300 -r --json"
  [TCP4]="-T -P 443 -4 -n -b -i 1 -c 300 -r --json"
  [TCP6]="-T -P 443 -6 -n -b -i 1 -c 300 -r --json"
)
```

## Logging & Output

- **Live Console**: All test progress and raw JSON are streamed to your terminal.  
- **Log Files**: Each run creates a timestamped log in `~/logs/`.  
- **JSON Parsing**: Extract key metrics with `jq`:
  ```bash
  jq '.report.hubs[] | {hop: .count, loss: ."Loss%", avg: .Avg}' ~/logs/mtr_results_*.log
  ```

## Advanced Integration

- **Alerting**: Schedule in cron and parse CSV/JSON for threshold breaches to send emails or Slack notifications.  
- **Time‑Series DB**: Convert JSON entries to InfluxDB line protocol or Prometheus pushgateway format.  
- **GeoIP & ASN Enrichment**: Pipe hop IPs through `geoiplookup` and `whois` for location/network details.  
- **Parallel Execution**: Use GNU `parallel` to run separate hosts or rounds concurrently.
