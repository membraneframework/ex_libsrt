module ExLibSRT.Native

interface [NIF]

state_type "State"

type srt_socket_stats :: %ExLibSRT.SocketStats{
  msTimeStamp: int64,
  pktSentTotal: int64,
  pktRecvTotal: int64,
  pktSentUniqueTotal: int64,
  pktRecvUniqueTotal: int64,
  pktSndLossTotal: int,
  pktRcvLossTotal: int,
  pktRetransTotal: int,
  pktRcvRetransTotal: int,
  pktSentACKTotal: int,
  pktRecvACKTotal: int,
  pktSentNAKTotal: int,
  pktRecvNAKTotal: int,
  usSndDurationTotal: int64,
  pktSndDropTotal: int,
  pktRcvDropTotal: int,
  pktRcvUndecryptTotal: int,
  pktSndFilterExtraTotal: int,
  pktRcvFilterExtraTotal: int,
  pktRcvFilterSupplyTotal: int,
  pktRcvFilterLossTotal: int,
  byteSentTotal: uint64,
  byteRecvTotal: uint64,
  byteSentUniqueTotal: uint64,
  byteRecvUniqueTotal: uint64,
  byteRcvLossTotal: uint64,
  byteRetransTotal: uint64,
  byteSndDropTotal: uint64,
  byteRcvDropTotal: uint64,
  byteRcvUndecryptTotal: uint64,
  pktSent: int64,
  pktRecv: int64,
  pktSentUnique: int64,
  pktRecvUnique: int64,
  pktSndLoss: int,
  pktRcvLoss: int,
  pktRetrans: int,
  pktRcvRetrans: int,
  pktSentACK: int,
  pktRecvACK: int,
  pktSentNAK: int,
  pktRecvNAK: int,
  pktSndFilterExtra: int,
  pktRcvFilterExtra: int,
  pktRcvFilterSupply: int,
  pktRcvFilterLoss: int,
  mbpsSendRate: float,
  mbpsRecvRate: float,
  usSndDuration: int64,
  pktReorderDistance: int,
  pktRcvBelated: int64,
  pktSndDrop: int,
  pktRcvDrop: int,
}

callback :load, :on_load
callback :unload, :on_unload

spec start_server(host :: string, port :: int, password :: string) :: {:ok :: label, state} | {:error :: label, reason :: string}

spec start_server_with_latency(host :: string, port :: int, password :: string, latency_ms :: int) :: {:ok :: label, state} | {:error :: label, reason :: string}

spec accept_awaiting_connect_request(receiver :: pid, state) :: (:ok :: label) | {:error :: label, reason :: string}

spec reject_awaiting_connect_request(state) :: (:ok :: label) | {:error :: label, reason :: string}

spec read_server_socket_stats(conn_id :: int, state) :: {:ok :: label, stats :: srt_socket_stats} | {:error :: label, reason :: string}

spec close_server_connection(conn_id :: int, state) :: (:ok :: label) | {:error :: label, reason :: string}

spec stop_server(state) :: (:ok :: label) | {:error :: label, reason :: string}


spec start_client(server_address :: string, port :: int, stream_id :: string, password :: string) :: {:ok :: label, state} | {:error :: label, reason :: string, code :: int}

spec start_client_with_latency(server_address :: string, port :: int, stream_id :: string, password :: string, latency_ms :: int) :: {:ok :: label, state} | {:error :: label, reason :: string, code :: int}

spec send_client_data(data :: payload, state) :: (:ok :: label) | {:error :: label, reason :: string}

spec read_client_socket_stats(state) :: {:ok :: label, stats :: srt_socket_stats} | {:error :: label, reason :: string}

spec stop_client(state) :: (:ok :: label) | {:error :: label, reason :: string}

sends {:srt_server_conn :: label, conn :: int, stream_id :: string}
sends {:srt_server_conn_closed:: label, conn :: int}
sends {:srt_server_error :: label, conn :: int, error :: string}
sends {:srt_data :: label, conn :: int, data :: payload}
sends {:srt_server_connect_request :: label, address :: string, stream_id :: string}

sends :srt_client_connected :: label
sends :srt_client_disconnected :: label
sends {:srt_client_error :: label, reason :: string}

dirty :io,  start_server: 3, start_server_with_latency: 4, close_server_connection: 2, stop_server: 1, start_client: 4, start_client_with_latency: 5, read_server_socket_stats: 2, read_client_socket_stats: 1
