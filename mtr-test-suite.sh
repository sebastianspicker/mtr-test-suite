#!/usr/bin/env bash
set -euo pipefail

VERSION="1.1.0"

ALL_TEST_TYPES=(ICMP4 ICMP6 UDP4 UDP6 TCP4 TCP6 MPLS4 MPLS6 AS4 AS6)
ALL_ROUNDS=(Standard MTU1400 TOS_CS5 TOS_AF11 TTL10 TTL64 FirstTTL3 Timeout5)
DEFAULT_HOSTS_IPV4=(netcologne.de google.com wikipedia.org amazon.de)
DEFAULT_HOSTS_IPV6=(netcologne.de google.com wikipedia.org)

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
mtr-test-suite.sh v1.1.0

Runs an MTR test matrix (types x rounds x hosts) and writes:
  - JSON_LOG: raw per-run JSON output
  - TABLE_LOG: human-readable summaries and progress

Default log directory: LOG_DIR env or ~/logs.
Default host config: ./config/hosts.conf (loaded when present).

Usage:
  ./mtr-test-suite.sh [options]

Options:
  --log-dir DIR      Log directory (default: ~/logs)
  --json-log PATH    Override JSON_LOG path
  --table-log PATH   Override TABLE_LOG path
  --types CSV        Run selected test types (e.g. ICMP4,TCP4)
  --rounds CSV       Run selected rounds (e.g. Standard,TTL64)
  --hosts4 CSV       Override IPv4 hosts (comma-separated)
  --hosts6 CSV       Override IPv6 hosts (comma-separated)
  --list-types       Print supported test types and exit
  --list-rounds      Print supported rounds and exit
  --no-summary       Skip jq/column summary tables (JSON still logged)
  --dry-run          Print planned runs only; no files created
  --quiet            Print warnings/failures and final summary only
  -h, --help         Show this help
  --version          Print version
USAGE
}

