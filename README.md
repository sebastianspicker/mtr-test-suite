# mtr-test-suite v1.0

An advanced, automated MTR-based network path testing suite with JSON logging, DSCP/TOS, MTU & TTL variations, MPLS & AS‑lookup, and live console output.

## Table of Contents

1. [Overview](#overview)  
2. [Features](#features)  
3. [Prerequisites](#prerequisites)  
4. [Installation](#installation)  
5. [Quickstart](#quickstart)  
6. [Usage](#usage)  
7. [Configuration](#configuration)  
8. [Logging & Output](#logging--output)  
9. [Advanced Integration](#advanced-integration)  
10. [Development](#development)  
11. [Testing](#testing)  
12. [Security](#security)  
13. [Troubleshooting](#troubleshooting)  
14. [Changelog](#changelog)  
15. [Contributing](#contributing)  
16. [License](#license)

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

### Linux/macOS (Bash suite)

- **Bash** (v4.x+ required to run the full suite)  
- **MTR** (with `--json`, MPLS, AS‑lookup support)  
- **jq**  
- **column** (`util-linux`)

**Debian/Ubuntu**:
```bash
sudo apt update
sudo apt install bash jq util-linux
sudo apt install mtr # package name may also be: mtr-tiny
```
**CentOS/RHEL**:
```bash
sudo yum install epel-release
sudo yum install bash mtr jq util-linux
```

**macOS (Homebrew)**:
```bash
brew install bash mtr jq
```
Note: macOS ships Bash 3.2 by default; the suite requires Bash 4+.

### Windows (PowerShell suite)

- PowerShell 5.1+
- Built-in tools: `ping`, `tracert`, `pathping`, `Test-NetConnection`

## Installation

```bash
git clone https://github.com/<your-org>/mtr-test-suite.git
cd mtr-test-suite
chmod +x mtr-test-suite.sh mtr-tests-enhanced.sh mtr-test-suite_min-comments.sh
```

## Quickstart

Linux/macOS:
```bash
./mtr-test-suite.sh --dry-run --no-summary
./mtr-test-suite.sh
```

Windows:
```powershell
powershell -ExecutionPolicy Bypass -File .\NetTestSuite.ps1
```

## Usage

### Linux/macOS (Bash suite)

```bash
./mtr-test-suite.sh
```

Note: depending on how `mtr` is installed on your system, some probe types may require elevated privileges (e.g. `sudo`) or `cap_net_raw`.

Wrappers:
- `mtr-tests-enhanced.sh` (legacy entrypoint)
- `mtr-test-suite_min-comments.sh` (legacy/minimal header)

Both wrappers exec the canonical `mtr-test-suite.sh`.

Abort anytime with **Ctrl+C**; partial results remain saved.

### Options

```bash
./mtr-test-suite.sh --help
./mtr-test-suite.sh --log-dir /var/log/mtr-suite
./mtr-test-suite.sh --json-log ./mtr.json.log --table-log ./mtr.table.log
./mtr-test-suite.sh --no-summary     # JSON only (no jq/column)
./mtr-test-suite.sh --dry-run        # print planned runs
```

### Running as a Background Job

To launch the suite detached from your terminal:
```bash
nohup ./mtr-test-suite.sh > /dev/null 2>&1 &
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

### Windows (PowerShell suite)

```powershell
powershell -ExecutionPolicy Bypass -File .\NetTestSuite.ps1
```

Outputs:
- JSON: `%USERPROFILE%\logs\net_results_<timestamp>.json`
- CSV:  `%USERPROFILE%\logs\net_summary_<timestamp>.csv`

## Configuration

### Hosts

Edit in `mtr-test-suite.sh`:
```bash
HOSTS_IPV4=( netcologne.de google.com wikipedia.org amazon.de )
HOSTS_IPV6=( netcologne.de google.com wikipedia.org )
```

### Test Types

Adjust or extend the `TESTS` mapping in `mtr-test-suite.sh`:
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

Modify the `ROUNDS` array in `mtr-test-suite.sh`:
```bash
declare -A ROUNDS=(
  [Standard]="",
  [MTU1400]="-s 1400",
  [TOS_CS5]="--tos 160",
  [TOS_AF11]="--tos 40",
  [TTL10]="-m 10",
  [TTL64]="-m 64",
  [FirstTTL3]="-f 3",
  [Timeout5]="-Z 5",
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

## Development

```bash
make validate

shfmt -w -i 2 -ci mtr-test-suite.sh mtr-tests-enhanced.sh mtr-test-suite_min-comments.sh
shellcheck -x mtr-test-suite.sh mtr-tests-enhanced.sh mtr-test-suite_min-comments.sh
```

See `docs/RUNBOOK.md` for the full command matrix.

## Testing

Fast smoke test (no network probes):
```bash
./mtr-test-suite.sh --dry-run --no-summary
```

Full suite (long-running):
```bash
./mtr-test-suite.sh
```

## Security

Please report vulnerabilities privately. See [SECURITY.md](SECURITY.md).

Notes:
- Running probes may require elevated privileges or `cap_net_raw`.
- Do not include secrets in logs or issue reports.

## Troubleshooting

- `Bash 4+ required` → install a newer bash and run `bash ./mtr-test-suite.sh`.
- `Missing dependency: mtr` → install `mtr` and ensure it supports `--json`.
- `column: command not found` → install `util-linux` (Linux) or `column` via Homebrew.
- Permission errors → run with `sudo` or set `cap_net_raw` for `mtr`.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

See [LICENSE](LICENSE).
