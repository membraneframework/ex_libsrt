defmodule ExLibSRT.Server do
  @moduledoc """
  Implementation of the SRT server.

  ## API
  The server API consists of the following functions:

  * `start/2` - starts the server
  * `start/6` - starts the server with password authentication, latency and stream ID whitelist
  * `start_link/2` - starts the server and links to current process
  * `start_link/6` - starts the server with password authentication, latency and stream ID whitelist, links to current process
  * `stop/1` - stops the server
  * `close_server_connection/2` - stops server's connection to given client
  * `add_stream_id_to_whitelist/3` - adds a stream ID to the server's whitelist at runtime
  * `remove_stream_id_from_whitelist/2` - removes a stream ID from the server's whitelist at runtime
  * `bind_with_process/2,3` - registers a process as the receiver for a pending connection
  * `bind_with_handler/3` - spawns a `ExLibSRT.Connection` process and binds it to a pending connection

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

  ### Accepting connections — whitelist mode
  Each SRT connection can carry a `streamid` string which can be used for identifying the stream.
  When `allowed_stream_ids` is non-empty the server operates in **whitelist
  mode**: only connections whose `streamid` is present in the whitelist are accepted. For each
  whitelisted stream ID a receiver process must be provided — this is the process that will
  receive `t:srt_server_conn/0`, `t:srt_data/0`, and `t:srt_server_conn_closed/0` messages for
  that stream.

  The whitelist can be supplied up-front via the `allowed_stream_ids` argument
  of `start/6` / `start_link/6`, and modified at runtime with `add_stream_id_to_whitelist/3` and
  `remove_stream_id_from_whitelist/2`.

  When a client connects with a stream ID that is not on the whitelist, the server responds with
  rejection code `1403` (analogous to HTTP 403 Forbidden).

  ### Accepting connections — accept-all mode
  When `allowed_stream_ids` is `nil` (the default) the server operates in **accept-all mode**:
  every incoming connection is accepted at the SRT level regardless of its stream ID.

  In both modes the owner process receives a `t:srt_server_conn/0` message for each accepted
  connection. The owner then has **1 second** to call `bind_with_process/3` or
  `bind_with_handler/3` to register a receiver for that connection. If no binding happens within
  1 second the connection is dropped.

  The registered receiver will receive `t:srt_data/0` and `t:srt_server_conn_closed/0` messages.
  When using `bind_with_handler`, the spawned `ExLibSRT.Connection` process also receives
  `t:srt_server_conn/0` to trigger `c:ExLibSRT.Connection.Handler.handle_connected/3`.
  """

  use Agent

  @type t :: pid()

  @type connection_id :: non_neg_integer()

  @type srt_server_conn :: {:srt_server_conn, connection_id(), stream_id :: String.t()}
  @type srt_server_conn_closed :: {:srt_server_conn_closed, connection_id()}
  @type srt_server_error :: {:srt_server_error, connection_id(), error :: String.t()}
  @type srt_data :: {:srt_data, connection_id(), data :: binary()}

  @doc """
  Starts a new SRT server binding to given address and port and links to current process.

  One may usually want to bind to `0.0.0.0` address.

  ## Password Requirements

  If a password is provided, it must be between 10 and 79 characters long according to SRT specification.
  An empty string means no password authentication will be used.

  ## Stream ID Whitelist

  `allowed_stream_ids` is a list of stream ID strings that pre-populate the server's whitelist.
  Each connecting client must present a `streamid` matching one of the listed IDs, otherwise it
  is rejected with code `1403`. The whitelist can also be modified at runtime with
  `add_stream_id_to_whitelist/2` and `remove_stream_id_from_whitelist/2`.

  ## Owner

  `owner` is the process that receives `t:srt_server_conn/0` notifications for every accepted
  connection, as well as `{:srt_server_rejected_client, stream_id}` when a connection is rejected.
  Defaults to `self()`.
  """
  @spec start_link(
          address :: String.t(),
          port :: non_neg_integer(),
          password :: String.t(),
          latency_ms :: integer(),
          allowed_stream_ids :: [String.t()] | nil,
          owner :: pid() | nil
        ) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start_link(
        address,
        port,
        password \\ "",
        latency_ms \\ -1,
        allowed_stream_ids \\ nil,
        owner \\ nil
      ) do
    owner = owner || self()

    with :ok <- validate_password(password),
         {:ok, server_ref} <-
           ExLibSRT.Native.start_server(
             address,
             port,
             password,
             latency_ms,
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

  ## Password Requirements

  If a password is provided, it must be between 10 and 79 characters long according to SRT specification.
  An empty string means no password authentication will be used.

  ## Stream ID Whitelist

  `allowed_stream_ids` is a list of stream ID strings that pre-populate the server's whitelist.
  Each connecting client must present a `streamid` matching one of the listed IDs, otherwise it
  is rejected with code `1403`. The whitelist can also be modified at runtime with
  `add_stream_id_to_whitelist/2` and `remove_stream_id_from_whitelist/2`.

  ## Owner

  `owner` is the process that receives `t:srt_server_conn/0` notifications for every accepted
  connection, as well as `{:srt_server_rejected_client, stream_id}` when a connection is rejected.
  Defaults to `self()`.
  """
  @spec start(address :: String.t(), port :: non_neg_integer()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  @spec start(
          address :: String.t(),
          port :: non_neg_integer(),
          password :: String.t(),
          latency_ms :: integer(),
          allowed_stream_ids :: [String.t()] | nil,
          owner :: pid() | nil
        ) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start(
        address,
        port,
        password \\ "",
        latency_ms \\ -1,
        allowed_stream_ids \\ nil,
        owner \\ nil
      ) do
    owner = owner || self()

    with :ok <- validate_password(password),
         {:ok, server_ref} <-
           ExLibSRT.Native.start_server(
             address,
             port,
             password,
             latency_ms,
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
    if Process.alive?(agent) do
      server_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.add_stream_id_to_whitelist(stream_id, server_ref)
    else
      {:error, "Server is not active"}
    end
  end

  @doc """
  Removes a stream ID from the server's whitelist at runtime.

  After removal, new connections carrying that stream ID will be rejected.
  """
  @spec remove_stream_id_from_whitelist(t(), String.t()) :: :ok | {:error, reason :: String.t()}
  def remove_stream_id_from_whitelist(agent, stream_id) do
    if Process.alive?(agent) do
      server_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.remove_stream_id_from_whitelist(stream_id, server_ref)
    else
      {:error, "Server is not active"}
    end
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

    if Process.alive?(agent) do
      server_ref = Agent.get(agent, & &1)

      case ExLibSRT.Native.bind_with_process(conn_id, receiver, server_ref) do
        {:ok, _stream_id} -> :ok
        error -> error
      end
    else
      {:error, "Server is not active"}
    end
  end

  @doc """
  Spawns an `ExLibSRT.Connection` process backed by `handler` and binds it to a pending
  connection.

  Must be called within 1 second of receiving `t:srt_server_conn/0`. The spawned process
  receives `t:srt_server_conn/0` to trigger `c:ExLibSRT.Connection.Handler.handle_connected/3`,
  then `t:srt_data/0` and `t:srt_server_conn_closed/0` for the lifetime of the connection.
  Returns `{:ok, connection_pid}` on success or `{:error, reason}` if the connection ID is not
  found or the handler fails to start.
  """
  @spec bind_with_handler(ExLibSRT.Connection.Handler.t(), t(), connection_id()) ::
          {:ok, ExLibSRT.Connection.t()} | {:error, reason :: any()}
  def bind_with_handler(handler, agent, conn_id) do
    with true <- Process.alive?(agent),
         server_ref = Agent.get(agent, & &1),
         {:ok, conn_process} <- ExLibSRT.Connection.start(handler),
         {:ok, stream_id} <- ExLibSRT.Native.bind_with_process(conn_id, conn_process, server_ref) do
      send(conn_process, {:srt_server_conn, conn_id, stream_id})
      {:ok, conn_process}
    else
      false ->
        {:error, "Server is not active"}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Closes the connection to the given client.
  """
  @spec close_server_connection(connection_id(), t()) :: :ok | {:error, reason :: String.t()}
  def close_server_connection(connection_id, agent) do
    if Process.alive?(agent) do
      server_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.close_server_connection(connection_id, server_ref)
    else
      {:error, "Server is not active"}
    end
  end

  @doc """
  Reads socket statistics.
  """
  @spec read_socket_stats(connection_id(), t()) ::
          {:ok, ExLibSRT.SocketStats.t()} | {:error, reason :: String.t()}
  def read_socket_stats(connection_id, agent) do
    if Process.alive?(agent) do
      server_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.read_server_socket_stats(connection_id, server_ref)
    else
      {:error, "Server is not active"}
    end
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
