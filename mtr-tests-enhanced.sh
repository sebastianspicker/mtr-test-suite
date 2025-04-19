```bash
#!/usr/bin/env bash
# Ensure this script runs under Bash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash: bash $0" >&2
  exit 1
fi
set -euo pipefail

# -------------------------------------------------------------------
# mtr-tests-enhanced.sh v1.0 – Advanced MTR Testing Suite
# Estimated runtime with defaults (~280 runs × 5 min ≈ 24 h)
#
# Test Types (in exact sequence):
#  1) ICMP4
#  2) ICMP6
#  3) UDP4
#  4) UDP6
#  5) TCP4
#  6) TCP6
#  7) MPLS4
#  8) MPLS6
#  9) AS4
# 10) AS6
#
# Round Scenarios (in defined order):
#  1) Standard
#  2) MTU1400
#  3) TOS_CS5
#  4) TOS_AF11
#  5) TTL10
#  6) TTL64
#  7) FirstTTL3
#  8) Timeout5
#
# Outputs:
#  - raw JSON → JSON_LOG
#  - formatted tables → TABLE_LOG
#  - real-time logs to console & TABLE_LOG
# -------------------------------------------------------------------

# Setup
LOG_DIR="$HOME/logs"
TS=$(date +'%Y%m%d_%H%M%S')
JSON_LOG="$LOG_DIR/mtr_results_${TS}.json.log"
TABLE_LOG="$LOG_DIR/mtr_summary_${TS}.log"
mkdir -p "$LOG_DIR"
touch "$JSON_LOG" "$TABLE_LOG"

# Logging helper
log() {
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" | tee -a "$TABLE_LOG"
}

# Summarize JSON to table
summarize_json() {
  local file="$1"
  local dst_name dst_ip
  dst_name=$(jq -r '.report.dst_name? // .report.dst_addr? // .report.dst_ip? // .report.mtr.dst? // "Unknown"' "$file")
  dst_ip=$(jq -r '.report.dst_addr? // .report.dst_ip? // .report.mtr.dst? // "Unknown"' "$file")

  {
    echo
    echo "Results for: ${dst_name} (${dst_ip})"
    echo -e "Hop	Host	IP	Loss%	Snt	Last	Avg	Best	Wrst	StDev"
    jq -r '
      .report.hubs[]? |
        (.count|tostring)        as $hop  |
        (.host//"N/A")          as $host |
        (.ip//"N/A")            as $ip   |
        (."Loss%"|tostring)     as $loss|
        (.Snt|tostring)          as $snt  |
        (.Last|tostring)         as $last|
        (.Avg|tostring)          as $avg  |
        (.Best|tostring)         as $best |
        (.Wrst|tostring)         as $wrst |
        (.StDev|tostring)        as $stdev|
        [ $hop, $host, $ip, $loss, $snt, $last, $avg, $best, $wrst, $stdev ] | @tsv
    ' "$file" | column -t -s $'\t'
    echo
  } | tee -a "$TABLE_LOG"
}

# Test types
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
# enforce test order
TEST_ORDER=(ICMP4 ICMP6 UDP4 UDP6 TCP4 TCP6 MPLS4 MPLS6 AS4 AS6)
TEST_ORDER=(ICMP4 ICMP6 UDP4 UDP6 TCP4 TCP6 MPLS4 MPLS6 AS4 AS6)

# Host lists
HOSTS_IPV4=(netcologne.de google.com wikipedia.org amazon.de)
HOSTS_IPV6=(netcologne.de google.com wikipedia.org)

# Rounds
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
# enforce round order
ROUND_ORDER=(Standard MTU1400 TOS_CS5 TOS_AF11 TTL10 TTL64 FirstTTL3 Timeout5)

# Execute
log "Starting MTR tests (rounds: ${ROUND_ORDER[*]})"
for ROUND in "${ROUND_ORDER[@]}"; do
  EXTRA=${ROUNDS[$ROUND]}
  log "=== Round: $ROUND ${EXTRA:+(opts: $EXTRA)} ==="

  for TYPE in "${TEST_ORDER[@]}"; do
    BASE_OPTS=${TESTS[$TYPE]}
    OPTS="$BASE_OPTS $EXTRA"
    log "--- $TYPE tests in Round: $ROUND ---"

    if [[ "$TYPE" == *6 ]]; then
      HOSTS=("${HOSTS_IPV6[@]}")
    else
      HOSTS=("${HOSTS_IPV4[@]}")
    fi

    for H in "${HOSTS[@]}"; do
      log "→ $TYPE → $H"
      tmp=$(mktemp)
      if ! mtr $OPTS "$H" 2>&1 | tee -a "$JSON_LOG" >"$tmp"; then
        log "⚠️  Error in $TYPE → $H, continuing"
      fi
      summarize_json "$tmp"
      rm -f "$tmp"
      log "✓ Completed $TYPE → $H"
    done
  done
done

log "All tests done. JSON_LOG=$JSON_LOG, TABLE_LOG=$TABLE_LOG"
```

