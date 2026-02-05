# RUNBOOK

This runbook documents the supported workflows for validating and operating the repository.

## Setup

### Requirements (macOS/Linux)

- Bash 4+ (the suite uses associative arrays)
- mtr with JSON support
- jq
- column (util-linux)
- shellcheck
- shfmt

macOS (Homebrew):
```bash
brew install bash mtr jq shellcheck shfmt
```

Debian/Ubuntu:
```bash
sudo apt-get update
sudo apt-get install -y bash mtr jq util-linux shellcheck shfmt
```

Notes:
- Running `mtr` may require elevated privileges or `cap_net_raw` depending on probe type.
- The full test suite can take many hours to complete; use `--dry-run` for verification.

### Windows (PowerShell)

- PowerShell 5.1+ (tested with built-in tools)

Run:
```powershell
powershell -ExecutionPolicy Bypass -File .\NetTestSuite.ps1
```

## Format / Lint

```bash
make fmt
make lint
```

## Static / Type Checks

None (shell scripts only).

## Build

None (scripts only).

## Tests

### Fast loop (developer)

```bash
make validate
./mtr-test-suite.sh --dry-run
```

### Full loop (long-running)

```bash
make validate
./mtr-test-suite.sh
```

## Security Minimum

CI runs the following checks:
- Secret scan via Gitleaks (filesystem scan, redacted output)
- SAST: `shellcheck` for Bash and `PSScriptAnalyzer` for PowerShell (errors only)
- SCA: GitHub dependency review on pull requests

Optional local equivalents (if tools are installed):

```bash
gitleaks detect --no-git --redact
```

```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path .\NetTestSuite.ps1 -Severity Error -EnableExit
```

## Troubleshooting

- `Missing dependency: mtr` → install `mtr` and ensure it supports `--json`.
- `Bash 4+ required` → install a newer bash and run `bash ./mtr-test-suite.sh`.
- `column: command not found` → install `util-linux` (Linux) or `column` via Homebrew.
- Permission errors → run with `sudo` or set `cap_net_raw` for `mtr`.
