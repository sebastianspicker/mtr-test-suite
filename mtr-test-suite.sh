#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
mtr-test-suite.sh v1.0

Runs a comprehensive MTR test matrix (types × rounds × hosts) and writes:
  - JSON_LOG: raw per-run JSON output
  - TABLE_LOG: human-readable summaries and progress

Default log directory: LOG_DIR env or ~/logs. Default files: <log-dir>/mtr_results_<timestamp>.json.log and <log-dir>/mtr_summary_<timestamp>.log.

Usage:
  ./mtr-test-suite.sh [--log-dir DIR] [--json-log PATH] [--table-log PATH] [--no-summary] [--dry-run] [--quiet]

Options:
  --log-dir DIR     Log directory (default: ~/logs)
  --json-log PATH   Override JSON_LOG path (parent dirs created if needed)
  --table-log PATH  Override TABLE_LOG path (parent dirs created if needed)
  --no-summary      Skip jq/column summary tables (still logs JSON)
  --dry-run         Print planned runs only; no files created or truncated
  --quiet           Only errors and final summary (no per-step progress)
  -h, --help        Show this help
  --version         Print version
EOF
}

require_bash4() {
  if [[ -z "${BASH_VERSION:-}" ]]; then
    die "Please run this script with bash: bash $0"
  fi
  if ((BASH_VERSINFO[0] < 4)); then
    die "Bash 4+ required (found: ${BASH_VERSION}). Install a newer bash or run on a Linux host."
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

# Reject path/option values that look like options (could break mkdir/tee/rm)
validate_path_option() {
  local opt_name=$1
  local val=$2
  if [[ -n "$val" && "$val" == -* ]]; then
    die "$opt_name argument must not look like an option (starts with -): $val"
  fi
}

# Reject host names that look like options (could be interpreted by mtr)
validate_host() {
  local host=$1
  if [[ -z "$host" ]]; then
    die "Host name must not be empty"
  fi
  if [[ "$host" == -* ]]; then
    die "Host name must not look like an option (starts with -): $host"
  fi
}

# Set extra_args (round-specific mtr options) by round name
set_round_extra_args() {
  local round=$1
  case "$round" in
    Standard) extra_args=() ;;
    MTU1400) extra_args=(-s 1400) ;;
    TOS_CS5) extra_args=(--tos 160) ;;
    TOS_AF11) extra_args=(--tos 40) ;;
    TTL10) extra_args=(-m 10) ;;
    TTL64) extra_args=(-m 64) ;;
    FirstTTL3) extra_args=(-f 3) ;;
    Timeout5) extra_args=(-Z 5) ;;
    *) extra_args=() ;;
  esac
}

# Set mtr_args (type-specific flags + BASE_MTR) by test type name
set_mtr_args_for_type() {
  local type=$1
  local -a BASE_MTR=(-b -i 1 -c 300 -r --json)
  case "$type" in
    ICMP4) mtr_args=(-4 "${BASE_MTR[@]}") ;;
    ICMP6) mtr_args=(-6 "${BASE_MTR[@]}") ;;
    UDP4) mtr_args=(-u -4 "${BASE_MTR[@]}") ;;
    UDP6) mtr_args=(-u -6 "${BASE_MTR[@]}") ;;
    TCP4) mtr_args=(-T -P 443 -4 "${BASE_MTR[@]}") ;;
    TCP6) mtr_args=(-T -P 443 -6 "${BASE_MTR[@]}") ;;
    MPLS4) mtr_args=(-e -4 "${BASE_MTR[@]}") ;;
    MPLS6) mtr_args=(-e -6 "${BASE_MTR[@]}") ;;
    AS4) mtr_args=(-z --aslookup -4 "${BASE_MTR[@]}") ;;
    AS6) mtr_args=(-z --aslookup -6 "${BASE_MTR[@]}") ;;
    *) die "Unknown test type: $type" ;;
  esac
}

