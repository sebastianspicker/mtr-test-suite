# CI Decision

Date: 2026-02-06

## Decision
LIGHT CI.

## Rationale
- The repo is a set of Bash and PowerShell scripts with no build artifacts.
- Full end-to-end tests require network access, external hosts, and `mtr` raw-socket privileges, which are not deterministic on GitHub-hosted runners.
- Lightweight checks provide reliable signal without flaky external dependencies.

## What Runs Where
- pull_request (main): shellcheck/shfmt validation, dry-run smoke test, PowerShell ScriptAnalyzer, gitleaks, dependency review.
- push (main): shellcheck/shfmt validation, dry-run smoke test, PowerShell ScriptAnalyzer, gitleaks.
- workflow_dispatch: same as push (manual on demand).

## Threat Model
- Fork PRs are untrusted: no secrets, no write permissions, no `pull_request_target` usage.
- Jobs run with read-only `contents` permissions; dependency review adds `pull-requests: read` only.
- Artifacts are plain logs; no secrets or infrastructure access required.

## If We Later Want FULL CI
We would need:
- A deterministic fixture strategy (recorded `mtr --json` samples) or a controlled test environment.
- A self-hosted runner or container with `mtr`, `jq`, and `cap_net_raw` (or sudo) permissions.
- Network allowlists and timeouts to avoid flaky public internet dependencies.
- Separation of untrusted PR checks vs trusted `main` checks (secrets only on trusted runs).
