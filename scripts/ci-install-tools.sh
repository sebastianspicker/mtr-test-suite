#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLS_DIR="${ROOT_DIR}/.ci-tools"

SHELLCHECK_VERSION="0.9.0"
SHELLCHECK_SHA256="700324c6dd0ebea0117591c6cc9d7350d9c7c5c287acbad7630fa17b1d4d9e2f"
SHELLCHECK_URL="https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"

SHFMT_VERSION="3.7.0"
SHFMT_SHA256="0264c424278b18e22453fe523ec01a19805ce3b8ebf18eaf3aadc1edc23f42e3"
SHFMT_URL="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_amd64"

# Pinned binaries are Linux x86_64 only; fail fast on other platforms with a clear message
CI_OS=$(uname -s)
CI_ARCH=$(uname -m)
if [[ "$CI_OS" != "Linux" ]] || [[ "$CI_ARCH" != "x86_64" && "$CI_ARCH" != "amd64" ]]; then
  echo "ERROR: ci-install-tools.sh is Linux x86_64/amd64 only (got: $CI_OS $CI_ARCH). Install shellcheck and shfmt manually (e.g. brew install shellcheck shfmt on macOS)." >&2
  exit 1
fi

mkdir -p "$TOOLS_DIR"

sha256_check() {
  local file=$1
  local expected=$2
  local actual=""

  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$file" | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
  else
    echo "ERROR: No sha256 tool available" >&2
    return 1
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: SHA256 mismatch for $file" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    return 1
  fi
}

install_shellcheck() {
  local bin="$TOOLS_DIR/shellcheck"

  if [[ -x "$bin" ]]; then
    if "$bin" --version 2>/dev/null | grep -q "version: ${SHELLCHECK_VERSION}"; then
      return 0
    fi
  fi

  echo "Installing shellcheck v${SHELLCHECK_VERSION}"
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  local archive="$tmpdir/shellcheck.tar.xz"
  if ! curl -fSL -o "$archive" "$SHELLCHECK_URL"; then
    echo "ERROR: Failed to download shellcheck from $SHELLCHECK_URL" >&2
    return 1
  fi
  sha256_check "$archive" "$SHELLCHECK_SHA256" || {
    rm -rf "$tmpdir"
    exit 1
  }

  tar -xJf "$archive" -C "$tmpdir"
  local found
  found=$(find "$tmpdir" -type f -name shellcheck 2>/dev/null | head -1)
  [[ -n "$found" ]] || {
    echo "ERROR: shellcheck binary not found in archive" >&2
    return 1
  }
  mv "$found" "$bin"
  chmod +x "$bin"
}

install_shfmt() {
  local bin="$TOOLS_DIR/shfmt"

  if [[ -x "$bin" ]]; then
    if "$bin" --version 2>/dev/null | grep -q "v${SHFMT_VERSION}"; then
      return 0
    fi
  fi

  echo "Installing shfmt v${SHFMT_VERSION}"
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  local target="$tmpdir/shfmt"
  if ! curl -fSL -o "$target" "$SHFMT_URL"; then
    echo "ERROR: Failed to download shfmt from $SHFMT_URL" >&2
    return 1
  fi
  sha256_check "$target" "$SHFMT_SHA256" || {
    rm -rf "$tmpdir"
    exit 1
  }

  mv "$target" "$bin"
  chmod +x "$bin"
}

install_shellcheck
install_shfmt

cat <<EOF2
Installed tools:
- shellcheck: $TOOLS_DIR/shellcheck
- shfmt:      $TOOLS_DIR/shfmt
EOF2
