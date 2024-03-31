module ExLibSRT.Native

interface [NIF]

state_type "State"

callback :load, :on_load
callback :unload, :on_unload

spec start_server(host :: string, port :: int) :: {:ok :: label, state} | {:error :: label, reason :: string}

spec accept_awaiting_connect_request(state) :: (:ok :: label) | {:error :: label, reason :: string}

spec reject_awaiting_connect_request(state) :: (:ok :: label) | {:error :: label, reason :: string}

spec close_server_connection(conn_id :: int, state) :: (:ok :: label) | {:error :: label, reason :: string}

spec stop_server(state) :: (:ok :: label) | {:error :: label, reason :: string}

spec start_client(server_address :: string, port :: int, stream_id :: string) :: {:ok :: label, state} | {:error :: label, reason :: string, code :: int}

spec send_client_data(data :: payload, state) :: (:ok :: label) | {:error :: label, reason :: string}

spec stop_client(state) :: (:ok :: label) | {:error :: label, reason :: string}

sends {:srt_server_conn :: label, conn :: int, stream_id :: string}
sends {:srt_server_conn_closed:: label, conn :: int}
sends {:srt_server_error :: label, conn :: int, error :: string}
sends {:srt_data :: label, conn :: int, data :: payload}
sends {:srt_server_connect_request :: label, address :: string, stream_id :: string}

sends :srt_client_connected :: label
sends :srt_client_disconnected :: label
sends {:srt_client_error :: label, reason :: string}

dirty :io,  start_server: 2, close_server_connection: 2, stop_server: 1, start_client: 3
