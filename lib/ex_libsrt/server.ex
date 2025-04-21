defmodule ExLibSRT.Server do
  @moduledoc """
  Implementation of the SRT server.

  ## API
  The client API consinsts of the following functions:

  * `start/2` - starts the server
  * `stop/1` - stops the server
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

  @type t :: reference()

  @type connection_id :: non_neg_integer()

  @type srt_server_conn :: {:srt_server_conn, connection_id(), stream_id :: String.t()}
  @type srt_server_conn_closed :: {:srt_server_conn_closed, connection_id()}
  @type srt_server_error :: {:srt_server_error, connection_id(), error :: String.t()}
  @type srt_data :: {:srt_data, connection_id(), data :: binary()}
  @type srt_server_connect_request ::
          {:srt_server_connect_request, address :: String.t(), stream_id :: String.t()}

  @doc """
  Starts a new SRT server binding to given address and port.

  One may usually want to bind to `0.0.0.0` address.
  """
  @spec start(address :: String.t(), port :: non_neg_integer()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start(address, port) do
    ExLibSRT.Native.create_server(address, port)
  end

  @doc """
  Stops the server.

  Stopping a server should gracefuly close all the client connections.
  """
  @spec stop(t()) :: :ok
  def stop(server) do
    ExLibSRT.Native.stop_server(server)
  end

  @doc """
  Acccepts the currently awaiting connection request.
  """
  @spec accept_awaiting_connect_request(t()) :: :ok | {:error, reason :: String.t()}
  def accept_awaiting_connect_request(server),
    do: ExLibSRT.Native.accept_awaiting_connect_request(self(), server)

  @doc """
  Acccepts the currently awaiting connection request and starts a separate connection process
  """
  @spec accept_awaiting_connect_request_with_handler(ExLibSRT.Connection.Handler.t(), t()) ::
          {:ok, ExLibSRT.Connection.t()} | {:error, reason :: any()}
  def accept_awaiting_connect_request_with_handler(handler, server) do
    with {:ok, handler} <- ExLibSRT.Connection.start(handler) do
      case ExLibSRT.Native.accept_awaiting_connect_request(handler, server) do
        :ok ->
          {:ok, handler}

        {:error, _reason} = error ->
          ExLibSRT.Connection.stop(handler)

          error
      end
    end
  end

  @doc """
  Rejects the currently awaiting connection request.
  """
  @spec reject_awaiting_connect_request(t()) :: :ok | {:error, reason :: String.t()}
  def reject_awaiting_connect_request(server),
    do: ExLibSRT.Native.reject_awaiting_connect_request(server)

  @doc """
  Closes the connection to the given client.
  """
  @spec close_server_connection(connection_id(), t()) :: :ok | {:error, reason :: String.t()}
  def close_server_connection(connection_id, server),
    do: ExLibSRT.Native.close_server_connection(connection_id, server)

  @doc """
  Reads socket statistics.
  """
  @spec read_socket_stats(connection_id(), t()) ::
          {:ok, ExLibSRT.SocketStats.t()} | {:error, reason :: String.t()}
  def read_socket_stats(connection_id, server),
    do: ExLibSRT.Native.read_server_socket_stats(connection_id, server)
end