log() {
  if [[ "${QUIET:-0}" -eq 1 ]]; then
    [[ "$*" == *WARN* || "$*" == *FAIL* || "$*" == *"All tests"* || "$*" == *Passed:* || "$*" == *"Starting MTR"* ]] || return 0
  fi
  local line
  line=$(printf '[%s] %s\n' "$(date +'%F %T')" "$*")
  if [[ -n "${TABLE_LOG:-}" ]]; then
    (echo "$line" | tee -a -- "$TABLE_LOG") || echo "$line" >&2
  else
    echo "$line"
  fi
}

summarize_json() {
  local f=$1
  local dst_name dst_ip
  local table_out jq_status

  dst_name=$(jq -r '(.report // {} | .dst_name? // .dst_addr? // .dst_ip? // .mtr.dst?) // "???"' "$f" 2>/dev/null) || true
  dst_name="${dst_name:-???}"
  dst_ip=$(jq -r '(.report // {} | .dst_addr? // .dst_ip? // .mtr.dst?) // "???"' "$f" 2>/dev/null) || true
  dst_ip="${dst_ip:-???}"

  table_out=$(jq -r '
    ((.report // {}) | .hubs // [])[]? as $h |
    [
      ($h.count // 0),
      ( $h.host // "???" | sub(" \\(.*"; "") ),
      ( ($h.ip // ($h.host | if type == "string" and test("\\(.*\\)") then capture("\\((?<ip>[^)]+)\\)").ip else . end)) // "???" ),
      ($h."Loss%" // 0),
      ($h.Snt     // 0),
      ($h.Last    // 0),
      ($h.Avg     // 0),
      ($h.Best    // 0),
      ($h.Wrst    // 0),
      ($h.StDev   // 0)
    ] | map(tostring) | @tsv' "$f" 2>/dev/null | column -t -s $'\t')
  jq_status=${PIPESTATUS[0]}

  if [[ -n "${TABLE_LOG:-}" ]]; then
    {
      echo
      echo "Results for: ${dst_name} (${dst_ip})"
      printf 'Hop\tHost\tIP\tLoss%%\tSnt\tLast\tAvg\tBest\tWrst\tStDev\n'
      echo "$table_out"
      echo
    } | tee -a -- "$TABLE_LOG" >/dev/null
  else
    echo
    echo "Results for: ${dst_name} (${dst_ip})"
    printf 'Hop\tHost\tIP\tLoss%%\tSnt\tLast\tAvg\tBest\tWrst\tStDev\n'
    if [[ -n "$table_out" ]]; then
      echo "$table_out"
    else
      echo "(No results)"
    fi
    echo
  fi
  return "$jq_status"
}

main() {
  local log_dir="${LOG_DIR:-$HOME/logs}"
  local json_log=""
  local table_log=""
  local do_summary=1
  local dry_run=0
  local quiet=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --log-dir)
        [[ $# -ge 2 ]] || die "--log-dir requires an argument"
        validate_path_option "--log-dir" "$2"
        log_dir=$2
        shift 2
        ;;
      --json-log)
        [[ $# -ge 2 ]] || die "--json-log requires an argument"
        validate_path_option "--json-log" "$2"
        json_log=$2
        shift 2
        ;;
      --table-log)
        [[ $# -ge 2 ]] || die "--table-log requires an argument"
        validate_path_option "--table-log" "$2"
        table_log=$2
        shift 2
        ;;
      --no-summary)
        do_summary=0
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --quiet)
        quiet=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --version)
        echo "mtr-test-suite.sh v${VERSION}"
        exit 0
        ;;
      --)
        shift
        break
        ;;
      *)
        die "Unknown argument: $1 (use --help)"
        ;;
    esac
  done
  [[ $# -eq 0 ]] || die "Unexpected positional args: $*"

  QUIET=${quiet:-0}
  export QUIET

  require_bash4

  if ((dry_run == 0)); then
    require_cmd mtr
  fi
  if ((do_summary)) && ((dry_run == 0)); then
    require_cmd jq
    require_cmd column
  fi

  if ((dry_run == 1)); then
    JSON_LOG=""
    TABLE_LOG=""
  else
    local ts
    ts=$(date +'%Y%m%d_%H%M%S')
    JSON_LOG=${json_log:-"$log_dir/mtr_results_${ts}.json.log"}
    TABLE_LOG=${table_log:-"$log_dir/mtr_summary_${ts}.log"}
    mkdir -p -- "$log_dir"
    if [[ -n "$json_log" ]]; then
      mkdir -p -- "$(dirname "$JSON_LOG")"
    fi
    if [[ -n "$table_log" ]]; then
      mkdir -p -- "$(dirname "$TABLE_LOG")"
    fi
    : >"$JSON_LOG"
    : >"$TABLE_LOG"
  fi

  CURRENT_TMP=""
  trap 'rm -f "${CURRENT_TMP:-}" 2>/dev/null; echo "Interrupted" >&2; exit 130' INT TERM
  trap 'rm -f "${CURRENT_TMP:-}" 2>/dev/null' EXIT

  # Test definitions (arrays built in loop to avoid fragile read -a parsing)
  TEST_ORDER=(ICMP4 ICMP6 UDP4 UDP6 TCP4 TCP6 MPLS4 MPLS6 AS4 AS6)

  HOSTS_IPV4=(netcologne.de google.com wikipedia.org amazon.de)
  HOSTS_IPV6=(netcologne.de google.com wikipedia.org)

  # Validate all host names to prevent option injection
  for h in "${HOSTS_IPV4[@]}" "${HOSTS_IPV6[@]}"; do
    validate_host "$h"
  done

  ROUND_ORDER=(Standard MTU1400 TOS_CS5 TOS_AF11 TTL10 TTL64 FirstTTL3 Timeout5)

  log "Starting MTR tests (rounds: ${ROUND_ORDER[*]})"
  if [[ -n "${JSON_LOG:-}" ]]; then
    log "JSON_LOG=$JSON_LOG"
    log "TABLE_LOG=$TABLE_LOG"
  fi

  local round type host
  local -a hosts mtr_args extra_args
  local run_ok=0 run_fail=0

  for round in "${ROUND_ORDER[@]}"; do
    set_round_extra_args "$round"
    log "=== Round: $round ${extra_args[*]:+(opts: ${extra_args[*]})} ==="

    for type in "${TEST_ORDER[@]}"; do
      log "--- $type tests in Round: $round ---"

      if [[ $type == *6 ]]; then
        hosts=("${HOSTS_IPV6[@]}")
      else
        hosts=("${HOSTS_IPV4[@]}")
      fi

      set_mtr_args_for_type "$type"

      for host in "${hosts[@]}"; do
        log "-> $type -> $host"

        if ((dry_run)); then
          log "DRY RUN: mtr ${mtr_args[*]} ${extra_args[*]} $host"
          continue
        fi

        CURRENT_TMP=$(mktemp "${TMPDIR:-/tmp}/mtr-suite.XXXXXXXX")

        if mtr "${mtr_args[@]}" "${extra_args[@]}" "$host" >"$CURRENT_TMP" 2>>"$TABLE_LOG"; then
          cat "$CURRENT_TMP" >>"$JSON_LOG"
          printf '\n' >>"$JSON_LOG"
          if ((do_summary)); then
            if ! summarize_json "$CURRENT_TMP"; then
              log "WARN: summary failed for $type -> $host (continuing)"
            fi
          fi
          ((run_ok++)) || true
          log "OK: completed $type -> $host"
        else
          {
            jq -n --arg type "$type" --arg host "$host" '{"_failed":true, $type, $host}'
            cat "$CURRENT_TMP"
            printf '\n'
          } >>"$JSON_LOG"
          ((run_fail++)) || true
          log "FAIL: $type -> $host (continuing)"
        fi

        rm -f -- "$CURRENT_TMP"
        CURRENT_TMP=""
      done
    done
  done

  if ((dry_run == 0)) && [[ -n "${TABLE_LOG:-}" ]]; then
    log "All tests done. Passed: $run_ok, Failed: $run_fail"
  else
    log "All tests done."
  fi
}

main "$@"
