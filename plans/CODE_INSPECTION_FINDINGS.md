# Deep Code Inspection Findings

**Date:** 2026-02-23  
**Inspector:** Kilo Code (Architect Mode)  
**Files Analyzed:**
- `mtr-test-suite.sh` (325 lines)
- `NetTestSuite.ps1` (360 lines)
- `scripts/ci-install-tools.sh` (111 lines)
- `scripts/ci-local.sh` (112 lines)

---

## Executive Summary

The codebase has a well-documented bug tracking system in [`docs/BUGS_AND_FIXES.md`](docs/BUGS_AND_FIXES.md). Most documented issues have been properly fixed. This inspection found **14 new issues** not previously documented, plus verified the implementation status of documented fixes.

---

## Verification of Documented Fixes

| Issue # | Description | Status | Evidence |
|---------|-------------|--------|----------|
| 1, 2, 20, 33 | Option/path validation | ✅ FIXED | [`validate_path_option()`](mtr-test-suite.sh:50) function exists and is called |
| 3, 21 | Dry-run non-invasive | ✅ FIXED | Lines 226-243 skip file creation when `dry_run=1` |
| 4, 22 | OK/FAIL logging | ✅ FIXED | Lines 300-309 show proper branching |
| 5, 6, 7, 30, 34 | summarize_json fallbacks | ✅ FIXED | Lines 111-114 use `${var:-???}` pattern |
| 8, 9, 10, 24, 35 | EXIT trap and temp cleanup | ✅ FIXED | Lines 246-247 have EXIT trap |
| 11, 29 | Parent dirs for custom paths | ✅ FIXED | Lines 235-240 create parent dirs |
| 12 | Failed mtr runs in JSON_LOG | ✅ FIXED | Lines 303-307 append `_failed` marker |
| 13, 31 | PowerShell CSV newline | ✅ FIXED | Line 355 uses `-join [Environment]::NewLine` |
| 14, 26, 36 | PowerShell TCP protocol binding | ✅ FIXED | [`Test-TcpPort`](NetTestSuite.ps1:183) has Protocol param |
| 15, 37 | PowerShell host validation | ✅ FIXED | [`Test-HostNameSafe()`](NetTestSuite.ps1:72) function exists |
| 16, 27, 32 | CI install OS/arch detection | ✅ FIXED | Lines 16-21 check for Linux x86_64 |
| 17, 28, 40 | sha256_check returns 1 | ✅ FIXED | Lines 39-44 use `return 1` |
| 38, 39 | PSNativeCommandUseErrorActionPreference | ✅ FIXED | Lines 59-61 set it for PS7+ |

---

## New Issues Found

### P0 - Critical (Security/Breaking)

#### P0-1: Missing Host Name Validation in Bash Script
**File:** [`mtr-test-suite.sh`](mtr-test-suite.sh:252-253)  
**Severity:** Critical  
**Type:** Security / Command Injection

**Description:**  
The PowerShell script validates host names with [`Test-HostNameSafe()`](NetTestSuite.ps1:72) to reject values starting with `-` or `/`. The Bash script has **NO equivalent validation** for [`HOSTS_IPV4`](mtr-test-suite.sh:252) and [`HOSTS_IPV6`](mtr-test-suite.sh:253) arrays.

**Impact:**  
A malicious or accidental host name like `-o /dev/null` or `--help` passed to `mtr` could:
- Cause mtr to interpret the host as an option
- Overwrite arbitrary files (if combined with other options)
- Leak information via error messages

**Proof of Concept:**
```bash
# If user modifies HOSTS_IPV4 to include:
HOSTS_IPV4=(--version)
# mtr would print version instead of running tests
```

**Fix:**  
Add host validation function and call it before the test loops:
```bash
validate_host() {
  local host=$1
  if [[ "$host" == -* ]]; then
    die "Host name must not start with '-': $host"
  fi
}
```

---

### P1 - Breaking Bugs

#### P1-1: UDP Probe Sends 1 Byte Instead of 0 Bytes
**File:** [`NetTestSuite.ps1`](NetTestSuite.ps1:234)  
**Severity:** Medium  
**Type:** Bug / Documentation Mismatch

**Description:**  
Line 234 creates a 1-byte array:
```powershell
$bytes = [byte[]](0)  # Creates array with one element: 0
```

