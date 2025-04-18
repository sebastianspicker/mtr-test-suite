#!/usr/bin/env bash
# Ensure this script runs under Bash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash: bash $0" >&2
  exit 1
fi
set -euo pipefail

# -------------------------------------------------------------------
# mtr-tests-enhanced.sh v0.9 – Advanced MTR Testing Suite 
# Estimated runtime with current defaults (300 pings × 1 s × 126 runs): ~11 hours
#
# Performs for each host & test type:
#  1) Standard mode
#  2) MTU tests (1400‑byte)
#  3) DSCP QoS (CS5, AF11)
#  4) TTL variations (10, 64)
#  5) Protocol tests (ICMP, UDP, TCP/443)
#
# Outputs JSON per run, summarizes into a human table (with host/IP),
# logs live to console and to $HOME/logs/mtr_results_TIMESTAMP.log.
# -------------------------------------------------------------------

# 1) Setup
LOG_DIR="$HOME/logs"
TS=$(date +'%Y%m%d_%H%M%S')
OUTPUT="$LOG_DIR/mtr_results_$TS.log"
mkdir -p "$LOG_DIR"
touch "$OUTPUT"

# 2) Redirect all stdout/stderr to console AND log
exec > >(tee -a "$OUTPUT") 2>&1

# 3) Timestamped log helper
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# 4) Summarize a single JSON output into a table
summarize_json() {
  local file="$1"
  # extract destination name & IP (fallbacks for different JSON schemas)
  local dst_name dst_ip
  dst_name=$(jq -r '
      .report.dst_name?             // 
      .report.dst_addr?             // 
      .report.dst_ip?               // 
      .report.mtr.dst?              // 
      empty' "$file")
  dst_ip=$(jq -r '
      .report.dst_addr?             // 
      .report.dst_ip?               // 
      .report.mtr.dst?              // 
      empty' "$file")

  echo
  echo "Results for: ${dst_name:-Unknown} (${dst_ip:-Unknown})"
  echo "Hop  Host                          IP               Loss%   Snt   Last    Avg     Best    Wrst    StDev"
  jq -r '
    .report.hubs[]? |
      ( .count                     | tostring ) as $hop
    | ( .host                      | sub(" \\(.*\\)"; "") )  as $host
    | ( ( .host                      | capture("\\((?<ip>[^)]+)\\)").ip )
        // .ip? // "" )             as $ip
    | (."Loss%"                    | tostring ) as $loss
    | (.Snt                        | tostring ) as $snt
    | (.Last                       | tostring ) as $last
    | (.Avg                        | tostring ) as $avg
    | (.Best                       | tostring ) as $best
    | (.Wrst                       | tostring ) as $wrst
    | (.StDev                      | tostring ) as $stdev
    | [ $hop, $host, $ip, $loss, $snt, $last, $avg, $best, $wrst, $stdev ]
      | @tsv
  ' "$file" | column -t
  echo
}

# 5) Test types
declare -A TESTS=(
  [ICMP4]="-4 -n -b -i 1 -c 300 -r --json"
  [ICMP6]="-6 -n -b -i 1 -c 300 -r --json"
  [UDP4]="-u -4 -n -b -i 1 -c 300 -r --json"
  [UDP6]="-u -6 -n -b -i 1 -c 300 -r --json"
  [TCP4]="-T -P 443 -4 -n -b -i 1 -c 300 -r --json"
  [TCP6]="-T -P 443 -6 -n -b -i 1 -c 300 -r --json"
)

# 6) Host lists
HOSTS_IPV4=( netcologne.de google.com wikipedia.org amazon.de )
HOSTS_IPV6=( netcologne.de google.com wikipedia.org )

# 7) Test rounds
declare -A ROUNDS=(
  [Standard]=""
  [MTU1400]="-s 1400"
  [DSCP_CS5]="--dscp 40"
  [DSCP_AF11]="--dscp 10"
  [TTL10]="-m 10"
  [TTL64]="-m 64"
)

# 8) Run everything
log "Starting MTR tests (rounds: ${!ROUNDS[*]})"
for ROUND in "${!ROUNDS[@]}"; do
  EXTRA_OPTS=${ROUNDS[$ROUND]}
  log "=== Round: $ROUND ${EXTRA_OPTS:+(options: $EXTRA_OPTS)} ==="

  for TYPE in "${!TESTS[@]}"; do
    BASE_OPTS=${TESTS[$TYPE]}
    OPTS="$BASE_OPTS $EXTRA_OPTS"

    log "--- Running $TYPE tests [Round: $ROUND] ---"
    # choose IPv4 vs IPv6 host list
    if [[ "$TYPE" == *6 ]]; then
      HOSTS=( "${HOSTS_IPV6[@]}" )
    else
      HOSTS=( "${HOSTS_IPV4[@]}" )
    fi

    for HOST in "${HOSTS[@]}"; do
      log "→ $TYPE → $HOST [Round: $ROUND]"
      tmpfile=$(mktemp)
      if ! mtr $OPTS "$HOST" 2>&1 | tee -a "$OUTPUT" >"$tmpfile"; then
        log "⚠️  Error during $TYPE → $HOST in round $ROUND, continuing"
      fi
      summarize_json "$tmpfile"
      rm -f "$tmpfile"
      log "✓ Completed $TYPE → $HOST [Round: $ROUND]"
    done
  done
done

log "All tests completed. Results written to: $OUTPUT"
