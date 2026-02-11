# Bugs & Required Fixes

Each item can be turned into a separate issue.

---

## Known Limitations / Bugs

### 1. [Bug] Option arguments can swallow subsequent flags (no “looks-like-an-option” validation)

**Description:** For `--log-dir`, `--json-log`, and `--table-log`, the script only checks `[[ $# -ge 2 ]]` and assigns `$2` as the value. If the user passes another option as the “argument” (e.g. `--log-dir --dry-run`), that flag is consumed as a path and never parsed as an option.

**Impact:** Confusing behavior: dry-run or other modes may not activate; paths may look like option names; no explicit error.

**Fix:** Reject or normalize values that look like options (e.g. start with `-`). Optionally support `--` to end option parsing and treat the rest as positional (if the script ever accepts positional args).

---

### 2. [Bug] Paths starting with `-` break commands (missing `--` guards)

**Description:** User-controlled paths (`--log-dir`, `--table-log`, `--json-log`) are passed to `mkdir`, `tee`, `: >"$JSON_LOG"`, and `rm -f` without a `--` terminator. If a path begins with `-`, these commands can interpret it as an option.

**Impact:** Script can fail under `set -e` with confusing errors, or write/delete the wrong files.

**Fix:** Use `--` before variable path arguments where the command supports it (e.g. `mkdir -p -- "$log_dir"`, `tee -a -- "$TABLE_LOG"`, `rm -f -- "$tmp"`). Reject or normalize paths that start with `-` in option parsing.

---

### 3. [Bug] `--dry-run` still creates/truncates log files and directories

**Description:** In dry-run mode the script still runs `mkdir -p "$log_dir"`, computes timestamped log paths, and runs `: >"$JSON_LOG"` and `: >"$TABLE_LOG"`. It also writes progress via `log()` to TABLE_LOG.

**Impact:** Dry-run is not non-invasive; it can overwrite existing log files and create empty logs/directories, contrary to “Print planned runs without executing mtr”.

**Fix:** Skip directory creation, path setup, and log file truncation when `dry_run=1`; only print planned runs (e.g. to stdout or a dedicated dry-run log path). Document behavior in `--help`.

---

### 4. [Bug] “OK: completed” is logged even when `mtr` failed

**Description:** After the `mtr` block, the script unconditionally logs `OK: completed $type -> $host` regardless of success or failure. The failure branch only logs `WARN: error in ...`.

**Impact:** TABLE_LOG mixes failure and success; operators may believe a failed test succeeded when scanning for “OK”.

**Fix:** Log “OK” only in the success branch; in the failure branch log “FAIL” or “SKIP” (and keep WARN). Optionally add a summary count of passed/failed at the end.

---

### 5. [Bug] `summarize_json` fallback `|| echo "???"` does not set variables and pollutes stdout

**Description:** The pattern `dst_name=$(jq ... 2>/dev/null) || echo "???"` runs `echo "???"` as a separate command on jq failure; it does not assign `"???"` to `dst_name`/`dst_ip`. The variables stay empty while `???` is printed to stdout.

**Impact:** Summary header can show blank destination and stray `???` lines; fallback is ineffective and noisy.

**Fix:** Use a proper fallback, e.g. `dst_name=$(jq -r '...' "$f" 2>/dev/null) || true; dst_name="${dst_name:-???}"` (or run jq and set default in a single assignment pattern). Remove redundant `|| echo "???"` and ensure jq stderr is not blindly discarded when diagnosing failures.

---

### 6. [Bug] jq hop IP extraction hard-fails on common MTR JSON (no `$h.ip`, host without parentheses)

**Description:** The jq expression uses `$h.ip` or extracts IP from `$h.host` via `capture("\\((?<ip>[^)]+)\\)")`. If `host` is a plain IP or `"???"` (no parentheses), `capture` throws and breaks the whole table for that run.

**Impact:** `summarize_json()` can abort or produce no table for real-world MTR output (e.g. plain IP or unknown hop).