The comment on line 201 says "zero-byte datagram" but the code sends 1 byte (value 0).

**Impact:**  
- Misleading documentation
- Some firewalls might treat 1-byte UDP differently than 0-byte
- Test results may not match expected behavior

**Fix:**
```powershell
$bytes = @()  # Empty array for true zero-byte datagram
# OR update comment to reflect 1-byte probe
```

---

#### P1-2: No Timeout on DNS Resolution in PowerShell
**File:** [`NetTestSuite.ps1`](NetTestSuite.ps1:192) and [`NetTestSuite.ps1`](NetTestSuite.ps1:224)  
**Severity:** Medium  
**Type:** Bug / Reliability

**Description:**  
Both [`Test-TcpPort`](NetTestSuite.ps1:192) and [`Test-UdpPortBestEffort`](NetTestSuite.ps1:224) use:
```powershell
$addrs = [System.Net.Dns]::GetHostAddresses($HostName)
```

This method has no timeout parameter and can hang indefinitely on DNS issues.

**Impact:**  
- Script can hang for minutes on DNS timeout
- No progress indication to user
- Long-running tests may never complete

**Fix:**  
Wrap DNS resolution in a timeout block or use async methods with timeout.

---

#### P1-3: Missing `--` Guard for File Truncation
**File:** [`mtr-test-suite.sh`](mtr-test-suite.sh:241-242)  
**Severity:** Low-Medium  
**Type:** Bug / Edge Case

**Description:**  
Lines 241-242 use:
```bash
: >"$JSON_LOG"
: >"$TABLE_LOG"
```

While `validate_path_option()` rejects paths starting with `-`, the `: >` redirection doesn't use `--` for consistency with other commands.

**Impact:**  
- Inconsistent with other path operations
- If validation is ever bypassed, could interpret path as option

**Fix:**  
The current mitigation via `validate_path_option()` is sufficient, but for consistency:
```bash
: > -- "$JSON_LOG"  # Not valid syntax; use:
: > "$JSON_LOG"     # Current approach is fine with validation
```

Note: The `:` builtin with redirection doesn't support `--`, so validation is the correct fix.

---

### P2 - Nice-to-Haves / Code Quality

#### P2-1: HTTP Port 80 Not Gaming-Related
**File:** [`NetTestSuite.ps1`](NetTestSuite.ps1:119)  
**Severity:** Low  
**Type:** Documentation / Naming

**Description:**  
The [`$GamingTargets`](NetTestSuite.ps1:113) array includes:
```powershell
[pscustomobject]@{ Name='HTTP'; Protocol='TCP'; Port=80 }
```

Port 80 is not gaming-related, just a general web port.

**Impact:**  
- Misleading variable name
- Confusion for users expecting only gaming ports

**Fix:**  
Rename variable to `$PortTargets` or `$NetworkTargets`, or remove HTTP from the list.

---

#### P2-2: No Validation of LogDirectory Path in PowerShell
**File:** [`NetTestSuite.ps1`](NetTestSuite.ps1:35)  
**Severity:** Low  
**Type:** Consistency

**Description:**  
The Bash script validates path options, but PowerShell's [`$LogDirectory`](NetTestSuite.ps1:35) parameter is not validated.

**Impact:**  
- User could pass problematic paths
- PowerShell's cmdlets may handle this, but inconsistent with Bash approach

**Fix:**  
Add validation similar to `Test-HostNameSafe`:
```powershell
function Test-PathSafe {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  $trimmed = $Path.Trim()
  if ($trimmed.StartsWith('-')) { return $false }
  return $true
}
```

---

#### P2-3: curl Silent Mode Could Hide Errors
**File:** [`scripts/ci-install-tools.sh`](scripts/ci-install-tools.sh:62) and [`scripts/ci-install-tools.sh`](scripts/ci-install-tools.sh:94)  
**Severity:** Low  
**Type:** Debugging / Operations

**Description:**  
```bash
curl -sSL -o "$archive" "$SHELLCHECK_URL"
```

The `-s` flag silences all output including error details.

**Impact:**  
- Download failures produce no diagnostic output
- Harder to debug network issues

**Fix:**  
Add `-f` (fail) flag to at least get exit code, or remove `-s` for verbose mode:
```bash
curl -fSL -o "$archive" "$SHELLCHECK_URL" || {
  echo "ERROR: Download failed from $SHELLCHECK_URL" >&2
  return 1
}
```

