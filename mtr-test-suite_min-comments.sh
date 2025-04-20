#!/usr/bin/env bash
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash: bash $0" >&2
  exit 1
fi
set -euo pipefail
# -------------------------------------------------------------------
# mtr-tests-enhanced.sh v1.0 – Advanced MTR Testing Suite
# -------------------------------------------------------------------

# ── paths ──────────────────────────────────────────────────────────
LOG_DIR="$HOME/logs"
TS=$(date +'%Y%m%d_%H%M%S')
JSON_LOG="$LOG_DIR/mtr_results_${TS}.json.log"
TABLE_LOG="$LOG_DIR/mtr_summary_${TS}.log"
mkdir -p "$LOG_DIR"
:> "$JSON_LOG"  :> "$TABLE_LOG"

log() { echo "[$(date +'%F %T')] $*" | tee -a "$TABLE_LOG"; }

# ── table formatter (fixed) ────────────────────────────────────────
summarize_json() {
  local f=$1
  local dst_name dst_ip
  dst_name=$(jq -r '.report.dst_name? // .report.dst_addr? // .report.dst_ip? // .report.mtr.dst? // "???"' "$f")
  dst_ip=$(jq -r   '.report.dst_addr? // .report.dst_ip? // .report.mtr.dst? // "???"'             "$f")

  {
    echo; echo "Results for: ${dst_name} (${dst_ip})"
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

# ── test definitions ───────────────────────────────────────────────
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
TEST_ORDER=(ICMP4 ICMP6 UDP4 UDP6 TCP4 TCP6 MPLS4 MPLS6 AS4 AS6)  # << only once

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

# ── execution loop ─────────────────────────────────────────────────
log "Starting MTR tests (rounds: ${ROUND_ORDER[*]})"
for ROUND in "${ROUND_ORDER[@]}"; do
  EXTRA=${ROUNDS[$ROUND]}
  log "=== Round: $ROUND ${EXTRA:+(opts: $EXTRA)} ==="

  for TYPE in "${TEST_ORDER[@]}"; do
    OPTS="${TESTS[$TYPE]} $EXTRA"
    log "--- $TYPE tests in Round: $ROUND ---"

    [[ $TYPE == *6 ]] && HOSTS=("${HOSTS_IPV6[@]}") || HOSTS=("${HOSTS_IPV4[@]}")

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
