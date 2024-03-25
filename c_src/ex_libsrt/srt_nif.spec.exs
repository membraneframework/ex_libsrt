module ExLibSRT

interface [NIF]

state_type "State"

callback :load, :on_load
callback :unload, :on_unload

spec start_server(host :: string, port :: int) :: {:ok :: label, state} | {:error :: label, reason :: string}

spec close_server_connection(conn_id :: int, state) :: (:ok :: label)

spec stop_server(state) :: (:ok :: label)

# spec start_client(server_address :: string, port :: int) :: {:ok :: label, state} | {:error :: label, reason :: string}

# spec send_client_data(data :: payload, state) :: (:ok :: label) | {:error :: label, reason :: string}

# spec stop_client(state) :: {:ok :: label}

# spec start_client(host :: string, port :: int, stream_id :: string) :: {:ok :: label, state} | {:error :: label, reason :: string}

# sends {:client_connected :: label, streamid :: string, conn :: int}
sends {:srt_client_connected :: label, conn :: int}
sends {:srt_client_disconnected:: label, conn :: int}
sends {:srt_connection_error :: label, conn :: int, error :: string}
sends {:srt_data :: label, conn :: int, data :: payload}
