# Changelog

All notable changes to **mtr-test-suite**.

## [v0.9] - 2025-04-18
### Fixed
- Corrected reference to JSON field for packet loss (`"Loss%"`) to prevent `null` values.
- Enhanced table output to include both hostname and IP address for each hop.

## [v0.8] - 2025-04-16
### Added
- Combined JSON logging and human-readable table output for every test iteration.
- Implemented iterative logging that writes to both console and log file in real time.
- Introduced destination extraction logic to display target hostname and IP.

## [v0.7] - 2025-04-14
### Added
- Tabular summary function (`summarize_json`) to present statistics per hop in a clear table format alongside JSON.
- Integrated `jq` and `column` to format table output.

## [v0.6] - 2025-04-12
### Changed
- Removed `-I` option to enforce ICMP, using `-4`/`-6` for IPv4/IPv6 by default.
- Switched to `exec > >(tee -a ...) 2>&1` for global, iterative logging to prevent data loss.

## [v0.5] - 2025-04-10
### Added
- QoS/DSCP test rounds (`--dscp 40` for CS5, `--dscp 10` for AF11).
- TTL variation rounds (`-m 10` and `-m 64`) to uncover asymmetric paths and firewall TTL behaviors.

## [v0.4] - 2025-04-08
### Added
- TCP SYN tests on port 443 (`-T -P 443`) for both IPv4 and IPv6.
- MTU test round with 1400-byte packets to detect fragmentation issues.

## [v0.3] - 2025-04-06
### Changed
- Introduced `-b` flag in MTR calls to display both DNS names and IPs.

## [v0.2] - 2025-04-04
### Changed
- Increased packet count to 600 and interval to 0.5s for deeper statistical insight.

## [v0.1] - 2025-04-02
### Added
- Initial script: automated MTR tests for IPv4/IPv6, UDP, ICMP with timestamped JSON logs and live console output.
- Basic logging function and date-based log file naming.

