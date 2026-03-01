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

Optional CI-style local run:

```bash
scripts/ci-local.sh
```