**Fix:** Handle missing `ip` and host-without-parentheses: e.g. use `($h.ip // ($h.host | if test("\\(.*\\)") then capture("\\((?<ip>[^)]+)\\)").ip else . end)) // "???"` or equivalent so that plain IP / `???` do not trigger jq errors.

---

### 7. [Bug] summarize_json exit status does not reflect jq/column failure

**Description:** The `{ echo; ...; jq ... | column ...; echo; } | tee -a "$TABLE_LOG"` block’s exit status is that of the last `echo`, not the jq/column pipeline. So when jq or column fails, `summarize_json` can still exit 0 and the caller’s `if ! summarize_json` warning never fires.

**Impact:** Summary failures are silent; missing or corrupt tables are not flagged.

**Fix:** Make the group’s exit status reflect the critical command, e.g. run jq/column in a subshell and capture its exit status, then `return` that from the function or set `set +e` around the pipeline and check PIPESTATUS.

---

### 8. [Bug/Operational] Temp file cleanup only on INT/TERM; no EXIT trap

**Description:** Temp files are removed in the loop and in the INT/TERM trap. There is no EXIT trap. With `set -e`, any failing command after `mktemp` (e.g. `cat >>"$JSON_LOG"`, `log`, or `rm -f "$tmp"`) can exit the script without running the trap or the normal cleanup, leaving the current temp file behind.

**Impact:** Temp files can leak on failures (disk full, permissions, pipefail in `log()`), especially when the environment is already unhealthy.

**Fix:** Add an EXIT trap that removes `CURRENT_TMP` (and optionally other temp paths), or ensure all exit paths run cleanup. Consider making trap handler robust to `log` failure (e.g. don’t rely on `log` for trap; use `echo` to stderr or a fixed path).

---

### 9. [Bug] Race between `mktemp` and `CURRENT_TMP=$tmp` on INT/TERM

**Description:** There is a window after `tmp=$(mktemp ...)` but before `CURRENT_TMP=$tmp`. If INT/TERM is received in that window, the trap runs with `CURRENT_TMP` still empty (or from the previous iteration), so the newly created temp file is not removed.

**Impact:** Interrupts right after creating the temp file can still leak that file.

**Fix:** Set `CURRENT_TMP` in the same logical step as creating the file (e.g. `CURRENT_TMP=$(mktemp ...)` and use `CURRENT_TMP` for the mtr output path), or make the trap accept an optional path passed via a global that is set immediately after mktemp.

---

### 10. [Bug] TABLE_LOG write failures abort the entire run (and can break INT/TERM exit code)

**Description:** With `set -euo pipefail`, any failure in `log()` (e.g. `tee -a "$TABLE_LOG"` failing) terminates the script. The INT/TERM trap also calls `log "Interrupted"`; if that fails, `exit 130` may never run.

**Impact:** A logging I/O problem can stop the full test matrix and change the expected interrupt exit code.

**Fix:** Consider making `log()` resilient (e.g. ignore tee failure or write to stderr as fallback) so that progress logging does not take down the run. In the trap, avoid depending on `log` for exit semantics (e.g. use `echo ... >&2` and then `exit 130`).

---

### 11. [Bug] Custom `--json-log` / `--table-log` paths: parent directories not created

**Description:** The script only runs `mkdir -p "$log_dir"`. If the user passes `--json-log` or `--table-log` with a path in a directory that does not exist, `: >"$JSON_LOG"` or `tee -a "$TABLE_LOG"` can fail and the script exits under `set -e`.

**Impact:** Valid-looking invocations can fail before any tests run.

**Fix:** Ensure parent directories exist for both JSON_LOG and TABLE_LOG (e.g. `mkdir -p "$(dirname "$JSON_LOG")"` and same for TABLE_LOG), or document that custom paths must have existing parents.

---

### 12. [Bug] JSON_LOG only records successful mtr runs; failed-run stdout is discarded

**Description:** Raw JSON is appended to JSON_LOG only when `mtr` exits 0. If mtr fails but produced useful stdout (partial JSON, error payload), that is only in the temp file and is then removed.

