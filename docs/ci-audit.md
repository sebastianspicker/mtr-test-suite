# CI Audit

Date: 2026-02-06

## Workflow Inventory

Workflow: `ci.yml`

Triggers:
- `push` on `main`
- `pull_request` targeting `main`
- `workflow_dispatch`

Jobs:
- `lint` (Shell + PowerShell lint)
  - Actions: `actions/checkout@v4.3.1`, `actions/cache@v5.0.3`, `actions/upload-artifact@v6.0.0`
  - Steps: install pinned `shellcheck`/`shfmt`, `make validate`, dry-run smoke test, PowerShell ScriptAnalyzer
- `secret_scan`
  - Actions: `actions/checkout@v4.3.1`, `gitleaks/gitleaks-action@v2.3.9`
- `dependency_review` (PR only)
  - Actions: `actions/dependency-review-action@v4.8.2`

Permissions:
- Default jobs: `contents: read`
- Dependency review: `contents: read`, `pull-requests: read`

## Recent Runs
- 2026-02-05: `ci` (push on `main`) succeeded.
- 2026-01-31: `ci` (push on `main`) succeeded.

No failed runs were found for this workflow.

## Root-Cause & Fix Plan

| Workflow | Failure(s) | Root Cause | Fix Plan | Risiko | Wie verifizieren |
|---|---|---|---|---|---|
| ci / lint | None observed | Risk of nondeterministic tool versions and slow installs via `apt-get` | Pin tool versions, cache `.ci-tools`, add timeouts and artifacts | Low | Rerun CI on PR and push; verify tools versions in logs |
| ci / secret_scan | None observed | Potential for long scans on future repo growth | Keep gitleaks default limits; monitor runtime | Low | Observe job duration on future runs |
| ci / dependency_review | None observed | PR-only job; depends on GitHub API availability | Keep minimal permissions; rerun on PR | Low | Verify on a test PR |
