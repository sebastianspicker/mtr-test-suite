#!/usr/bin/env bash
# Ensure this script runs under Bash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash: bash $0" >&2
  exit 1
fi
set -euo pipefail

# -------------------------------------------------------------------
# mtr-tests-enhanced.sh v0.9 – Advanced MTR Testing Suite
#
# This script automates comprehensive network path analysis using MTR
# for a predefined list of hosts, performing multiple test rounds:
#
# 1) Standard mode: default packet size
# 2) MTU tests: 1400-byte packets to detect fragmentation and MTU issues
# 3) QoS/DSCP tests: simulate different traffic classes
#    (DSCP CS5 for high priority, DSCP AF11 for lower priority)
# 4) TTL variations: limit max hops to 10 or extend to 64
#    to uncover asymmetric routes and TTL expiry behaviors
# 5) Protocol tests: ICMP, UDP, and TCP on port 443
#    to verify protocol and firewall behavior
#
# All measurements are output in JSON format with timestamps,
# displayed live in the terminal, and logged to:
# $HOME/logs/mtr_results_YYYYMMDD_HHMMSS.log
# Errors in individual test rounds are recorded but do not
# interrupt the overall process.
# -------------------------------------------------------------------

# 1) Setup
LOG_DIR="$HOME/logs"
TS=$(date +'%Y%m%d_%H%M%S')
OUTPUT="$LOG_DIR/mtr_results_$TS.log"
mkdir -p "$LOG_DIR"
touch "$OUTPUT"

# 2) Redirect all stdout/stderr to console AND append to log file
exec > >(tee -a "$OUTPUT") 2>&1

# 3) Logging function: prepend timestamp
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# 4) Summarize JSON into a table, include hostname and IP per hop
summarize_json() {
  local file="$1"
  # extract destination name and IP
  local dst_name dst_ip
  dst_name=$(jq -r '.report.dst_name' "$file")
  dst_ip=$(jq -r '.report.dst_addr // .report.dst_ip' "$file")

  echo
  echo "Results for: $dst_name ($dst_ip)"
  echo "Hop  Host               IP               Loss%  Snt  Last   Avg    Best   Wrst   StDev"
  # include host and ip for each hop
  jq -r '.report.hubs[] | [(.count|tostring), .host, .ip, (."Loss%"|tostring), (.Snt|tostring), (.Last|tostring), (.Avg|tostring), (.Best|tostring), (.Wrst|tostring), (.StDev|tostring)] | @tsv' "$file" |
    column -t
  echo
}

# 5) Define test types
declare -A TESTS=(
  [IPv4]="-4"
  [IPv6]="-6"
  [UDP4]="-u -4"
  [UDP6]="-u -6"
  [TCP4]="-T -P 443 -4"
  [TCP6]="-T -P 443 -6"
)

# 6) Host lists
HOSTS_IPV4=( netcologne.de google.com wikipedia.org amazon.de )
HOSTS_IPV6=( netcologne.de google.com wikipedia.org )

# 7) Test rounds: scenarios
declare -A ROUNDS=(
  [Standard]=""            # default packet size
  [MTU1400]="-s 1400"     # fragmentation/MTU check
  [DSCP_CS5]="--dscp 40"  # high priority traffic
  [DSCP_AF11]="--dscp 10" # lower priority traffic
  [TTL10]="-m 10"         # limit to 10 hops
  [TTL64]="-m 64"         # extend to 64 hops
)

# 8) Start tests
log "Starting MTR tests (rounds: ${!ROUNDS[*]})"

for ROUND in "${!ROUNDS[@]}"; do
  EXTRA_OPTS="${ROUNDS[$ROUND]}"
  log "=== Round: $ROUND ${EXTRA_OPTS:+(options: $EXTRA_OPTS)} ==="

  for TYPE in "${!TESTS[@]}"; do
    BASE_OPTS="${TESTS[$TYPE]} -n -b -i 1 -c 300 -r --json"
    OPTIONS="$BASE_OPTS $EXTRA_OPTS"

    log "--- Running $TYPE tests [Round: $ROUND] ---"

    if [[ "$TYPE" == *6 ]]; then
      HOSTS=( "${HOSTS_IPV6[@]}" )
    else
      HOSTS=( "${HOSTS_IPV4[@]}" )
    fi

    for HOST in "${HOSTS[@]}"; do
      log "Running $TYPE → $HOST [Round: $ROUND]"
      tmpfile=$(mktemp)
      # run MTR, append JSON to log and save to tmpfile
      if ! mtr $OPTIONS "$HOST" 2>&1 | tee -a "$OUTPUT" > "$tmpfile"; then
        log "Error during $TYPE → $HOST in round $ROUND, continuing"
      fi
      # print human-readable table with hostname & IP, correct Loss%
      summarize_json "$tmpfile"
      rm -f "$tmpfile"
      log "✓ Completed $TYPE → $HOST [Round: $ROUND]"
    done
  done

done

log "All tests completed. Results written to: $OUTPUT"
