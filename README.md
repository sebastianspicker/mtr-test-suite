# mtr-test-suite v1.0

An advanced, automated MTR-based network path testing suite with JSON logging, DSCP/TOS, MTU & TTL variations, MPLS & AS‑lookup, and live console output.

## Table of Contents

1. [Overview](#overview)  
2. [Features](#features)  
3. [Prerequisites](#prerequisites)  
4. [Installation](#installation)  
5. [Usage](#usage)  
6. [Configuration](#configuration)  
7. [Logging & Output](#logging--output)  
8. [Advanced Integration](#advanced-integration)  
9. [Changelog](#changelog)  
10. [Contributing](#contributing)  
11. [License](#license)

## Overview

`mtr-test-suite` v1.0 is a Bash script that automates comprehensive network path analysis using MTR. It runs multiple test rounds against a set of hosts, capturing latency, packet loss, jitter, and routing behaviors under diverse protocols and conditions. It produces:

- **JSON_LOG**: raw per-run JSON output archived to `mtr_results_<timestamp>.json.log`  
- **TABLE_LOG**: human-readable summaries archived to `mtr_summary_<timestamp>.log`  
- **Console**: real-time progress, errors, and table output

Estimated runtime with defaults (~280 runs × 5 min each ≈ 24 hours).

## Features

- **Protocol Coverage**  
  - ICMP (IPv4 & IPv6)  
  - UDP (IPv4 & IPv6)  
  - TCP (port 443 IPv4 & IPv6)  
  - MPLS label stack (`-e`)  
  - AS‑lookup (`-z --aslookup`)
- **Test Scenarios**  
  - Standard  
  - MTU 1400-byte (`-s 1400`)  
  - DSCP/TOS CS5 (`--tos 160`), AF11 (`--tos 40`)  
  - TTL variation: 10, 64, first run at TTL 3 (`-f 3`)  
  - Socket timeout extension (`-Z 5`)
- **Dual Logging**  
  - Raw JSON for automated parsing  
  - Tabular summaries for human readability
- **Live Console Output**  
  - Progress & errors via `log()`  
  - Table display via `jq` + `column`
- **Robust Error Handling**  
  - `set -euo pipefail`  
  - Per-test fallback ensures suite continues on failures

## Prerequisites

- **Bash** (v4.x+)  
- **MTR** (with JSON, MPLS, AS‑lookup support)  
- **jq**  
- **column** (GNU coreutils)

**Debian/Ubuntu**:
```bash
sudo apt update
sudo apt install bash mtr jq coreutils
```
**CentOS/RHEL**:
```bash
sudo yum install epel-release
sudo yum install bash mtr jq coreutils
```

## Installation

```bash
git clone https://github.com/<your-org>/mtr-test-suite.git
cd mtr-test-suite
chmod +x mtr-tests-enhanced.sh
```

## Usage

```bash
./mtr-tests-enhanced.sh
```

Abort anytime with **Ctrl+C**; partial results remain saved.

### Running as a Background Job

To launch the suite detached from your terminal:
```bash
nohup bash mtr-tests-enhanced.sh > /dev/null 2>&1 &
```
This will continue running after you log out.

To follow the raw JSON logs in real time:
```bash
tail -f ~/logs/mtr_results_*.json.log
```

To follow the human-readable summaries in real time:
```bash
tail -f ~/logs/mtr_summary_*.log
```

## Configuration

### Hosts

Edit at top of script:
```bash
HOSTS_IPV4=( netcologne.de google.com wikipedia.org amazon.de )
HOSTS_IPV6=( netcologne.de google.com wikipedia.org )
```

### Test Types

Adjust or extend `TESTS` mapping:
```bash
declare -A TESTS=(
  [ICMP4]="-4 -b ...",
  [UDP4] ="-u -4 -b ...",
  [MPLS4]="-e -4 ...",
  [AS4]  ="-z --aslookup -4 ...",
  …
)
```

### Rounds

Modify `ROUNDS` array:
```bash
declare -A ROUNDS=(
  [Standard]="",
  [MTU1400]="-s 1400",
  [TOS_CS5]="--tos 160",
  [DSCP_AF11]="--tos 40",
  [TTL10]="-m 10",
  [TTL64]="-m 64",
  [FirstTTL3]="-f 3",
  [Timeout5]="-Z 5",
)
```

## Logging & Output

- **JSON_LOG**: `~/logs/mtr_results_<timestamp>.json.log`  
- **TABLE_LOG**: `~/logs/mtr_summary_<timestamp>.log`  
- **Console**: real-time progress & table display

**Parse JSON**:
```bash
jq '.report.hubs[] | {hop: .count, loss: ."Loss%", avg: .Avg}' ~/logs/*.json.log
```

## Advanced Integration

- **Cron & Alerts**: schedule and parse logs for threshold breaches  
- **Time‑Series DB**: convert JSON to InfluxDB/Prometheus format  
- **Geo/ASN Enrichment**: add `geoiplookup`/`whois` in `summarize_json()`

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