**Impact:** The “raw per-run JSON” log is incomplete for failed runs, which are often the most important for debugging.

**Fix:** Optionally append `$tmp` to JSON_LOG even on mtr failure (e.g. with a “failed” marker line), or write failed-run output to a separate file; document the behavior.

---

### 13. [Bug] PowerShell: CSV content written as single space-delimited line (array coerced to string)

**Description:** `ConvertTo-Csv` returns a `string[]`. The script passes that to `[System.IO.File]::WriteAllText($csvPath, $csvContent, ...)`. PowerShell coerces `string[]` to string using `$OFS` (default space), so the file becomes one long line instead of newline-separated rows.

**Impact:** CSV is not valid row-delimited CSV; parsers and “quick diff” workflows break.

**Fix:** Join the array with newlines before writing, e.g. `$csvContent = ($all | ... | ConvertTo-Csv -NoTypeInformation) -join "`n"` (or use `[Environment]::NewLine`), then pass the single string to `WriteAllText`.

---

### 14. [Bug] PowerShell: TCP probes not constrained to round’s IP protocol (IPv4 vs IPv6)

**Description:** The script iterates `$proto` (IPv4/IPv6) and labels results with `Protocol = $proto`, but `Test-TcpPort` (Test-NetConnection) does not force IP family. The actual family used is determined by resolution and OS preferences, so TCP results can be for the wrong protocol.

**Impact:** Per-round IPv4 vs IPv6 comparison is unreliable for TCP (Tcp443OK and TCP port probes).

**Fix:** Add a parameter to force IPv4/IPv6 for Test-NetConnection (e.g. resolve to an address of the desired family and use that for the test), or document that TCP results are not protocol-bound.

---

### 15. [Bug] PowerShell: Host values unvalidated; option-like strings can be interpreted by ping/tracert/pathping

**Description:** Host names from `HostsIPv4`/`HostsIPv6` are passed as the last argument to ping, tracert, and pathping. If a host string starts with `-` or `/`, the native tools may treat it as an option.

**Impact:** Misleading diagnostics, unexpected behavior (e.g. help output, wrong timeouts), or confusing logs.

**Fix:** Validate or sanitize host strings (reject or quote values that look like options), or document that host names must not start with `-` or `/`.

---

### 16. [Bug] CI install script: Linux x86_64/amd64 only; no OS/arch detection

**Description:** Shellcheck and shfmt download URLs are hard-coded to Linux x86_64/amd64. The script does not check OS or architecture before downloading. On macOS or Linux arm64, the binaries may not run (“Exec format error”).

**Impact:** CI or local runs on non-Linux or non-x86_64 fail or repeatedly re-download incompatible binaries.

**Fix:** Add OS/arch detection and select the appropriate download URL (or document that the script is Linux x86_64 only and fail fast with a clear message on other platforms).

---

### 17. [Bug] CI install script: `sha256_check` uses `exit 1`; RETURN trap never runs on checksum failure

**Description:** When `sha256_check` fails (mismatch or no sha tool), it calls `exit 1`, which terminates the script. The install functions use `trap 'rm -rf "$tmpdir"' RETURN`, which runs only on function return, not on script exit. So on checksum failure the temp directory is not removed.

**Impact:** Temp directories leak on download/checksum failures; trap does not help for the common failure path.

**Fix:** Use `return 1` from `sha256_check` and let the caller exit, or add an EXIT trap that cleans up a known temp dir; avoid `exit` inside called functions if RETURN trap cleanup is required.

---

### 18. [Bug] Wrappers break when invoked via symlink or from a different directory

**Description:** `mtr-tests-enhanced.sh` and `mtr-test-suite_min-comments.sh` set `script_dir` from `BASH_SOURCE[0]` and exec `"$script_dir/mtr-test-suite.sh"`. If the wrapper is symlinked or copied to e.g. `/usr/local/bin`, `script_dir` becomes that directory and the exec looks for `mtr-test-suite.sh` there, which usually does not exist.

**Impact:** PATH-installed or symlinked wrappers fail with “no such file” or wrong script.