require_bash4() {
  if [[ -z "${BASH_VERSION:-}" ]]; then
    die "Please run this script with bash: bash $0"
  fi
  if ((BASH_VERSINFO[0] < 4)); then
    die "Bash 4+ required (found: ${BASH_VERSION})."
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

trim() {
  local v=$1
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

contains_item() {
  local needle=$1
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

print_list() {
  local item
  for item in "$@"; do
    echo "$item"
  done
}

parse_csv_to_array() {
  local csv=$1
  local opt_name=$2
  local -a raw=()
  local item clean

  PARSED_CSV_ITEMS=()

  [[ -n "$csv" ]] || die "$opt_name requires a non-empty CSV argument"
  if [[ "$csv" == ,* || "$csv" == *, || "$csv" == *,,* ]]; then
    die "$opt_name contains malformed CSV separators"
  fi

  IFS=',' read -r -a raw <<<"$csv"
  for item in "${raw[@]}"; do
    clean=$(trim "$item")
    [[ -n "$clean" ]] || die "$opt_name contains an empty item"
    PARSED_CSV_ITEMS+=("$clean")
  done
}

validate_selection() {
  local label=$1
  shift
  local -a selected=()
  local -a allowed=("$@")
  local item

  selected=("${PARSED_CSV_ITEMS[@]}")
  for item in "${selected[@]}"; do
    contains_item "$item" "${allowed[@]}" || die "Unknown $label: $item"
  done
}

validate_path_option() {
  local opt_name=$1
  local val=$2
  local normalized
  normalized=$(trim "$val")
  if [[ -z "$normalized" ]]; then
    die "$opt_name argument must not be empty"
  fi
  if [[ -n "$val" && "$val" == -* ]]; then
    die "$opt_name argument must not look like an option (starts with -): $val"
  fi
  if [[ -n "$val" && "$val" == *[[:cntrl:]]* ]]; then
    die "$opt_name argument must not contain control characters"
  fi
  if [[ -n "$val" && ("$val" == *'/../'* || "$val" == '../'* || "$val" == *'/..') ]]; then
    die "$opt_name argument must not contain path traversal (..): $val"
  fi
}

require_path_option() {
  local opt_name=$1
  local argc=$2
  local val=$3
  [[ $argc -ge 2 ]] || die "$opt_name requires an argument"
  validate_path_option "$opt_name" "$val"
}

validate_host() {
  local host=$1
  [[ -n "$host" ]] || die "Host name must not be empty"
  [[ "$host" != -* ]] || die "Host name must not look like an option (starts with -): $host"
  [[ "$host" != *[[:space:]]* ]] || die "Host name must not contain whitespace: $host"
  [[ "$host" != *"/"* ]] || die "Host name must not contain '/': $host"
  [[ "$host" != *"|"* ]] || die "Host name must not contain '|': $host"
  [[ "$host" != *[[:cntrl:]]* ]] || die "Host name must not contain control characters: $host"
}

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

append_failed_marker() {
  local round=$1
  local type=$2
  local host=$3
  printf '{"_failed":true,"round":"%s","type":"%s","host":"%s"}\n' \
    "$(json_escape "$round")" \
    "$(json_escape "$type")" \
    "$(json_escape "$host")"
}

default_hosts_config_path() {
  local script_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  echo "$script_dir/config/hosts.conf"
}

load_hosts_from_config() {
  local config_path=$1
  local line raw_key raw_val key val
  local -a loaded4=()
  local -a loaded6=()

  [[ -f "$config_path" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(trim "$line")
    [[ -n "$line" ]] || continue
    [[ "$line" == \#* ]] && continue

    if [[ "$line" != *=* ]]; then
      continue
    fi

    raw_key=${line%%=*}
    raw_val=${line#*=}
    key=$(trim "$raw_key")
    val=$(trim "$raw_val")
    key=${key,,}

    [[ -n "$val" ]] || continue

    case "$key" in
      ipv4)
        loaded4+=("$val")
        ;;
      ipv6)
        loaded6+=("$val")
        ;;
    esac
  done <"$config_path"

  if ((${#loaded4[@]} > 0)); then
    HOSTS_IPV4=("${loaded4[@]}")
  fi
  if ((${#loaded6[@]} > 0)); then
    HOSTS_IPV6=("${loaded6[@]}")
  fi
}

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

set_mtr_args_for_type() {
  local type=$1
  local -a base_mtr=(-b -i 1 -c 300 -r --json)
  case "$type" in
    ICMP4) mtr_args=(-4 "${base_mtr[@]}") ;;
    ICMP6) mtr_args=(-6 "${base_mtr[@]}") ;;
    UDP4) mtr_args=(-u -4 "${base_mtr[@]}") ;;
    UDP6) mtr_args=(-u -6 "${base_mtr[@]}") ;;
    TCP4) mtr_args=(-T -P 443 -4 "${base_mtr[@]}") ;;
    TCP6) mtr_args=(-T -P 443 -6 "${base_mtr[@]}") ;;
    MPLS4) mtr_args=(-e -4 "${base_mtr[@]}") ;;
    MPLS6) mtr_args=(-e -6 "${base_mtr[@]}") ;;
    AS4) mtr_args=(-z --aslookup -4 "${base_mtr[@]}") ;;
    AS6) mtr_args=(-z --aslookup -6 "${base_mtr[@]}") ;;
    *) die "Unknown test type: $type" ;;
  esac
}

hosts_for_type() {
  local type=$1
  if [[ "$type" == *6 ]]; then
    print_list "${HOSTS_IPV6[@]}"
  else
    print_list "${HOSTS_IPV4[@]}"
  fi
}

log_line() {
  local level=$1
  shift
  local msg=$*
  if [[ "${QUIET:-0}" -eq 1 ]]; then
    case "$level" in
      WARN | FAIL | ERROR | SUMMARY) ;;
      *) return 0 ;;
    esac
  fi

  local line
  line=$(printf '[%s] [%s] %s\n' "$(date +'%F %T')" "$level" "$msg")
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
      if [[ -n "$table_out" ]]; then
        echo "$table_out"
      else
        echo "(No results)"
      fi
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