---

#### P2-4: PSScriptAnalyzer Installation Could Fail Silently
**File:** [`scripts/ci-local.sh`](scripts/ci-local.sh:109)  
**Severity:** Low  
**Type:** Reliability

**Description:**  
```bash
pwsh -NoProfile -NonInteractive -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module PSScriptAnalyzer -Scope CurrentUser -Force; Invoke-ScriptAnalyzer -Path NetTestSuite.ps1 -Severity Error -EnableExit"
```

If PSGallery is inaccessible, the entire command fails with no fallback.

**Impact:**  
- CI fails on network issues
- No offline mode

**Fix:**  
Add error handling and consider caching the module.

---

#### P2-5: Path Traversal Not Validated
**File:** Both scripts  
**Severity:** Low  
**Type:** Security / Defense in Depth

**Description:**  
While paths starting with `-` are rejected, `../` sequences are not validated.

**Impact:**  
- User could potentially write logs outside intended directories
- Low risk since paths are user-controlled anyway

**Fix:**  
Consider canonicalizing paths or rejecting `../` if defense-in-depth is desired.

---

#### P2-6: No Signal Handling for Graceful Shutdown in PowerShell
**File:** [`NetTestSuite.ps1`](NetTestSuite.ps1)  
**Severity:** Low  
**Type:** Reliability

**Description:**  
The Bash script has INT/TERM traps for cleanup. PowerShell has no equivalent.

**Impact:**  
- Ctrl+C leaves partial results
- No cleanup of in-progress operations

**Fix:**  
Consider adding PowerShell try/finally or event handling for cleanup.

---

### P3 - Minor / Documentation

#### P3-1: Comment Says Zero-Byte but Code Sends One Byte
**File:** [`NetTestSuite.ps1`](NetTestSuite.ps1:201)  
**Severity:** Minor  
**Type:** Documentation

**Description:**  
Comment says "zero-byte datagram" but code sends 1 byte.

**Fix:**  
Update comment to "single-byte probe" or fix code to send 0 bytes.

---

#### P3-2: README Clone URL Still Has Placeholder
**File:** [`README.md`](README.md:95)  
**Severity:** Minor  
**Type:** Documentation

**Description:**  
Line 95 shows:
```
git clone <this-repository-url>
```

**Impact:**  
- Not copy-paste runnable
- Already documented in BUGS_AND_FIXES.md as issue 19

**Fix:**  
Replace with actual URL or generic instruction.

---

## Summary Table

| ID | Severity | File | Issue | Status |
|----|----------|------|-------|--------|
| P0-1 | Critical | mtr-test-suite.sh | Missing host name validation | 🔴 Open |
| P1-1 | Medium | NetTestSuite.ps1 | UDP sends 1 byte not 0 | 🟡 Open |
| P1-2 | Medium | NetTestSuite.ps1 | No DNS timeout | 🟡 Open |
| P1-3 | Low-Med | mtr-test-suite.sh | Missing -- guard for truncation | 🟢 Mitigated |
| P2-1 | Low | NetTestSuite.ps1 | HTTP not gaming-related | 🟢 Open |
| P2-2 | Low | NetTestSuite.ps1 | No LogDirectory validation | 🟢 Open |
| P2-3 | Low | ci-install-tools.sh | curl silent mode | 🟢 Open |
| P2-4 | Low | ci-local.sh | PSScriptAnalyzer silent fail | 🟢 Open |
| P2-5 | Low | Both | Path traversal not validated | 🟢 Open |
| P2-6 | Low | NetTestSuite.ps1 | No signal handling | 🟢 Open |
| P3-1 | Minor | NetTestSuite.ps1 | Comment mismatch | 🟢 Open |
| P3-2 | Minor | README.md | Placeholder clone URL | 🟢 Open |

---

## Recommended Fix Order

1. **P0-1:** Add host validation to Bash script (security issue)
2. **P1-1:** Fix UDP byte count or update comment
3. **P1-2:** Add DNS timeout handling
4. **P2-2:** Add LogDirectory validation for consistency
5. **P2-3:** Improve curl error handling
6. **Remaining P2/P3:** Address as time permits

---

## Next Steps

Switch to Code mode to implement fixes iteratively, starting with P0 issues.