**Fix:** Resolve the real script path (e.g. follow symlinks with `readlink -f` or equivalent) and derive the repo root or script dir from that; or document that wrappers must be run from the repo and not installed as shims.

---

### 19. [Bug] README clone URL and Configuration section outdated / invalid

**Description:** README uses `https://github.com/<your-org>/mtr-test-suite.git`, which is not copy-paste runnable. The Configuration section shows `declare -A TESTS` and `declare -A ROUNDS` with trailing commas; the actual script uses `TEST_ORDER`, `ROUND_ORDER`, and `case` statements, so the README is wrong and the snippets are invalid Bash if copied.

**Impact:** New users get a failing clone URL; users trying to customize tests/rounds get wrong or broken examples.

**Fix:** Replace placeholder with a real repo URL or generic “clone this repo” wording. Align Configuration with the current script (case-based args, no TESTS/ROUNDS associative arrays) and fix syntax (no trailing commas in the examples).

---

## Required Fixes / Improvements

### 20. [Enhancement] Validate option values and path arguments

Reject or normalize `--log-dir`/`--json-log`/`--table-log` values that look like options; add `--` before path operands for `mkdir`, `tee`, `rm` where supported. See (1), (2).

---

### 21. [Enhancement] Make dry-run non-invasive

Skip log directory creation and log file truncation when `--dry-run` is set; only print planned runs. See (3).

---

### 22. [Enhancement] Clearer success/failure logging and summary fallbacks

Log “OK” only on success; use proper fallback for `dst_name`/`dst_ip` in `summarize_json` (no `|| echo "???"`); ensure summary failure is reflected in exit status. See (4), (5), (7).

---

### 23. [Enhancement] Robust jq for MTR JSON (hop IP, missing hubs, schema variants)

Handle hops without `ip` and host strings without parentheses; avoid jq `capture` throwing. Consider documenting supported MTR JSON shape or adding a “strict schema” check. See (6).

---

### 24. [Enhancement] Temp and trap robustness

EXIT trap for `CURRENT_TMP`; set `CURRENT_TMP` immediately with mktemp to avoid race; make trap handler not depend on `log()` for exit code. See (8), (9), (10).

---

### 25. [Enhancement] PowerShell: Fix CSV write and document encoding/BOM

Join `ConvertTo-Csv` output with newlines before `WriteAllText`. Document script file encoding (UTF-8 with/without BOM) for Windows PowerShell 5.1. See (13).

---

### 26. [Enhancement] PowerShell: Constrain TCP probes to round’s IP protocol

Add a way to force IPv4 or IPv6 for Test-NetConnection so that TCP results match the round’s protocol. See (14).

---

### 27. [Enhancement] CI: OS/arch-aware install or clear “Linux x86_64 only” message

Either add OS/arch detection and correct URLs, or exit early with a clear message that the script is for Linux x86_64 only. See (16).

---

### 28. [Enhancement] CI: Temp cleanup on exit and on checksum failure

Use EXIT trap or `return` from `sha256_check` so that install function RETURN trap runs; or centralize temp dir and clean on exit. See (17).

---

### 29. [Operational] Document LOG_DIR, default paths, and optional parent-dir creation

Document `LOG_DIR` in `--help`; document that custom `--json-log`/`--table-log` paths require existing parent directories (or that the script will create them if you add that behavior). See (11).

---

## Critical

### 30. [Bug] jq hop IP extraction throws on common MTR output (plain IP or `???`)

Same as (6): `capture(...)` in summarize_json throws when `host` has no parentheses; breaks table generation. **Fix:** Defensive jq so that missing `ip` and host without `(...)` yield `"???"` without throwing.

---

### 31. [Bug] PowerShell CSV written as one line (string[] coerced to string)

Same as (13): `WriteAllText` receives an array; CSV becomes space-joined. **Fix:** `-join "`n"` (or newline) before `WriteAllText`.

---

### 32. [Bug] CI install: Linux x86_64 only, no detection

Same as (16): Hard-coded Linux amd64 URLs; fails on macOS/arm64. **Fix:** Detect OS/arch and pick URL or fail with clear message.

