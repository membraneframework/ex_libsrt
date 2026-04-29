# Migration Guide for release v0.2.0

v0.2.0 introduces a new API for starting server and handling connections.
Below there is a description of changes that need to be implemented while migrating
from v0.1.x.

## start() and start_link() signatures
`ExLibSRT.Server.start/3` and `start_link/3` signatures have changed.
`password` and `latency_ms` options now need to be provided as a keyword list elements.
Furthermore, a new option: `:accept_mode` was added - more information in [Connection handling](#connection-handling) section.

```diff
- {:ok, server} = ExLibSRT.Server.start("0.0.0.0", 12_000, "some_password", 1000)
+ {:ok, server} = ExLibSRT.Server.start("0.0.0.0", 12_000, accept_mode: :accept_all, password: "some_password", latency_ms: 1000)
```

## Connection handling

The `{:srt_server_conn, <connection ID>, <stream ID>}` message is sent to the server's "owner" process (which can be specified by the `:owner` option of `ExLibSRT.Server.start/3` and `ExLibSRT.Server.start_link/3` functions).
The old functions `ExLibSRT.Server.accept_awaiting_connect_request`, `ExLibSRT.Server.accept_awaiting_connect_request_with_handler` and `ExLibSRT.Server.reject_awaiting_connect_request` were removed since the connection
is now either always accepted (with `accept_mode: :accept_all`) or accepted or rejected based on the `stream_id` (with `accept_mode: :whitelist` and `accept_mode: {:whitelist, <initial_whitelist>}`).
After acceptance, the connection needs to be bound with a process or a handler module handling incoming data, which is done with `ExLibSRT.Server.bind_with_process/3` and `ExLibSRT.Server.bind_with_handler/3` functions.

```diff
- receive do
-   {:srt_server_connect_request, _addr, stream_id} ->
-     {:ok, _conn} = ExLibSRT.Server.accept_awaiting_connect_request(stream_id, server, receiver_pid)
- end

+ receive do
+   {:srt_server_conn, conn_id, _stream_id} ->
+     {:ok, _conn} = ExLibSRT.Server.bind_with_handler(%MyHandler{}, server, conn_id)
+ end
```

## ConnectionHandler callbacks changes

The `handle_connected/3` callback in `ExLibSRT.Connection.Handler` was removed since now the connection handler is bound to an already connected client connection.

```diff
  @impl true
- def handle_connected(conn_id, stream_id, state) do
-   {:ok, Map.put(state, :conn_id, conn_id)}
- end
-
  @impl true
  def handle_data(data, state) do
    ...
  end
```

## New: Rejection handling

The owner process of the server now gets notified when connection is rejected (which might happen only in the whitelist mode).

```diff
+ receive do
+   {:srt_server_rejected_client, stream_id} ->
+     Logger.warning("Rejected: #{stream_id}")
+ end
```
