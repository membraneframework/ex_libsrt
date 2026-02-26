#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BASELINE_REF="${BASELINE_REF:-HEAD^}"
CANDIDATE_REF="${CANDIDATE_REF:-HEAD}"
RUNS="${RUNS:-3}"
DURATION_SECONDS="${DURATION_SECONDS:-60}"
CLIENTS="${CLIENTS:-1}"
PAYLOAD_SIZE="${PAYLOAD_SIZE:-1316}"
LATENCY_MS="${LATENCY_MS:-120}"
SNDTIMEO="${SNDTIMEO:--1}"

WORK_ROOT="$(mktemp -d -t exlibsrt-listener-ab.XXXXXX)"
BASELINE_WT="$WORK_ROOT/baseline"
CANDIDATE_WT="$WORK_ROOT/candidate"
RESULTS_TSV="$WORK_ROOT/results.tsv"

cleanup() {
  git worktree remove "$BASELINE_WT" --force >/dev/null 2>&1 || true
  git worktree remove "$CANDIDATE_WT" --force >/dev/null 2>&1 || true
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

echo "[ab] baseline_ref=$BASELINE_REF candidate_ref=$CANDIDATE_REF"
echo "[ab] runs=$RUNS duration=${DURATION_SECONDS}s clients=$CLIENTS payload=$PAYLOAD_SIZE latency=$LATENCY_MS sndtimeo=$SNDTIMEO"

git worktree add --detach "$BASELINE_WT" "$BASELINE_REF" >/dev/null
git worktree add --detach "$CANDIDATE_WT" "$CANDIDATE_REF" >/dev/null

prepare_tree() {
  local wt="$1"
  echo "[ab] preparing $(basename "$wt")"
  mkdir -p "$wt/scripts"
  cp "$ROOT_DIR/scripts/listener_send_bench.exs" "$wt/scripts/listener_send_bench.exs"
  (
    cd "$wt"
    MIX_ENV=dev mix deps.get >/dev/null
    MIX_ENV=dev mix compile >/dev/null
  )
}

run_once() {
  local label="$1"
  local wt="$2"
  local run="$3"
  local port="$4"

  local out
  out="$(
    cd "$wt"
    MIX_ENV=dev mix run --no-start scripts/listener_send_bench.exs \
      --duration "$DURATION_SECONDS" \
      --clients "$CLIENTS" \
      --payload "$PAYLOAD_SIZE" \
      --latency "$LATENCY_MS" \
      --port "$port" \
      --sndtimeo "$SNDTIMEO" 2>&1 | rg '^RESULT ' || true
  )"

  if [[ -z "$out" ]]; then
    echo "[ab] $label run=$run failed to produce RESULT line"
    return 1
  fi

  echo "[ab] $label run=$run $out"
  python3 - "$label" "$run" "$out" >> "$RESULTS_TSV" <<'PY'
import sys
label, run, line = sys.argv[1], sys.argv[2], sys.argv[3]
parts = line.strip().split()
kv = {}
for p in parts[1:]:
    if '=' in p:
        k, v = p.split('=', 1)
        kv[k] = v
keys = [
  'send_mbps', 'recv_mbps', 'send_errors', 'srt_mbps_send_rate', 'pkt_snd_drop', 'pkt_retrans',
  'sent_bytes', 'recv_bytes', 'duration_s', 'clients', 'payload', 'sndtimeo'
]
vals = [kv.get(k, '') for k in keys]
print('\t'.join([label, run] + vals))
PY
}

prepare_tree "$BASELINE_WT"
prepare_tree "$CANDIDATE_WT"

echo -e "label\trun\tsend_mbps\trecv_mbps\tsend_errors\tsrt_mbps_send_rate\tpkt_snd_drop\tpkt_retrans\tsent_bytes\trecv_bytes\tduration_s\tclients\tpayload\tsndtimeo" > "$RESULTS_TSV"

for i in $(seq 1 "$RUNS"); do
  run_once baseline "$BASELINE_WT" "$i" "$((20000 + i))"
  run_once candidate "$CANDIDATE_WT" "$i" "$((21000 + i))"
done

python3 - "$RESULTS_TSV" <<'PY'
import sys
from statistics import mean

path = sys.argv[1]
rows = []
with open(path, 'r', encoding='utf-8') as f:
    header = f.readline().strip().split('\t')
    for line in f:
        parts = line.strip().split('\t')
        if len(parts) != len(header):
            continue
        row = dict(zip(header, parts))
        rows.append(row)

def fval(x):
    try:
        return float(x)
    except Exception:
        return 0.0

for label in ('baseline', 'candidate'):
    subset = [r for r in rows if r['label'] == label]
    if not subset:
        print(f'[ab] {label}: no rows')
        continue
    send = [fval(r['send_mbps']) for r in subset]
    recv = [fval(r['recv_mbps']) for r in subset]
    errs = [fval(r['send_errors']) for r in subset]
    srt = [fval(r['srt_mbps_send_rate']) for r in subset]
    drop = [fval(r['pkt_snd_drop']) for r in subset]
    retr = [fval(r['pkt_retrans']) for r in subset]
    print(f"[ab] {label}: send_avg={mean(send):.3f} recv_avg={mean(recv):.3f} srt_send_rate_avg={mean(srt):.3f} send_errors_avg={mean(errs):.1f} pkt_snd_drop_avg={mean(drop):.1f} pkt_retrans_avg={mean(retr):.1f}")

base = [r for r in rows if r['label'] == 'baseline']
cand = [r for r in rows if r['label'] == 'candidate']
if base and cand:
    b = mean([fval(r['send_mbps']) for r in base])
    c = mean([fval(r['send_mbps']) for r in cand])
    ratio = (c / b) if b > 0 else 0.0
    print(f"[ab] delta_send_mbps={c-b:+.3f} ratio={ratio:.3f}")

print(f"[ab] raw_results={path}")
PY
