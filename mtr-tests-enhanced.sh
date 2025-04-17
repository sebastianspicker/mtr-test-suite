#!/usr/bin/env bash
# Ensure the script is executed with Bash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash: bash $0" >&2
  exit 1
fi
set -euo pipefail

# -------------------------------------------------------------------
# mtr-tests-enhanced.sh v0.5 – Advanced MTR Testing Suite
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

# Setup
LOG_DIR="$HOME/logs"
TS=$(date +'%Y%m%d_%H%M%S')
OUTPUT="$LOG_DIR/mtr_results_$TS.log"
mkdir -p "$LOG_DIR"

# Logging function: prepend timestamp
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Test types and options (including TCP tests on port 443)
declare -A TESTS=(
  [IPv4]="-4"
  [IPv6]="-6"
  [UDP4]="-u -4"
  [UDP6]="-u -6"
  [ICMP4]="-I -4"
  [ICMP6]="-I -6"
  [TCP4]="-T -P 443 -4"
  [TCP6]="-T -P 443 -6"
)

# Host lists
HOSTS_IPV4=( netcologne.de google.com wikipedia.org amazon.de )
HOSTS_IPV6=( netcologne.de google.com wikipedia.org )

# Test rounds: various scenarios
# - Standard: default packet size
# - MTU1400: 1400-byte packets for MTU/fragmentation testing
# - DSCP_CS5: DSCP CS5 (high priority)
# - DSCP_AF11: DSCP AF11 (lower priority)
# - TTL10: limit hops to 10
# - TTL64: extend max hops to 64
declare -A ROUNDS=(
  [Standard]=""
  [MTU1400]="-s 1400"
  [DSCP_CS5]="--dscp 40"
  [DSCP_AF11]="--dscp 10"
  [TTL10]="-m 10"
  [TTL64]="-m 64"
)

# Start testing
log "Starting MTR tests (rounds: ${!ROUNDS[*]})" | tee -a "$OUTPUT"

for ROUND in "${!ROUNDS[@]}"; do
  EXTRA_OPTS="${ROUNDS[$ROUND]}"
  log "=== Round: $ROUND ${EXTRA_OPTS:+(options: $EXTRA_OPTS)} ===" | tee -a "$OUTPUT"

  for TYPE in "${!TESTS[@]}"; do
    BASE_OPTS="${TESTS[$TYPE]} -n -b -i 0.5 -c 600 -r --json"
    OPTIONS="$BASE_OPTS $EXTRA_OPTS"

    log "--- Running $TYPE tests [Round: $ROUND] ---" | tee -a "$OUTPUT"

    # Select appropriate host list based on protocol type
    if [[ $TYPE == IPv6 || $TYPE == UDP6 || $TYPE == ICMP6 || $TYPE == TCP6 ]]; then
      HOSTS=( "${HOSTS_IPV6[@]}" )
    else
      HOSTS=( "${HOSTS_IPV4[@]}" )
    fi

    for HOST in "${HOSTS[@]}"; do
      log "Running $TYPE → $HOST [Round: $ROUND]" | tee -a "$OUTPUT"
      # Execute MTR: live output to console and append to log; catch errors
      mtr $OPTIONS "$HOST" 2>&1 | tee -a "$OUTPUT" || {
        log "Error during $TYPE → $HOST in round $ROUND, continuing" | tee -a "$OUTPUT"
      }
      log "✓ Completed $TYPE → $HOST [Round: $ROUND]" | tee -a "$OUTPUT"
    done
  done

done

log "All tests completed. Results stored in: $OUTPUT" | tee -a "$OUTPUT"
