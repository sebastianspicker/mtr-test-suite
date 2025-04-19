# Changelog

All notable changes to **mtr-test-suite**.

## [v1.0] - 2025-04-20
### Added
- **Dual Log Files**: Raw JSON output is now written to a separate `JSON_LOG` (`mtr_results_TIMESTAMP.json.log`), and human‑readable tables to `TABLE_LOG` (`mtr_summary_TIMESTAMP.log`).
- **Enhanced Table Formatting**: Hostnames are no longer truncated; columns are widened to accommodate long names. Missing IPs show `N/A`, so Loss% and subsequent columns remain aligned.
- **New Test Types**:
  - **MPLS** tests (`-e`) for MPLS label stack inspection.
  - **AS‑lookup** tests (`-z --aslookup`) to display autonomous system numbers per hop.
- **Additional Rounds**:
  - **FirstTTL3** (`-f 3`): start probing from TTL=3.
  - **Timeout5** (`-Z 5`): extend socket grace time to 5 s per hop.
- **Header Update**: Bumped to v1.0 and updated estimated runtime to ~280 runs × 5 min ≈ 24 h.

## [v0.9] - 2025-04-18
### Fixed
- JSON field parsing for destination name/IP: added robust fallbacks to avoid `null`.
- Packet loss (`"Loss%"`) extraction corrected to prevent empty or misaligned values.
- Table generation regex improved to reliably handle hostnames and IPs in separate columns.

## [v0.8] - 2025-04-16
### Added
- Combined raw JSON logging with immediate table summaries in Bash.
- Switched global logging to `exec > >(tee -a ...) 2>&1` for real‑time console+file output.
- Destination extraction logic introduced to display target name and IP in summary header.

## [v0.7] - 2025-04-14
### Added
- `summarize_json()` function: formats per‑hop metrics into neat tables using `jq` + `column`.
- Integrated `jq` for JSON parsing and `column -t` for alignment.

## [v0.6] - 2025-04-12
### Changed
- Removed `-n` (no‑dns) to allow reverse DNS lookups by default.
- Adopted global `tee` redirection to ensure no output is lost between console and log file.

## [v0.5] - 2025-04-10
### Added
- QoS/TOS test rounds: DSCP CS5 (`--tos 160`) and AF11 (`--tos 40`).
- TTL variation rounds: `-m 10` and `-m 64` for limiting/extending hop counts.

## [v0.4] - 2025-04-08
### Added
- TCP SYN tests on port 443 (`-T -P 443`) for both IPv4 and IPv6.
- MTU probe round with 1400‑byte packets (`-s 1400`) to detect fragmentation.

## [v0.3] - 2025-04-06
### Changed
- Added `-b` (show-ips) flag to display both hostnames and IP addresses in `mtr` output.

## [v0.2] - 2025-04-04
### Changed
- Increased ping count to 300 (`-c 300`) and interval to 1 s (`-i 1`) for deeper per‑hop statistics.

## [v0.1] - 2025-04-02
### Added
- Initial release: automated MTR tests for ICMP and UDP (IPv4/IPv6) with timestamped JSON logs and live console output.
- Basic logging function with date‑based filenames.

---
*See [README.md](README.md) for usage and configuration details.*

