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
    exit 1
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: SHA256 mismatch for $file" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
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
  curl -sSL -o "$archive" "$SHELLCHECK_URL"
  sha256_check "$archive" "$SHELLCHECK_SHA256"

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
  curl -sSL -o "$target" "$SHFMT_URL"
  sha256_check "$target" "$SHFMT_SHA256"

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