---

## High

### 33. [Bug] Option parsing swallows flags; paths with `-` break commands

Same as (1), (2). **Fix:** Reject option-like values for path options; use `--` before path operands.

---

### 34. [Bug] summarize_json fallback and exit status

Same as (5), (7). **Fix:** Proper default for `dst_name`/`dst_ip`; make function exit status reflect jq/column failure.

---

### 35. [Bug] TABLE_LOG write failure aborts run; trap depends on log()

Same as (10). **Fix:** Resilient `log()` or trap that does not depend on `log` for exit 130.

---

### 36. [Bug] PowerShell: TCP not bound to round’s IPv4/IPv6

Same as (14).

---

### 37. [Bug] PowerShell: Host strings can be interpreted as options

Same as (15).

---

### 38. [Bug] PowerShell: PingOk/TracertOk/PathpingOk mean “exit code 0”, not “path OK”

**Description:** The `*Ok` booleans are derived only from process exit code. They do not reflect actual connectivity or loss.  
**Fix:** Document clearly; optionally add a second notion (e.g. “ExitCodeOk” vs “PathOk” derived from output).

---

### 39. [Bug] PowerShell: Non-zero native exit codes can terminate script if PSNativeCommandUseErrorActionPreference is true

**Description:** With `$ErrorActionPreference = 'Stop'`, if `$PSNativeCommandUseErrorActionPreference` is true, ping/tracert/pathping non-zero exit can throw and stop the script before the result object is returned.  
**Fix:** Run native commands in a context that does not treat non-zero as terminating (e.g. `& { ping @args; $LASTEXITCODE }` and capture), or set preference so native commands don’t throw.

---

### 40. [Bug] CI: sha256_check exits script; RETURN trap skipped

Same as (17).

---

### 41. [Bug] README: placeholder clone URL and wrong TESTS/ROUNDS syntax

Same as (19).

---

### 42. [Bug] Wrappers fail when symlinked / run from PATH

Same as (18).

---

## Quick reference: common failure causes

| Symptom | Typical cause | Fix / see |
|--------|----------------|-----------|
| Script exits after “Missing dependency” | `mtr`/`jq`/`column` not in PATH or wrong shell | Install deps; run with Bash 4+ (`bash ./mtr-test-suite.sh`) |
| Dry-run overwrites my logs | Dry-run still truncates JSON_LOG/TABLE_LOG | Use separate paths for dry-run or fix (3) |
| TABLE_LOG shows “OK” but mtr failed | Unconditional “OK” after each host | Fix (4); re-run and check WARN lines |
| Summary table empty or “???” lines | jq failure or fallback bug | Fix (5), (6), (7); check MTR JSON shape |
| Temp files left under /tmp | Exit/signal before cleanup | Fix (8), (9); EXIT trap, CURRENT_TMP set earlier |
| 403 / tee / mkdir errors with custom paths | Path starts with `-` or parent missing | Fix (2), (11); use `--`, create parents |
| PowerShell CSV one long line | string[] coerced to string | Fix (13), (31) |
| PowerShell TCP “wrong” protocol | Test-NetConnection not forced to IPv4/IPv6 | Fix (14), (26), (36) |
| CI install fails on macOS / arm64 | Linux x86_64 URLs only | Fix (16), (27), (32) |
| CI temp dirs left behind | exit in sha256_check skips RETURN trap | Fix (17), (28), (40) |
| Wrapper “no such file” from PATH | script_dir points to shim dir | Fix (18), (42); run from repo or resolve real path |
| README clone/config wrong | Placeholder URL; outdated TESTS/ROUNDS | Fix (19), (41) |

---

## Using this list for issues

- **Labels:** `bug`, `enhancement`, `documentation`, `operational` as appropriate.
- **Title:** Use the **[Bug]** / **[Enhancement]** prefix or a label.
- **Body:** Copy the relevant section (description, impact, fix) into the issue.
- The **quick reference** table can be linked from README or a “Troubleshooting” / “Common issues” doc.
