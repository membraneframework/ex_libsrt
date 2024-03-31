defmodule ExLibSRT do
  @moduledoc """
  Bindings to [libsrt](https://github.com/Haivision/srt) library.

  This package contains well defined abstractions of SRT entities, consisting of a server and a client.

  > #### Compability {: .info}
  >
  > The current implementation is very limited and only uses the livestreaming configuration, with only one way
  > capability of sending media.

  ## Client
  The client API consinsts of the following functions:

  * `start_client/3` - starts a client connection to the server
  * `stop_client/1` - stops the client connection
  * `send_client_data/2` - sencds a packet through the client connection

  A process starting the client will also receive the following notifications:
  * `t:srt_client_started/0`
  * `t:srt_client_disconnected/0`
  * `t:srt_client_error/0`

  ## Server
  The client API consinsts of the following functions:

  * `start_server/2` - starts the server
  * `stop_server/1` - stops the server
  * `accept_awaiting_connect_request/1` - accepts next incoming connection
  * `reject_awaiting_connect_request/1` - rejects next incoming connection
  * `close_server_connection/2` - stops server's connection to given client


  A process starting the server will also receive the following notifications:
  * `t:srt_server_conn/0` - a new client connection has been established
  * `t:srt_server_conn_closed/0` - a client connection has been closed
  * `t:srt_server_error/0` - server has encountered an error
  * `t:srt_data/0` - server has received new data on a client connection
  * `t:srt_server_connect_request/0` - server has triggered a new connection request 
    (see `accept_awaiting_connect_request/1` and `reject_awaiting_connect_request/1` for answering the request)

  ### Accepting connections
  Each SRT connection can carry a `streamid` string which can be used for identifying the stream.

  To support accepting/rejecting the connection a server sends `t:srt_server_connect_request/0` event.
  THe process that started the server is then obliged to either call  `accept_awaiting_connect_request/1` or `reject_awaiting_connect_request/1`.
  Not responding in time will result in server's rejecting the connection.

  When user rejects the stream, the server respons with `1403` rejection code (SRT wise). While not being to accept in time
  results in `1504` (not that the codes respectively are the same of HTTP 403 forbidden and 504 gateway timeout).

  > #### Response timeout {: .warning}
  >
  > It is very important to answer the connection request as fast as possible.
  > Due to how `libsrt` works, while the server waits for the response it blocks the receiving thread 
  > and potentially interrupts other ongoing connections.
  """

  @type client :: reference()
  @type server :: reference()

  @type connection_id :: non_neg_integer()

  @type srt_client_started :: :srt_client_started
  @type srt_client_disconnected :: :srt_client_started
  @type srt_client_error :: {:srt_client_error, reason :: String.t()}

  @type srt_server_conn :: {:srt_server_conn, connection_id(), stream_id :: String.t()}
  @type srt_server_conn_closed :: {:srt_server_conn_closed, connection_id()}
  @type srt_server_error :: {:srt_server_error, connection_id(), error :: String.t()}
  @type srt_data :: {:srt_data, connection_id(), data :: binary()}
  @type srt_server_connect_request ::
          {:srt_server_connect_request, address :: String.t(), stream_id :: String.t()}

  @doc """
  Starts a new SRT connection to the target address and port.
  """
  @spec start_client(address :: String.t(), port :: non_neg_integer(), stream_id :: String.t()) ::
          {:ok, client()} | {:error, reason :: String.t(), error_code :: integer()}
  defdelegate start_client(address, port, stream_id), to: ExLibSRT.Native

  @doc """
  Stops the active client connection.
  """
  @spec stop_client(client()) :: :ok
  defdelegate stop_client(client), to: ExLibSRT.Native

  @doc """
  Sends data through the client connection.
  """
  @spec send_client_data(binary(), client()) :: :ok | {:error, reason :: String.t()}
  defdelegate send_client_data(payload, client), to: ExLibSRT.Native

  @doc """
  Starts a new SRT server binding to given address and port.

  One may usually want to bind to `0.0.0.0` address.
  """
  @spec start_server(address :: String.t(), port :: non_neg_integer()) ::
          {:ok, client()} | {:error, reason :: String.t(), error_code :: integer()}
  defdelegate start_server(address, port), to: ExLibSRT.Native

  @doc """
  Stops the server.

  Stopping a server should gracefuly close all the client connections.
  """
  @spec stop_server(server()) :: :ok
  defdelegate stop_server(server), to: ExLibSRT.Native

  @doc """
  Acccepts the currently awaiting connection request.
  """
  @spec accept_awaiting_connect_request(client()) :: :ok | {:error, reason :: String.t()}
  defdelegate accept_awaiting_connect_request(server), to: ExLibSRT.Native

  @doc """
  Rejects the currently awaiting connection request.
  """
  @spec reject_awaiting_connect_request(client()) :: :ok | {:error, reason :: String.t()}
  defdelegate reject_awaiting_connect_request(server), to: ExLibSRT.Native

  @doc """
  Closes the connection to the given client.
  """
  @spec close_server_connection(connection_id(), client()) :: :ok | {:error, reason :: String.t()}
  defdelegate close_server_connection(connection_id, server), to: ExLibSRT.Native
end
