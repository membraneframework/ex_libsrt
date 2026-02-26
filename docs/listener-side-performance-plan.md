# Listener-side performance improvement plan (ex_libsrt)

## Goals

1. Increase sustained listener egress throughput (`server -> connected clients`).
2. Reduce dirty scheduler pressure from send-heavy workloads.
3. Improve tail latency and resilience under receiver backpressure.
4. Preserve backwards compatibility of current Elixir API.
5. Add observability to tune with data, not guesswork.

---

## Phase 0 — Baseline and acceptance gates (before code changes)

### 0.1 Reproducible benchmark matrix

Create three repeatable scenarios:

- **A. Native baseline**: `srt-live-transmit` listener sender -> caller receiver
- **B. ex_libsrt direct**: `ExLibSRT.Server.send_data/3` hot loop to N clients
- **C. App path**: real sender app flow (if applicable)

Run each in the same environment class (CPU/memory/network).

### 0.2 Metrics to capture (1s cadence)

- App-layer send throughput (bytes/s, Mbps)
- Sender SRT stats (`srt_bstats`), especially:
  - `mbpsSendRate`
  - `pktSndDrop`
  - `pktRetrans`
  - `pktSndLoss`
- BEAM runtime:
  - dirty scheduler utilization
  - reductions
  - sender process mailbox length
- Native path (once added):
  - queue depth (bytes/messages)
  - enqueue→send latency

### 0.3 Acceptance criteria

- Avg throughput >= **95% of `srt-live-transmit` baseline** for same test.
- p95 send latency under agreed threshold.
- No dirty scheduler starvation symptoms.

---

## Phase 1 — Low-risk socket behavior fixes (quick wins)

### 1.1 Enforce non-blocking send semantics

#### Problem
Listener path does not explicitly ensure egress sockets are configured for non-blocking send behavior.

#### Change
- Set `SRTO_SNDSYN = 0` on listener/accepted sockets used for egress.
- Keep `SRTO_RCVSYN = 0` behavior for receive side.

#### Validation
- Under receiver backpressure, `send_server_data` should not block unexpectedly.
- Dirty scheduler occupancy should drop in send-heavy tests.

### 1.2 Add send timeout policy

- Set `SRTO_SNDTIMEO` (configurable, sane default e.g. 50–200ms).
- On timeout, return explicit error/backpressure signal instead of indefinite wait.

### 1.3 Expose key egress tuning options

Add to Native/Elixir options:

- `sndtimeo`
- `maxbw`
- `inputbw`
- `oheadbw`
- `peerlatency`
- `rcvlatency`
- `tlpktdrop`

This narrows the tuning gap with `srt-live-transmit`.

---

## Phase 2 — Architectural fix: native async send pipeline

### 2.1 Add per-connection native send queue

#### Problem
Current path sends directly inside NIF call (`send_server_data -> srt_sendmsg`), which scales poorly under high message rates and backpressure.

#### Design
- Each active connection gets a native queue (deque/ring buffer).
- `send_server_data` enqueues only.
- Dedicated native sender worker drains queue.

#### Backpressure policy
- Configurable max queue bytes/messages.
- Overflow behavior (configurable):
  - reject enqueue (`{:error, :backpressure}`), or
  - drop oldest/newest.

### 2.2 OUT-driven writable scheduling

- Register `SRT_EPOLL_OUT` only for sockets with pending queue.
- Remove `OUT` when queue drains.
- Keep `IN|ERR` for connection lifecycle handling.

This prevents unnecessary wakeups and avoids busy loops.

### 2.3 API compatibility contract

Keep current API response style (`:ok | {:error, reason}`).

- `:ok` means "queued successfully" in async mode.
- Optional future events:
  - `{:srt_server_send_dropped, conn_id, reason}`
  - `{:srt_server_backpressure, conn_id, queue_depth}`

---

## Phase 3 — NIF/scheduler hygiene

### 3.1 NIF classification by blocking behavior

- Ensure blocking paths remain dirty IO.
- If enqueue path becomes strictly non-blocking, it may move to normal scheduler later (optional optimization, not day-1).

### 3.2 Allocation minimization on hot path

- Reduce per-send allocations/copies where safe.
- Consider pooled native buffers for send queues.

---

## Phase 4 — Listener receive/control stability (secondary but related)

### 4.1 Parameterize server read drain batch

- Current fixed receive drain (`max_read_per_cycle`) can be too low/high depending on workload.
- Make it configurable to reduce wakeup churn.

### 4.2 De-stall accept callback path

- Current accept decision wait can block callback path.
- Move decision handling off critical section where possible to avoid collateral impact on active flows.

---

## Phase 5 — Observability and tooling

### 5.1 Add listener send telemetry

Emit periodic metrics:

- queue depth per connection (bytes/messages)
- enqueue failures/backpressure counts
- bytes queued vs bytes sent
- sender wakeups and active OUT sockets

### 5.2 Add dedicated listener benchmark scripts

- Compare ex_libsrt listener vs `srt-live-transmit` baseline.
- Include multi-client fanout tests (1, 2, 5 clients).

---

## Phase 6 — Rollout strategy

### 6.1 Feature flags

- `EX_LIBSRT_SERVER_ASYNC_SEND=true|false`
- `EX_LIBSRT_SERVER_SNDSYN=false` (target default after validation)

### 6.2 Canary rollout

- Enable on one instance.
- Compare control vs canary for throughput, drops, retransmissions, scheduler health.

### 6.3 Gradual expansion

- 10% -> 50% -> 100% with monitored gates.

### 6.4 Fast rollback

- Keep sync send path behind flag until async path is proven stable.

---

## Recommended implementation order

1. `SNDSYN` + `SNDTIMEO` + option exposure
2. Send-path telemetry
3. Async per-connection queue + OUT-driven drain
4. Backpressure/error contract refinements
5. Accept callback de-stall refactor

This ordering delivers quick wins early and contains risk while moving to the high-impact architecture.
