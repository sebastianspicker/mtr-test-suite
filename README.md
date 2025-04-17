# mtr-test-suite

A comprehensive, automated MTR‑based network path testing suite with JSON logging, DSCP/QoS, MTU & TTL variations, and live console output.

---

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

---

## Overview

`mtr-test-suite` is a Bash script that automates advanced network path analysis using MTR. It runs multiple test rounds against a predefined list of hosts, capturing latency, packet loss, jitter, and routing behavior under a variety of protocols and conditions. All results are output in JSON format with timestamps, displayed live on your console, and archived to datestamped log files for later inspection or automated processing.

---

## Features

- **Multiple Protocols**  
  - ICMP (default)  
  - UDP  
  - TCP on port 443  

- **MTU / Fragmentation Tests**  
  - 1400‑byte packets to surface MTU mismatches and fragmentation issues  

- **QoS / DSCP Marking**  
  - DSCP CS5 (high priority)  
  - DSCP AF11 (lower priority)  

- **TTL Variations**  
  - Limit to 10 hops  
  - Extend to 64 hops  

- **Machine‑Readable JSON Output**  
  - Ideal for `jq` parsing or time‑series database ingestion  

- **Live Console Logging**  
  - Real‑time progress and results via `tee`  

- **Robust Error Handling**  
  - `set -euo pipefail` plus per‑test fallback logic  

---

## Prerequisites

- **Bash** (v4.x or later)  
- **MTR** (with JSON support)  
- **jq** (optional, for JSON parsing)  

On Debian/Ubuntu:
```bash
sudo apt update
sudo apt install bash mtr jq
```
On CentOS/RHEL:
```bash
sudo yum install epel-release
sudo yum install bash mtr jq
```

---

## Installation

1. Clone the repository
   ```bash
   git clone https://github.com/yourusername/mtr-test-suite.git
   cd mtr-test-suite
   ```
2. Make the script executable
   ```bash
   chmod +x mtr-tests-enhanced.sh
   ```

---

## Usage 

Run the script directly:
```bash
./mtr-tests-enhanced.sh
```

Or explicitly with Bash:
```bash
Or explicitly with Bash:
```

By default, results will be written to:
```bash
$HOME/logs/mtr_results_YYYYMMDD_HHMMSS.log
```

---

## Configuration

### Host Lists
Edit the top of the script to customize your target hosts:
```bash
HOSTS_IPV4=( netcologne.de google.com wikipedia.org amazon.de )
HOSTS_IPV6=( netcologne.de google.com wikipedia.org )
```

### Test Rounds
Modify or extend the ```ROUNDS``` associative array:
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
Adjust the ```TESTS``` array to add or remove protocols:
```bash
declare -A TESTS=(
  [IPv4]="-4"
  [IPv6]="-6"
  [UDP4]="-u -4"
  [UDP6]="-u -6"
  [ICMP4]="-I -4"
  [ICMP6]="-I -6"
  [TCP4]="-T -P 443 -4"
  [TCP6]="-T -P 443 -6"
)
```

## Logging & Output
- Live Console: All test progress and JSON output are streamed live.
- Log Files: Each run produces a uniquely timestamped file under ```~/logs/```.
- Parsing: Use ```jq``` to extract metrics:
```bash
jq '.report.hubs[] | {hop: .count, Loss: .Loss%, Avg: .Avg}' ~/logs/mtr_results_*.log
```

## Advanced Integration
- Alerting: Wrap the script in a cron job and add post‑run threshold checks to notify via email, Slack, or Telegram.
- Time‑Series DB: Convert JSON to line protocol (InfluxDB) or Prometheus push format for dashboards.
- Geo/ASN Enrichment: Pipe each hop’s IP through ```geoiplookup``` or ```whois``` for location and network information.
- Parallel Execution: Use GNU ```parallel``` to speed up tests across multiple hosts.
