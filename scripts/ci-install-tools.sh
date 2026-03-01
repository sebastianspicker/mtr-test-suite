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

# Generic installer: name, version, version_grep (for --version), expected_sha, url, is_tarball (1=tar.xz, 0=single file)
install_pinned_binary() {
  local name=$1
  local version=$2
  local version_grep=$3
  local expected_sha=$4
  local url=$5
  local is_tarball=$6
  local bin="$TOOLS_DIR/$name"

  if [[ -x "$bin" ]]; then
    if "$bin" --version 2>/dev/null | grep -q "$version_grep"; then
      return 0
    fi
  fi

  echo "Installing $name v${version}"
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  if [[ "$is_tarball" -eq 1 ]]; then
    local archive="$tmpdir/$name.tar.xz"
    if ! curl -fSL -o "$archive" "$url"; then
      echo "ERROR: Failed to download $name from $url" >&2
      return 1
    fi
    sha256_check "$archive" "$expected_sha" || {
      rm -rf "$tmpdir"
      exit 1
    }
    tar -xJf "$archive" -C "$tmpdir"
    local found
    found=$(find "$tmpdir" -type f -name "$name" 2>/dev/null | head -1)
    [[ -n "$found" ]] || {
      echo "ERROR: $name binary not found in archive" >&2
      return 1
    }
    mv "$found" "$bin"
  else
    local target="$tmpdir/$name"
    if ! curl -fSL -o "$target" "$url"; then
      echo "ERROR: Failed to download $name from $url" >&2
      return 1
    fi
    sha256_check "$target" "$expected_sha" || {
      rm -rf "$tmpdir"
      exit 1
    }
    mv "$target" "$bin"
  fi
  chmod +x "$bin"
}

install_shellcheck() {
  install_pinned_binary shellcheck "$SHELLCHECK_VERSION" "version: ${SHELLCHECK_VERSION}" "$SHELLCHECK_SHA256" "$SHELLCHECK_URL" 1
}

install_shfmt() {
  install_pinned_binary shfmt "$SHFMT_VERSION" "v${SHFMT_VERSION}" "$SHFMT_SHA256" "$SHFMT_URL" 0
}

install_shellcheck
install_shfmt

cat <<EOF2
Installed tools:
- shellcheck: $TOOLS_DIR/shellcheck
- shfmt:      $TOOLS_DIR/shfmt
EOF2
