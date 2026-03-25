# Contributing

Thanks for contributing.

## Prerequisites

- Bash 4+
- `shellcheck`
- `shfmt`

Setup and operational details are in [docs/RUNBOOK.md](docs/RUNBOOK.md).

## Local Validation

```bash
make validate
./mtr-test-suite.sh --dry-run --no-summary
```

## Running Tests

Install test dependencies (bats-core submodules):

```bash
scripts/install-test-deps.sh
```

Run all tests:

```bash
make test          # Bash + PowerShell
make test-bash     # Bash only (bats)
make test-pwsh     # PowerShell only (Pester)
```

## Git Hooks

Install pre-commit hooks for automatic quality checks:

```bash
scripts/install-hooks.sh
```

To bypass hooks when needed: `git commit --no-verify`

## CI-style Local Run

```bash
scripts/ci-local.sh
```
