# Changelog

All notable changes to **mtr-test-suite**.

## [Unreleased]

- No unreleased changes yet.

## [v1.1.0] - 2026-03-01

### Added

- Shared host defaults file: `config/hosts.conf` used by both Bash and PowerShell suites.
- Bash CLI filters and discoverability:
  - `--types`, `--rounds`, `--hosts4`, `--hosts6`
  - `--list-types`, `--list-rounds`
- PowerShell parity controls:
  - `-Protocols`, `-Rounds`, `-DryRun`, `-Quiet`
- Standardized run progress/final summary output with stable `OK`/`FAIL`/`WARN`/`SUMMARY` tokens.
- README execution and lifecycle Mermaid diagrams.

### Changed

- Documentation consolidated to canonical set:
  - `README.md`
  - `docs/RUNBOOK.md`
  - `CONTRIBUTING.md`
  - `SECURITY.md`
  - `CHANGELOG.md`
- Runbook now contains troubleshooting quick-reference and release checklist.
- Bash and PowerShell dry-run flows print planned run counts and output destinations.
- README install snippet now uses the concrete GitHub repository URL.

### Fixed

- PowerShell log directory portability: resolves home via `USERPROFILE`, then `HOME`, then current location fallback.
- PowerShell StrictMode-safe counting by normalizing collections with `@(...).Count`.
- PowerShell interrupt/error partial-save guard no longer throws when result collection is empty.
- Bash CSV option parsing now fails fast on malformed separators.
- Bash failed-run marker generation no longer requires `jq` in `--no-summary` paths.

### Refactored

- Bash orchestration split into dedicated planning/execution helpers.
- PowerShell orchestration split into:
  - `Get-DiagnosticPlan`
  - `Invoke-HostDiagnostics`
  - `Invoke-DiagnosticsMatrix`
- CI helper scripts retain shared install utility and bash resolution simplifications.

## [v1.0] - 2025-04-20

### Added

- Dual log files for Bash (`JSON_LOG` and `TABLE_LOG`).
- Enhanced table formatting.
- MPLS (`-e`) and AS-lookup (`-z --aslookup`) test types.
- Additional rounds (`FirstTTL3`, `Timeout5`).

## [v0.9] - 2025-04-18

### Fixed

- JSON destination and packet-loss parsing improvements.

## [v0.8] - 2025-04-16

### Added

- Combined raw JSON logging with immediate table summaries in Bash.

## [v0.7] - 2025-04-14

### Added

- `summarize_json()` table output via `jq` + `column`.

## [v0.6] - 2025-04-12

### Changed

- Reverse DNS enabled by default (removed `-n`).

## [v0.5] - 2025-04-10

### Added

- QoS/TOS rounds and TTL variation rounds.

## [v0.4] - 2025-04-08

### Added

- TCP SYN tests on port 443 and MTU probe round.

## [v0.3] - 2025-04-06

### Changed

- Added `-b` to show IPs in MTR output.

## [v0.2] - 2025-04-04

### Changed

- Increased probe count/interval for deeper stats.

## [v0.1] - 2025-04-02

### Added

- Initial release.
