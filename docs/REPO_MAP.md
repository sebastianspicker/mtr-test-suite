# REPO MAP

## Overview

This repository provides a cross-platform network diagnostic suite:

- `mtr-test-suite.sh`: primary Bash-based MTR test matrix (Linux/macOS)
- `mtr-tests-enhanced.sh`: wrapper to the primary script (legacy entrypoint)
- `mtr-test-suite_min-comments.sh`: wrapper to the primary script (legacy entrypoint)
- `NetTestSuite.ps1`: Windows PowerShell diagnostic suite (ping, tracert, pathping, TCP/UDP probes)

## Entry Points

- Linux/macOS: `./mtr-test-suite.sh`
- Windows: `NetTestSuite.ps1`

## Key Flows

### Bash Suite (`mtr-test-suite.sh`)

1. Parse CLI args and validate dependencies (bash 4+, `mtr`, `jq`, `column`).
2. Prepare log files in `~/logs` (or `--log-dir`).
3. Define test types (`TESTS`) and rounds (`ROUNDS`).
4. Nested loop: round → test type → host.
5. Execute `mtr` per case, append JSON to `JSON_LOG`.
6. Optional summary rendering via `jq` + `column` into `TABLE_LOG`.

### PowerShell Suite (`NetTestSuite.ps1`)

1. Iterate rounds and protocols (IPv4/IPv6) per host list.
2. Execute `ping`, `tracert`, `pathping`, `Test-NetConnection`.
3. Optional best-effort UDP probes.
4. Persist JSON and CSV summaries.

## Build / Tooling

- `Makefile`: formatting/linting/validation via `shfmt` and `shellcheck`.
- CI: `.github/workflows/ci.yml` runs `make validate`.

## Data / Logs

- Bash suite logs to `~/logs` by default:
  - `mtr_results_<timestamp>.json.log`
  - `mtr_summary_<timestamp>.log`
- PowerShell logs to `%USERPROFILE%\logs`:
  - `net_results_<timestamp>.json`
  - `net_summary_<timestamp>.csv`

## Hot Spots / Risk Areas

- Long-running test matrix (runtime and resource usage).
- External dependencies (`mtr`, `jq`, `column`) and their availability.
- Probe privileges (`cap_net_raw`, `sudo`) may vary by OS.
- JSON parsing/summary relies on `jq` schema compatibility with `mtr --json`.
