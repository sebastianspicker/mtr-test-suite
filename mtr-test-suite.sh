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

Usage:
  ./mtr-test-suite.sh [--log-dir DIR] [--json-log PATH] [--table-log PATH] [--no-summary] [--dry-run]

Options:
  --log-dir DIR     Log directory (default: ~/logs)
  --json-log PATH   Override JSON_LOG path (default: <log-dir>/mtr_results_<timestamp>.json.log)
  --table-log PATH  Override TABLE_LOG path (default: <log-dir>/mtr_summary_<timestamp>.log)
  --no-summary      Skip jq/column summary tables (still logs JSON)
  --dry-run         Print planned runs without executing mtr
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

log() {
  printf '[%s] %s\n' "$(date +'%F %T')" "$*" | tee -a "$TABLE_LOG"
}

summarize_json() {
  local f=$1
  local dst_name dst_ip

  dst_name=$(jq -r '.report.dst_name? // .report.dst_addr? // .report.dst_ip? // .report.mtr.dst? // "???"' "$f")
  dst_ip=$(jq -r '.report.dst_addr? // .report.dst_ip? // .report.mtr.dst? // "???"' "$f")

  {
    echo
    echo "Results for: ${dst_name} (${dst_ip})"
    printf 'Hop\tHost\tIP\tLoss%%\tSnt\tLast\tAvg\tBest\tWrst\tStDev\n'
    jq -r '
      .report.hubs[]? as $h |
      [
        ($h.count // 0),
        ( $h.host // "???" | sub(" \\(.*"; "") ),
        ( $h.ip   // ( $h.host | capture("\\((?<ip>[^)]+)\\)").ip? ) // "???" ),
        ($h."Loss%" // 0),
        ($h.Snt     // 0),
        ($h.Last    // 0),
        ($h.Avg     // 0),
        ($h.Best    // 0),
        ($h.Wrst    // 0),
        ($h.StDev   // 0)
      ] | map(tostring) | @tsv' "$f" | column -t -s $'\t'
    echo
  } | tee -a "$TABLE_LOG"
}

main() {
  local log_dir="${LOG_DIR:-$HOME/logs}"
  local json_log=""
  local table_log=""
  local do_summary=1
  local dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --log-dir)
        [[ $# -ge 2 ]] || die "--log-dir requires an argument"
        log_dir=$2
        shift 2
        ;;
      --json-log)
        [[ $# -ge 2 ]] || die "--json-log requires an argument"
        json_log=$2
        shift 2
        ;;
      --table-log)
        [[ $# -ge 2 ]] || die "--table-log requires an argument"
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

  require_cmd mtr
  if ((do_summary)); then
    require_cmd jq
    require_cmd column
  fi

  mkdir -p "$log_dir"

  local ts
  ts=$(date +'%Y%m%d_%H%M%S')
  JSON_LOG=${json_log:-"$log_dir/mtr_results_${ts}.json.log"}
  TABLE_LOG=${table_log:-"$log_dir/mtr_summary_${ts}.log"}

  : >"$JSON_LOG"
  : >"$TABLE_LOG"

  trap 'log "Interrupted"; exit 130' INT TERM

  # Test definitions
  declare -A TESTS=(
    [ICMP4]="-4 -b -i 1 -c 300 -r --json"
    [ICMP6]="-6 -b -i 1 -c 300 -r --json"
    [UDP4]="-u -4 -b -i 1 -c 300 -r --json"
    [UDP6]="-u -6 -b -i 1 -c 300 -r --json"
    [TCP4]="-T -P 443 -4 -b -i 1 -c 300 -r --json"
    [TCP6]="-T -P 443 -6 -b -i 1 -c 300 -r --json"
    [MPLS4]="-e -4 -b -i 1 -c 300 -r --json"
    [MPLS6]="-e -6 -b -i 1 -c 300 -r --json"
    [AS4]="-z --aslookup -4 -b -i 1 -c 300 -r --json"
    [AS6]="-z --aslookup -6 -b -i 1 -c 300 -r --json"
  )
  TEST_ORDER=(ICMP4 ICMP6 UDP4 UDP6 TCP4 TCP6 MPLS4 MPLS6 AS4 AS6)

  HOSTS_IPV4=(netcologne.de google.com wikipedia.org amazon.de)
  HOSTS_IPV6=(netcologne.de google.com wikipedia.org)

  declare -A ROUNDS=(
    [Standard]=""
    [MTU1400]="-s 1400"
    [TOS_CS5]="--tos 160"
    [TOS_AF11]="--tos 40"
    [TTL10]="-m 10"
    [TTL64]="-m 64"
    [FirstTTL3]="-f 3"
    [Timeout5]="-Z 5"
  )
  ROUND_ORDER=(Standard MTU1400 TOS_CS5 TOS_AF11 TTL10 TTL64 FirstTTL3 Timeout5)

  log "Starting MTR tests (rounds: ${ROUND_ORDER[*]})"
  log "JSON_LOG=$JSON_LOG"
  log "TABLE_LOG=$TABLE_LOG"

  local round extra type host tmp
  local -a hosts mtr_args extra_args

  for round in "${ROUND_ORDER[@]}"; do
    extra=${ROUNDS[$round]}
    log "=== Round: $round ${extra:+(opts: $extra)} ==="

    for type in "${TEST_ORDER[@]}"; do
      log "--- $type tests in Round: $round ---"

      if [[ $type == *6 ]]; then
        hosts=("${HOSTS_IPV6[@]}")
      else
        hosts=("${HOSTS_IPV4[@]}")
      fi

      for host in "${hosts[@]}"; do
        log "-> $type -> $host"

        if ((dry_run)); then
          log "DRY RUN: mtr ${TESTS[$type]} ${extra:+$extra} $host"
          continue
        fi

        tmp=$(mktemp "${TMPDIR:-/tmp}/mtr-suite.XXXXXXXX")
        if ! read -r -a mtr_args <<<"${TESTS[$type]}"; then
          rm -f "$tmp"
          die "Failed to parse test args for $type"
        fi
        extra_args=()
        if [[ -n ${extra} ]]; then
          if ! read -r -a extra_args <<<"${extra}"; then
            rm -f "$tmp"
            die "Failed to parse round args for $round"
          fi
        fi

        if ! mtr "${mtr_args[@]}" "${extra_args[@]}" "$host" >"$tmp" 2>>"$TABLE_LOG"; then
          log "WARN: error in $type -> $host (continuing)"
        fi

        cat "$tmp" >>"$JSON_LOG"
        printf '\n' >>"$JSON_LOG"

        if ((do_summary)); then
          if ! summarize_json "$tmp"; then
            log "WARN: summary failed for $type -> $host (continuing)"
          fi
        fi

        rm -f "$tmp"
        log "OK: completed $type -> $host"
      done
    done
  done

  log "All tests done."
}

main "$@"
