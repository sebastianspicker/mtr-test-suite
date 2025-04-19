#!/usr/bin/env bash
# Ensure this script runs under Bash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash: bash $0" >&2
  exit 1
fi
set -euo pipefail

# -------------------------------------------------------------------
# mtr-tests-enhanced.sh v1.0 – Advanced MTR Testing Suite
# Estimated runtime with current defaults (~280 runs × 5 min each ≈ 24 hours)
#
# Performs for each host & test type:
#  1) Standard mode
#  2) MTU tests (1400‑byte)
#  3) QoS/TOS tests (CS5, AF11 via --tos)
#  4) TTL variations (10, 64, first‑TTL=3)
#  5) Protocol tests (ICMP, UDP, TCP/443, MPLS, AS‑lookup)
#
# Outputs:
#  - raw MTR JSON logs to JSON_LOG (mtr_results_TIMESTAMP.json.log)
#  - summarized tables to TABLE_LOG (mtr_summary_TIMESTAMP.log)
#  - all script logs (progress & errors) to console
# -------------------------------------------------------------------

# 1) Setup
LOG_DIR="$HOME/logs"
TS=$(date +'%Y%m%d_%H%M%S')
JSON_LOG="$LOG_DIR/mtr_results_${TS}.json.log"
TABLE_LOG="$LOG_DIR/mtr_summary_${TS}.log"
mkdir -p "$LOG_DIR"
touch "$JSON_LOG" "$TABLE_LOG"

# 2) Logging helper (console only)
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# 3) Summarize a single JSON output into a table (console + TABLE_LOG)
summarize_json() {
  local file="$1"
  local dst_name dst_ip
  dst_name=$(jq -r '.report.dst_name? // .report.dst_addr? // .report.dst_ip? // .report.mtr.dst? // "Unknown"' "$file")
  dst_ip=$(jq -r '.report.dst_addr? // .report.dst_ip? // .report.mtr.dst? // "Unknown"' "$file")

  {
    echo
    echo "Results for: ${dst_name} (${dst_ip})"
    echo "Hop  Host                                               IP        Loss%   Snt   Last    Avg     Best    Wrst    StDev"
    jq -r '
      .report.hubs[]? |
        (.count   | tostring)         as $hop  |
        (.host//"N/A")                as $host |
        (.ip//"N/A")                  as $ip   |
        (."Loss%" | tostring)         as $loss|
        (.Snt     | tostring)         as $snt |
        (.Last    | tostring)         as $last|
        (.Avg     | tostring)         as $avg |
        (.Best    | tostring)         as $best|
        (.Wrst    | tostring)         as $wrst|
        (.StDev   | tostring)         as $stdev|
        [ $hop, $host, $ip, $loss, $snt, $last, $avg, $best, $wrst, $stdev ] |
        @tsv
    ' "$file" | column -t
    echo
  } | tee -a "$TABLE_LOG"
}

# 4) Test types (no -n, so hostnames resolve; added MPLS/AS)
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

# 5) Host lists
HOSTS_IPV4=( netcologne.de google.com wikipedia.org amazon.de )
HOSTS_IPV6=( netcologne.de google.com wikipedia.org )

# 6) Test rounds (added FirstTTL3, Timeout5)
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

# 7) Run everything
log "Starting MTR tests (rounds: ${!ROUNDS[*]})"
for ROUND in "${!ROUNDS[@]}"; do
  EXTRA=${ROUNDS[$ROUND]}
  log "=== Round: $ROUND ${EXTRA:+(opts: $EXTRA)} ==="

  for TYPE in "${!TESTS[@]}"; do
    BASE_OPTS=${TESTS[$TYPE]}
    OPTS="$BASE_OPTS $EXTRA"
    log "--- $TYPE tests [Round: $ROUND] ---"

    if [[ "$TYPE" == *6 ]]; then
      HOSTS=( "${HOSTS_IPV6[@]}" )
    else
      HOSTS=( "${HOSTS_IPV4[@]}" )
    fi

    for H in "${HOSTS[@]}"; do
      log "→ $TYPE → $H"
      tmp=$(mktemp)
      # raw JSON to JSON_LOG
      if ! mtr $OPTS "$H" 2>&1 | tee -a "$JSON_LOG" >"$tmp"; then
        log "⚠️  Error in $TYPE → $H, continuing"
      fi
      # summarize to TABLE_LOG + console
      summarize_json "$tmp"
      rm -f "$tmp"
      log "✓ Completed $TYPE → $H"
    done
  done
done

log "All tests completed. JSON logs: $JSON_LOG, summaries: $TABLE_LOG"
