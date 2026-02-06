# CI Guide

## Overview
The CI workflow provides deterministic, fast checks for shell and PowerShell scripts without requiring live network access. It runs on `push`, `pull_request`, and manual `workflow_dispatch`.

Workflows:
- `ci.yml`: lint + dry-run smoke test, secret scan, dependency review (PR only).

## Local Execution
Run the same checks locally:

```bash
scripts/ci-local.sh
```

Options:
- `--skip-pwsh`: skip PowerShell static analysis if `pwsh` is unavailable.
- `--skip-install`: skip installing pinned tools (Linux-only installer).

Tooling notes:
- On Linux, `scripts/ci-install-tools.sh` downloads pinned `shellcheck` and `shfmt` into `.ci-tools/`.
- On macOS, install via Homebrew: `brew install shellcheck shfmt`.
- On Windows, use `choco install shellcheck shfmt` or run CI in WSL.

## Checks
- Shell validation: `shfmt` and `shellcheck` via `make validate`.
- Dry-run smoke test: `./mtr-test-suite.sh --dry-run --no-summary`.
- PowerShell static analysis: `PSScriptAnalyzer` on `NetTestSuite.ps1`.
- Secret scan: `gitleaks` (no secrets required).
- Dependency review: PR-only (GitHub dependency review action).

## Caching
- `.ci-tools` is cached per OS and tool version to avoid re-downloading `shellcheck` and `shfmt`.

## Artifacts
- On failure, logs are uploaded as workflow artifacts under `ci-artifacts-<job>`.

## Secrets and Permissions
- No secrets are required.
- Default job permissions are read-only; dependency review adds `pull-requests: read` only.

## Extending CI
- Add new checks to the `lint` job with clear step names and log capture to `ci-artifacts/`.
- For future integration tests, use separate jobs that only run on `push` to `main` or `workflow_dispatch`.
- Keep untrusted PR checks free of secrets and writes.

## Optional: act
You can run workflows with `act` for local simulation. This is optional and not required for daily development.