compute_run_plan() {
  PLAN_ENTRIES=()

  local round type host
  local -a hosts=()
  for round in "${ROUND_ORDER[@]}"; do
    for type in "${TEST_ORDER[@]}"; do
      mapfile -t hosts < <(hosts_for_type "$type")
      for host in "${hosts[@]}"; do
        PLAN_ENTRIES+=("$round|$type|$host")
      done
    done
  done

  TOTAL_RUNS=${#PLAN_ENTRIES[@]}
}

execute_single_run() {
  local round=$1
  local type=$2
  local host=$3
  local run_index=$4

  local -a local_mtr_args=()
  local -a local_extra_args=()

  set_round_extra_args "$round"
  local_extra_args=("${extra_args[@]}")

  set_mtr_args_for_type "$type"
  local_mtr_args=("${mtr_args[@]}")

  log_line INFO "RUN [$run_index/$TOTAL_RUNS] round=$round type=$type host=$host"

  if ((DRY_RUN)); then
    log_line PLAN "mtr ${local_mtr_args[*]} ${local_extra_args[*]} $host"
    return 0
  fi

  CURRENT_TMP=$(mktemp "${TMPDIR:-/tmp}/mtr-suite.XXXXXXXX")

  if mtr "${local_mtr_args[@]}" "${local_extra_args[@]}" "$host" >"$CURRENT_TMP" 2>>"$TABLE_LOG"; then
    cat "$CURRENT_TMP" >>"$JSON_LOG"
    printf '\n' >>"$JSON_LOG"

    if ((DO_SUMMARY)); then
      if ! summarize_json "$CURRENT_TMP"; then
        log_line WARN "summary failed for round=$round type=$type host=$host"
      fi
    fi

    ((RUN_OK++)) || true
    log_line OK "round=$round type=$type host=$host"
  else
    {
      append_failed_marker "$round" "$type" "$host"
      cat "$CURRENT_TMP"
      printf '\n'
    } >>"$JSON_LOG"

    ((RUN_FAIL++)) || true
    log_line FAIL "round=$round type=$type host=$host"
  fi

  rm -f -- "$CURRENT_TMP"
  CURRENT_TMP=""
}

main() {
  local log_dir="${LOG_DIR:-$HOME/logs}"
  local json_log=""
  local table_log=""
  local types_csv=""
  local rounds_csv=""
  local hosts4_csv=""
  local hosts6_csv=""
  local list_types=0
  local list_rounds=0

  DO_SUMMARY=1
  DRY_RUN=0
  QUIET=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --log-dir)
        require_path_option "--log-dir" $# "$2"
        log_dir=$2
        shift 2
        ;;
      --json-log)
        require_path_option "--json-log" $# "$2"
        json_log=$2
        shift 2
        ;;
      --table-log)
        require_path_option "--table-log" $# "$2"
        table_log=$2
        shift 2
        ;;
      --types)
        [[ $# -ge 2 ]] || die "--types requires an argument"
        types_csv=$2
        shift 2
        ;;
      --rounds)
        [[ $# -ge 2 ]] || die "--rounds requires an argument"
        rounds_csv=$2
        shift 2
        ;;
      --hosts4)
        [[ $# -ge 2 ]] || die "--hosts4 requires an argument"
        hosts4_csv=$2
        shift 2
        ;;
      --hosts6)
        [[ $# -ge 2 ]] || die "--hosts6 requires an argument"
        hosts6_csv=$2
        shift 2
        ;;
      --list-types)
        list_types=1
        shift
        ;;
      --list-rounds)
        list_rounds=1
        shift
        ;;
      --no-summary)
        DO_SUMMARY=0
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --quiet)
        QUIET=1
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

  require_bash4

  if ((list_types)); then
    print_list "${ALL_TEST_TYPES[@]}"
    exit 0
  fi

  if ((list_rounds)); then
    print_list "${ALL_ROUNDS[@]}"
    exit 0
  fi

  TEST_ORDER=("${ALL_TEST_TYPES[@]}")
  ROUND_ORDER=("${ALL_ROUNDS[@]}")
  HOSTS_IPV4=("${DEFAULT_HOSTS_IPV4[@]}")
  HOSTS_IPV6=("${DEFAULT_HOSTS_IPV6[@]}")

  load_hosts_from_config "$(default_hosts_config_path)"

  if [[ -n "$types_csv" ]]; then
    parse_csv_to_array "$types_csv" "--types"
    validate_selection "test type" "${ALL_TEST_TYPES[@]}"
    TEST_ORDER=("${PARSED_CSV_ITEMS[@]}")
  fi

  if [[ -n "$rounds_csv" ]]; then
    parse_csv_to_array "$rounds_csv" "--rounds"
    validate_selection "round" "${ALL_ROUNDS[@]}"
    ROUND_ORDER=("${PARSED_CSV_ITEMS[@]}")
  fi

  if [[ -n "$hosts4_csv" ]]; then
    parse_csv_to_array "$hosts4_csv" "--hosts4"
    HOSTS_IPV4=("${PARSED_CSV_ITEMS[@]}")
  fi

  if [[ -n "$hosts6_csv" ]]; then
    parse_csv_to_array "$hosts6_csv" "--hosts6"
    HOSTS_IPV6=("${PARSED_CSV_ITEMS[@]}")
  fi

  local h
  for h in "${HOSTS_IPV4[@]}" "${HOSTS_IPV6[@]}"; do
    validate_host "$h"
  done

  if ((DRY_RUN == 0)); then
    require_cmd mtr
  fi
  if ((DO_SUMMARY)) && ((DRY_RUN == 0)); then
    require_cmd jq
    require_cmd column
  fi

  local ts
  local would_json_log=""
  local would_table_log=""
  ts=$(date +'%Y%m%d_%H%M%S')

  if ((DRY_RUN)); then
    would_json_log=${json_log:-"$log_dir/mtr_results_${ts}.json.log"}
    would_table_log=${table_log:-"$log_dir/mtr_summary_${ts}.log"}
    JSON_LOG=""
    TABLE_LOG=""
  else
    JSON_LOG=${json_log:-"$log_dir/mtr_results_${ts}.json.log"}
    TABLE_LOG=${table_log:-"$log_dir/mtr_summary_${ts}.log"}

    mkdir -p -- "$log_dir"
    if [[ -n "$json_log" ]]; then
      mkdir -p -- "$(dirname "$JSON_LOG")"
    fi
    if [[ -n "$table_log" ]]; then
      mkdir -p -- "$(dirname "$TABLE_LOG")"
    fi

    if [[ -d "$JSON_LOG" ]] || [[ -d "$TABLE_LOG" ]]; then
      die "Log path must not be an existing directory: JSON_LOG=$JSON_LOG TABLE_LOG=$TABLE_LOG"
    fi

    : >"$JSON_LOG"
    : >"$TABLE_LOG"
  fi

  CURRENT_TMP=""
  trap 'rm -f "${CURRENT_TMP:-}" 2>/dev/null; echo "Interrupted" >&2; exit 130' INT TERM
  trap 'rm -f "${CURRENT_TMP:-}" 2>/dev/null' EXIT

  compute_run_plan
  ((TOTAL_RUNS > 0)) || die "No runs planned. Check selected rounds/types/hosts."

  log_line INFO "Starting MTR tests (planned runs: $TOTAL_RUNS)"
  log_line INFO "Selected rounds: ${ROUND_ORDER[*]}"
  log_line INFO "Selected types: ${TEST_ORDER[*]}"
  log_line INFO "IPv4 hosts: ${HOSTS_IPV4[*]}"
  log_line INFO "IPv6 hosts: ${HOSTS_IPV6[*]}"

  if ((DRY_RUN)); then
    log_line SUMMARY "Dry-run only. Planned runs: $TOTAL_RUNS"
    log_line SUMMARY "Would write JSON_LOG=$would_json_log"
    log_line SUMMARY "Would write TABLE_LOG=$would_table_log"
  else
    log_line INFO "JSON_LOG=$JSON_LOG"
    log_line INFO "TABLE_LOG=$TABLE_LOG"
  fi

  RUN_OK=0
  RUN_FAIL=0

  local start_ts
  start_ts=$(date +%s)

  local entry round type host idx=0
  for entry in "${PLAN_ENTRIES[@]}"; do
    IFS='|' read -r round type host <<<"$entry"
    ((idx++)) || true
    execute_single_run "$round" "$type" "$host" "$idx"
  done

  local end_ts elapsed
  end_ts=$(date +%s)
  elapsed=$((end_ts - start_ts))

  if ((DRY_RUN)); then
    log_line SUMMARY "Dry-run complete. Planned runs: $TOTAL_RUNS"
    return 0
  fi

  log_line SUMMARY "All tests done. Passed: $RUN_OK, Failed: $RUN_FAIL, Elapsed: ${elapsed}s"
  log_line SUMMARY "Logs: JSON=$JSON_LOG TABLE=$TABLE_LOG"

  if ((RUN_FAIL > 0)); then
    exit 1
  fi
}

main "$@"
