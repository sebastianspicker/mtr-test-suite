#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLS_DIR="${ROOT_DIR}/.ci-tools"

SKIP_PWSH=0
SKIP_INSTALL=0

usage() {
  cat <<'USAGE'
Usage: scripts/ci-local.sh [--skip-pwsh] [--skip-install]

Runs the same checks as CI locally.

Options:
  --skip-pwsh      Skip PowerShell static analysis
  --skip-install   Skip installing pinned tools (Linux only)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-pwsh)
      SKIP_PWSH=1
      shift
      ;;
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  if [[ "$(uname -s)" == "Linux" ]]; then
    "${ROOT_DIR}/scripts/ci-install-tools.sh"
  else
    echo "Note: ci-install-tools.sh is Linux-only. Install shellcheck and shfmt manually." >&2
  fi
fi

if [[ -d "$TOOLS_DIR" ]]; then
  export PATH="$TOOLS_DIR:$PATH"
fi

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "ERROR: shellcheck not found in PATH" >&2
  exit 1
fi

if ! command -v shfmt >/dev/null 2>&1; then
  echo "ERROR: shfmt not found in PATH" >&2
  exit 1
fi

find_bash4() {
  local candidate
  for candidate in bash /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ "$candidate" == "bash" ]]; then
      if command -v bash >/dev/null 2>&1; then
        local major
        major=$(bash -c "echo \${BASH_VERSINFO[0]}" 2>/dev/null || echo 0)
        if [[ "$major" -ge 4 ]]; then
          echo "bash"
          return 0
        fi
      fi
    else
      if [[ -x "$candidate" ]]; then
        local major
        major=$("$candidate" -c "echo \${BASH_VERSINFO[0]}" 2>/dev/null || echo 0)
        if [[ "$major" -ge 4 ]]; then
          echo "$candidate"
          return 0
        fi
      fi
    fi
  done
  return 1
}

cd "$ROOT_DIR"

make validate

if BASH_BIN=$(find_bash4); then
  "$BASH_BIN" ./mtr-test-suite.sh --dry-run --no-summary
else
  echo "ERROR: Bash 4+ required for mtr-test-suite.sh. Install newer bash (e.g., brew install bash)." >&2
  exit 1
fi

if [[ "$SKIP_PWSH" -eq 1 ]]; then
  echo "Skipping PowerShell static analysis"
  exit 0
fi

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -NonInteractive -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module PSScriptAnalyzer -Scope CurrentUser -Force; Invoke-ScriptAnalyzer -Path NetTestSuite.ps1 -Severity Error -EnableExit"
else
  echo "Note: pwsh not found; skipping PowerShell static analysis" >&2
fi
