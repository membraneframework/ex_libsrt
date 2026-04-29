defmodule ExLibSRT.Server do
  @moduledoc """
  Implementation of the SRT server.

  ## Accepting connections — whitelist mode
  Each SRT connection can carry a `streamid` string which can be used for identifying the stream.
  When `accept_mode: :whitelist` or `accept_mode: {:whitelist, ids}` the server operates in
  **whitelist mode**: only connections whose `streamid` is present in the whitelist are accepted.
  For each whitelisted stream ID a receiver process must be provided — this is the process that will
  receive `t:srt_server_conn/0`, `t:srt_data/0`, and `t:srt_server_conn_closed/0` messages for
  that stream.

  The whitelist can be supplied up-front via the `:accept_mode` option of `start/3` / `start_link/3`
  (e.g., `accept_mode: {:whitelist, stream_ids}`), and modified at runtime with
  `add_stream_id_to_whitelist/2` and `remove_stream_id_from_whitelist/2`.

  When a client connects with a stream ID that is not on the whitelist, the server responds with
  rejection code `1403` (analogous to HTTP 403 Forbidden).

  ## Accepting connections — accept-all mode
  When `accept_mode: :accept_all` the server operates in **accept-all mode**:
  every incoming connection is accepted at the SRT level regardless of its stream ID.

  In both modes the owner process receives a `t:srt_server_conn/0` message for each accepted
  connection. The owner then has **1 second** to call `bind_with_process/3` or
  `bind_with_handler/3` to register a receiver for that connection. If no binding happens within
  1 second the connection is dropped.

  The registered receiver will receive `t:srt_data/0` and `t:srt_server_conn_closed/0` messages.

  If the owner does not call `bind_with_process/3` or `bind_with_handler/3` within 1 second,
  the connection is dropped and the owner receives `t:srt_server_conn_timeout/0`.

  ## Password Authentication

  SRT supports password-based authentication. When using password authentication:
  - Password must be between 10 and 79 characters long (SRT specification requirement)
  - Empty string means no password authentication (default behavior)
  - All connecting clients must provide the same password

  A process starting the server will also receive the following notifications:
  * `t:srt_server_conn/0` - a new client connection has been established
  * `t:srt_server_conn_closed/0` - a client connection has been closed
  * `t:srt_server_error/0` - server has encountered an error
  * `t:srt_data/0` - server has received new data on a client connection
  """

  use Agent

  @type t :: pid()

  @type connection_id :: non_neg_integer()

  @type accept_mode :: :accept_all | :whitelist | {:whitelist, [String.t()]}

  @type srt_server_conn :: {:srt_server_conn, connection_id(), stream_id :: String.t()}
  @type srt_server_conn_closed :: {:srt_server_conn_closed, connection_id()}
  @type srt_server_error :: {:srt_server_error, connection_id(), error :: String.t()}
  @type srt_data :: {:srt_data, connection_id(), data :: binary()}
  @type srt_server_conn_timeout ::
          {:srt_server_conn_timeout, connection_id(), stream_id :: String.t()}

  @doc """
  Starts a new SRT server binding to given address and port and links to current process.

  One may usually want to bind to `0.0.0.0` address.

  ## Options

  * `:password` - SRT passphrase for authentication. Must be between 10 and 79 characters long
    according to SRT specification. Empty string (default) means no password authentication.
  * `:latency_ms` - SRT latency in milliseconds. Defaults to `-1`.
  * `:accept_mode` - Controls how the server accepts connections. Valid values are:
    * `:accept_all` - Accept all connections regardless of stream ID.
    * `:whitelist` - Whitelist mode with an empty initial whitelist.
    * `{:whitelist, stream_ids}` - Whitelist mode with pre-populated stream IDs.
    Defaults to `:whitelist`. In whitelist mode, the whitelist can be modified at runtime with
    `add_stream_id_to_whitelist/2` and `remove_stream_id_from_whitelist/2`.
  * `:owner` - The process that receives `t:srt_server_conn/0` notifications for every accepted
    connection, as well as `{:srt_server_rejected_client, stream_id}` when a connection is rejected.
    Defaults to `self()`.
  """
  @spec start_link(
          address :: String.t(),
          port :: non_neg_integer(),
          opts :: keyword()
        ) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start_link(address, port, opts \\ []) do
    password = Keyword.get(opts, :password, "")
    latency_ms = Keyword.get(opts, :latency_ms, -1)
    accept_mode = Keyword.get(opts, :accept_mode, :whitelist)
    owner = Keyword.get(opts, :owner) || self()

    {accept_all, allowed_stream_ids} =
      case accept_mode do
        :accept_all -> {true, []}
        :whitelist -> {false, []}
        {:whitelist, ids} -> {false, ids}
      end

    with :ok <- validate_password(password),
         {:ok, server_ref} <-
           ExLibSRT.Native.start_server(
             address,
             port,
             password,
             latency_ms,
             accept_all,
             allowed_stream_ids || [],
             owner
           ) do
      Agent.start_link(fn -> server_ref end)
    else
      {:error, reason, error_code} -> {:error, reason, error_code}
      {:error, reason} -> {:error, reason, 0}
    end
  end

  @doc """
  Starts a new SRT server outside the supervision tree, binding to given address and port.

  One may usually want to bind to `0.0.0.0` address.

  ## Options

  * `:password` - SRT passphrase for authentication. Must be between 10 and 79 characters long
    according to SRT specification. Empty string (default) means no password authentication.
  * `:latency_ms` - SRT latency in milliseconds. Defaults to `-1`.
  * `:accept_mode` - Controls how the server accepts connections. Valid values are:
    * `:accept_all` - Accept all connections regardless of stream ID.
    * `:whitelist` - Whitelist mode with an empty initial whitelist.
    * `{:whitelist, stream_ids}` - Whitelist mode with pre-populated stream IDs.
    Defaults to `:whitelist`. In whitelist mode, the whitelist can be modified at runtime with
    `add_stream_id_to_whitelist/2` and `remove_stream_id_from_whitelist/2`.
  * `:owner` - The process that receives `t:srt_server_conn/0` notifications for every accepted
    connection, as well as `{:srt_server_rejected_client, stream_id}` when a connection is rejected.
    Defaults to `self()`.
  """
  @spec start(
          address :: String.t(),
          port :: non_neg_integer(),
          opts :: keyword()
        ) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start(address, port, opts \\ []) do
    password = Keyword.get(opts, :password, "")
    latency_ms = Keyword.get(opts, :latency_ms, -1)
    accept_mode = Keyword.get(opts, :accept_mode, :whitelist)
    owner = Keyword.get(opts, :owner) || self()

    {accept_all, allowed_stream_ids} =
      case accept_mode do
        :accept_all -> {true, []}
        :whitelist -> {false, []}
        {:whitelist, ids} -> {false, ids}
      end

    with :ok <- validate_password(password),
         {:ok, server_ref} <-
           ExLibSRT.Native.start_server(
             address,
             port,
             password,
             latency_ms,
             accept_all,
             allowed_stream_ids || [],
             owner
           ) do
      Agent.start(fn -> server_ref end, name: {:global, server_ref})
    else
      {:error, reason, error_code} -> {:error, reason, error_code}
      {:error, reason} -> {:error, reason, 0}
    end
  end

  @doc """
  Stops the server.

  Stopping a server closes all active connections.
  """
  @spec stop(t()) :: :ok | {:error, reason :: String.t()}
  def stop(agent) do
    server_ref = Agent.get(agent, & &1)
    result = ExLibSRT.Native.stop_server(server_ref)
    Agent.stop(agent)
    result
  end

  @doc """
  Adds a stream ID to the server's whitelist at runtime.

  Once added, connections carrying this stream ID will be accepted and the owner will receive
  `t:srt_server_conn/0`. Call `bind_with_process/3` or `bind_with_handler/3` to register
  a receiver.
  """
  @spec add_stream_id_to_whitelist(t(), String.t()) :: :ok | {:error, reason :: String.t()}
  def add_stream_id_to_whitelist(agent, stream_id) do
    server_ref = Agent.get(agent, & &1)
    ExLibSRT.Native.add_stream_id_to_whitelist(stream_id, server_ref)
  end

  @doc """
  Removes a stream ID from the server's whitelist at runtime.

  After removal, new connections carrying that stream ID will be rejected.
  """
  @spec remove_stream_id_from_whitelist(t(), String.t()) :: :ok | {:error, reason :: String.t()}
  def remove_stream_id_from_whitelist(agent, stream_id) do
    server_ref = Agent.get(agent, & &1)
    ExLibSRT.Native.remove_stream_id_from_whitelist(stream_id, server_ref)
  end

  @doc """
  Registers the given process (defaults to `self()`) as the receiver for a pending connection.

  Must be called within 1 second of receiving `t:srt_server_conn/0`, otherwise the connection
  will have been dropped. Returns `{:error, reason}` if the connection ID is not found.

  After a successful bind the receiver will receive `t:srt_data/0` and
  `t:srt_server_conn_closed/0` messages for the connection.
  """
  @spec bind_with_process(t(), connection_id(), pid() | nil) ::
          :ok | {:error, reason :: String.t()}
  def bind_with_process(agent, conn_id, receiver \\ nil) do
    receiver = receiver || self()

    server_ref = Agent.get(agent, & &1)

    case ExLibSRT.Native.bind_with_process(conn_id, receiver, server_ref) do
      {:ok, _stream_id} -> :ok
      error -> error
    end
  end

  @doc """
  Spawns an `ExLibSRT.Connection` process backed by `handler` and binds it to a pending
  connection.

  Must be called within 1 second of receiving `t:srt_server_conn/0`.
  """
  @spec bind_with_handler(t(), connection_id(), ExLibSRT.Connection.Handler.t()) ::
          {:ok, ExLibSRT.Connection.t()} | {:error, reason :: any()}
  def bind_with_handler(agent, conn_id, handler) do
    with server_ref = Agent.get(agent, & &1),
         {:ok, conn_process} <- ExLibSRT.Connection.start(handler),
         {:ok, _stream_id} <- ExLibSRT.Native.bind_with_process(conn_id, conn_process, server_ref) do
      {:ok, conn_process}
    else
      {:error, _reason} = error ->
        error
    end
  end

  @spec accept_awaiting_connect_request_with_handler(ExLibSRT.Connection.Handler.t(), t()) ::
          {:ok, ExLibSRT.Connection.t()} | {:error, reason :: any()}
  def accept_awaiting_connect_request_with_handler(handler, agent),
    do: bind_with_handler(agent, handler)

  @doc """
  Closes the connection to the given client.
  """
  @spec close_server_connection(connection_id(), t()) :: :ok | {:error, reason :: String.t()}
  def close_server_connection(connection_id, agent) do
    server_ref = Agent.get(agent, & &1)
    ExLibSRT.Native.close_server_connection(connection_id, server_ref)
  end

  @doc """
  Reads socket statistics.
  """
  @spec read_socket_stats(connection_id(), t()) ::
          {:ok, ExLibSRT.SocketStats.t()} | {:error, reason :: String.t()}
  def read_socket_stats(connection_id, agent) do
    server_ref = Agent.get(agent, & &1)
    ExLibSRT.Native.read_server_socket_stats(connection_id, server_ref)
  end

  # Private functions

  @spec validate_password(String.t()) :: :ok | {:error, String.t()}
  defp validate_password(""), do: :ok

  defp validate_password(password) when is_binary(password) do
    password_length = String.length(password)

    cond do
      password_length < 10 ->
        {:error, "SRT password must be at least 10 characters long"}

      password_length > 79 ->
        {:error, "SRT password must be at most 79 characters long"}

      true ->
        :ok
    end
  end

  defp validate_password(_password), do: {:error, "Password must be a string"}
end
