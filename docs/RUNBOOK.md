# RUNBOOK

Canonical operational guide for setup, validation, execution, troubleshooting, and release.

## Setup

### Linux/macOS (Bash suite)

Install dependencies:

```bash
# macOS (Homebrew)
brew install bash mtr jq shellcheck shfmt

# Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y bash mtr jq util-linux shellcheck shfmt
```

Notes:
- Bash 4+ is required.
- `mtr` probe types may require elevated privileges (`sudo` or `cap_net_raw`).

### Windows (PowerShell suite)

- PowerShell 5.1+
- Built-in tools: `ping`, `tracert`, `pathping`, `Test-NetConnection`

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\NetTestSuite.ps1
```

## Shared Host Configuration

Default host list file: `config/hosts.conf`

Format:
```ini
ipv4=netcologne.de
ipv6=netcologne.de
```

Behavior:
- If present, both suites load it.
- CLI parameter/flag host overrides win over config file values.
- If missing or empty, built-in host defaults are used.

## Validate and Lint

```bash
make fmt
make lint
make validate
```

## Testing

Install test dependencies (one-time):

```bash
scripts/install-test-deps.sh
```

Run tests:

```bash
make test          # all tests (Bash + PowerShell)
make test-bash     # Bash unit + integration tests (bats-core)
make test-pwsh     # PowerShell tests (Pester)
```

Optional local CI-like run:

```bash
scripts/ci-local.sh --skip-install
```

## Execution

### Bash canonical smoke test (no probes)

```bash
./mtr-test-suite.sh --dry-run --no-summary
```

### Bash full run

```bash
./mtr-test-suite.sh
```

### Bash selective run

```bash
./mtr-test-suite.sh --types ICMP4,TCP4 --rounds Standard --hosts4 localhost --dry-run
```

### PowerShell dry-run

```powershell
pwsh -NoProfile -NonInteractive -File .\NetTestSuite.ps1 -DryRun
```

### PowerShell full run

```powershell
pwsh -NoProfile -NonInteractive -File .\NetTestSuite.ps1
```

### PowerShell selective run

```powershell
pwsh -NoProfile -NonInteractive -File .\NetTestSuite.ps1 -Protocols IPv4 -Rounds Standard -DryRun
```

## Output Artifacts

Bash:
- `mtr_results_<timestamp>_<pid>.json.log`
- `mtr_summary_<timestamp>_<pid>.log`

PowerShell:
- `net_results_<timestamp>_<pid>.json`
- `net_summary_<timestamp>_<pid>.csv`

Defaults:
- Bash: `~/logs`
- PowerShell: `%USERPROFILE%\logs`, fallback to `$HOME\logs`, then current directory `logs`

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Fix |
|---|---|---|
| `Missing dependency: mtr` | mtr missing from PATH | Install `mtr` and verify `mtr --json` support |
| `Bash 4+ required` | System bash too old (common on macOS) | Install newer bash and run with that shell |
| `column: command not found` | util-linux/column missing | Install `util-linux` (Linux) or `column` via Homebrew |
| Dry-run creates logs | Unexpected behavior | Dry-run should be non-invasive; verify script version and flags |
| PowerShell `LogDirectory` path error | Invalid/option-like path or traversal | Use a normal path without leading `-`, `|`, control chars, or `..` components |
| Host validation error (Bash/PowerShell) | Invalid host entry | Remove empty entries and values containing `-` prefix, whitespace, `/`, `|`, or control characters |
| CI local skips PowerShell checks | `pwsh` not installed | Install PowerShell or run with `--skip-pwsh` |
| Probe permission failures | Insufficient privileges | Use elevated shell or grant needed capabilities |

## Security Checks

CI includes:
- shellcheck/shfmt validation
- PSScriptAnalyzer (PowerShell static analysis)
- gitleaks secret scan
- dependency review (PR)

## Release Checklist (GitHub)

### Pre-release hygiene

```bash
git status --short
make validate
make test
./mtr-test-suite.sh --dry-run --no-summary
./mtr-test-suite.sh --list-types
./mtr-test-suite.sh --list-rounds
pwsh -NoProfile -NonInteractive -File .\NetTestSuite.ps1 -DryRun -Quiet
```

Optional:
```bash
scripts/ci-local.sh --skip-install
```

### PR preparation

1. Ensure only intentional release changes are present.
2. Open PR to `main` with:
   - validation command output summary
   - README Mermaid render confirmation
   - explicit note of removed obsolete docs/plans.

### Tag and release

1. Merge PR to `main`.
2. Create annotated tag:

```bash
git checkout main
git pull --ff-only
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0
```

3. Create GitHub Release `v1.1.0` and use `CHANGELOG.md` `v1.1.0` section as release notes baseline.

### Post-release verification

1. Confirm tag exists on GitHub.
2. Confirm release page is published.
3. Confirm README Mermaid diagrams render on GitHub.
4. Confirm CI is green on `main` and tag context.
