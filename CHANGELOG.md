# Changelog

All notable changes to **mtr-test-suite**.

## [v0.9] - 2025-04-18
### Fixed
- **JSON field parsing**: Improved fallback logic for `.report.dst_name` / `.report.dst_addr` / `.report.dst_ip` / `.report.mtr.dst` to avoid `null` targets.  
- **Packet loss display**: Corrected extraction of the `"Loss%"` field so that actual numeric values are shown instead of `null`.  
- **Hostname/IP extraction**: Enhanced regex to reliably separate hostnames and IPs (captured from `host` or `.ip`), ensuring both appear in the summary table.

## [v0.8] - 2025-04-16
### Added
- **Real‑time JSON + table output**: Merged raw JSON capture with immediate, human‑readable table display for every host/test iteration.  
- **Iterative logging**: Switched to `exec > >(tee -a …) 2>&1` so that all stdout/stderr—including `mtr --json`—streams live to console and log file.  
- **Destination extraction**: Introduced robust logic to extract and print the target’s DNS name and IP address in the summary header.

## [v0.7] - 2025-04-14
### Added
- **`summarize_json()`**: New function that formats each hop’s metrics into a well‑aligned table using `jq` + `column`.  
- **Dependency integration**: Leveraged `jq` for JSON parsing and `column -t` for neat tabular output directly in Bash.

## [v0.6] - 2025-04-12
### Changed
- **ICMP enforcement**: Removed explicit `-I` option; now default ICMP tests use `-4`/`-6` flags for IPv4/IPv6.  
- **Global logging overhaul**: Adopted `exec > >(tee -a LOGFILE) 2>&1` to guarantee no output is lost, replacing piecemeal redirections.

## [v0.5] - 2025-04-10
### Added
- **DSCP QoS tests**: Rounds for `--dscp 40` (CS5) and `--dscp 10` (AF11) to simulate high‑ and low‑priority traffic classes.  
- **TTL variation rounds**: New scenarios limiting hop count to 10 (`-m 10`) and extending to 64 (`-m 64`) to reveal asymmetric paths and TTL expiry behaviors.

## [v0.4] - 2025-04-08
### Added
- **TCP SYN tests**: Support for TCP on port 443 (`-T -P 443`) over both IPv4 and IPv6 to verify firewall and router handling.  
- **MTU Round**: Introduced `-s 1400` tests to detect fragmentation or MTU mismatches early.

## [v0.3] - 2025-04-06
### Changed
- **Hostname & IP display**: Added `-b` (both) option in `mtr` calls to ensure DNS names and IP addresses appear in combined output.

## [v0.2] - 2025-04-04
### Changed
- **Increased statistical depth**: Packet count bumped to 300 per round and interval lowered to 1s for richer per‑hop metrics. (Earlier drafts used 600/0.5s.)

## [v0.1] - 2025-04-02
### Added
- **Initial release**: Basic Bash automation of `mtr -4/-6` tests for ICMP and UDP, with per‑run JSON logging and timestamped log filenames.  
- **Live console feedback**: Simple `log()` function added to prepend timestamps and guide the user through each test step.
