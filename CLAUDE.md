# CLAUDE.md

## Project Overview

Cross-platform network diagnostics tool that runs a test matrix of MTR probes (Linux/macOS) or native Windows network tools. Two parallel implementations:

- **mtr-test-suite.sh** — Bash 4+, uses `mtr` for ICMP/UDP/TCP/MPLS/AS probes across 8 rounds
- **NetTestSuite.ps1** — PowerShell 5.1+, uses `ping`/`tracert`/`pathping`/`Test-NetConnection` across 3 rounds

## Repository Structure

```
mtr-test-suite.sh        # Bash entry point (sources lib/)
NetTestSuite.ps1         # PowerShell entry point (dot-sources lib-ps/)
lib/                     # Bash modules (common, validation, config, mtr_args, logging, plan, runner)
lib-ps/                  # PowerShell function files (18 files, one per function)
config/hosts.conf        # Shared host defaults (ipv4=host, ipv6=host)
tests/                   # bats-core tests (unit + integration + smoke)
  bats/                  # bats-core submodule
  helpers/               # bats-support + bats-assert submodules
scripts/
  ci-install-tools.sh    # Pinned shellcheck/shfmt installer (CI)
  ci-local.sh            # Local CI simulation
  install-test-deps.sh   # Test submodule initializer
  install-hooks.sh       # Git hook installer
hooks/pre-commit         # Pre-commit quality checks
.github/workflows/ci.yml # CI pipeline (lint, test, secret scan, dependency review)
```

## Commands

```bash
make validate       # shellcheck + shfmt (all lib/*.sh + scripts)
make fmt            # auto-format shell scripts
make lint           # shellcheck only
make test           # all tests (bats + Pester)
make test-bash      # bats tests only
make test-pwsh      # Pester tests only
```

## Key Conventions

### Bash
- Functions: `snake_case`
- Globals/constants: `UPPER_CASE`
- `set -euo pipefail` in entry point only (lib files inherit)
- All external input validated via `validate_host`, `validate_path_option`
- `# shellcheck source=lib/...` directives for cross-file sourcing

### PowerShell
- Functions: `Verb-Noun` PascalCase
- Parameters: PascalCase
- `Set-StrictMode -Version Latest` + `$ErrorActionPreference = 'Stop'` in entry point
- Dot-source pattern (not module) for scope sharing

### Commits
- Conventional commits: `fix:`, `feat:`, `refactor:`, `docs:`, `ci:`, `test:`, `style:`, `security:`

## Important Constraints

- Bash 4+ required (macOS needs `brew install bash`)
- PowerShell 5.1+ required; Windows-only for real runs, dry-run elsewhere
- CI actions must be pinned by SHA with version comment
- Config precedence: CLI > config/hosts.conf > built-in defaults
- Hostnames validated against: `-` prefix, whitespace, `/`, `|`, `;`, `&`, backtick, `$`, control chars
- Log filenames include PID suffix to prevent concurrent-run collisions
- `column` command is optional (graceful fallback to raw TSV)

## Common Tasks

### Adding a new test type (Bash)
1. Add to `ALL_TEST_TYPES` array in `mtr-test-suite.sh`
2. Add case in `lib/mtr_args.sh` → `set_mtr_args_for_type`
3. Add tests in `tests/integration_dryrun.bats`

### Adding a new round (Bash)
1. Add to `ALL_ROUNDS` array in `mtr-test-suite.sh`
2. Add case in `lib/mtr_args.sh` → `set_round_extra_args`

### Adding a host to defaults
- Edit `config/hosts.conf` (format: `ipv4=hostname` or `ipv6=hostname`)
- Or override via CLI: `--hosts4 host1,host2` / `-HostsIPv4 host1,host2`

### Modifying CI
- Edit `.github/workflows/ci.yml`
- Pin any new actions by SHA with version comment
- CODEOWNERS requires @sebastianspicker review for `.github/workflows/` changes
