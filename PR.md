# Add missing data-path support for caller-side ingest (server send + client receive)

## Problem

`ex_libsrt` was missing two capabilities needed by downstream caller-side ingest workflows:

1. Server could accept/receive, but had no API to send payloads back through an active connection.
2. Client startup was effectively sender-only in public usage, so caller-mode ingest could connect but not receive media.

## Changes

### 1) Server-side send support

- Native API: `ExLibSRT.Native.send_server_data(conn_id, payload, server_ref)`
- Public API: `ExLibSRT.Server.send_data(connection_id, payload, server_pid)`

Behavior:
- validates active server and connection
- sends via `srt_sendmsg`
- returns `:ok | {:error, reason}`
- enforces max payload size (`1316`) in `Server.send_data/3`

### 2) Receiver-mode client data path

- client mode controls `SRTO_SENDER`
- receiver mode enables `SRT_EPOLL_IN`
- receiver mode reads with `srt_recv`
- emits `{:srt_data, 0, payload}`
- `send_client_data/2` returns `{:error, "Client is not in sender mode"}` in receiver mode

### 3) Public API shape (developer-facing)

- public mode is atom-based: `:sender | :receiver`
- public entrypoints:
  - `ExLibSRT.Native.start_client/5` (default sender)
  - `ExLibSRT.Native.start_client/6` (explicit mode)
  - `ExLibSRT.Client.start/4` and `start_link/4` with options (`mode`, `password`, `latency_ms`)
- integer flag is internal-only via native entrypoint `start_client_native/6`
- `start_client_with_mode/6` is not exposed publicly

## Compatibility

- sender remains the default
- existing positional `Client.start/...` and `start_link/...` calls still work
- no expected break for published users

## Tests

- server send path tests (`Server.send_data/3`, payload size)
- coop test verifies receiver-mode client receives server payload
- receiver-mode send rejection verified
- options validation tests added
- full suite passes: `mix test`

## Recommended version bump

**Minor** (`0.1.6 -> 0.2.0`).

Reason: this PR adds new public capabilities/API surface while keeping published behavior backward compatible.
