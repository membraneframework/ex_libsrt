defmodule ExLibSRT.Server do
  @moduledoc """
  Implementation of the SRT server.

  ## API
  The server API consists of the following functions:

  * `start/2` - starts the server
  * `start/5` - starts the server with password authentication, latency and stream ID whitelist
  * `start_link/2` - starts the server and links to current process
  * `start_link/5` - starts the server with password authentication, latency and stream ID whitelist, links to current process
  * `stop/1` - stops the server
  * `close_server_connection/2` - stops server's connection to given client
  * `add_stream_id_to_whitelist/3` - adds a stream ID to the server's whitelist at runtime
  * `remove_stream_id_from_whitelist/2` - removes a stream ID from the server's whitelist at runtime

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

  ### Accepting connections
  Each SRT connection can carry a `streamid` string which can be used for identifying the stream.
  The server only accepts connections whose `streamid` is present in the whitelist. For each
  whitelisted stream ID a receiver process must be provided — this is the process that will
  receive `t:srt_server_conn/0`, `t:srt_data/0`, and `t:srt_server_conn_closed/0` messages for
  that stream.

  The whitelist can be supplied up-front via the `allowed_stream_id_with_receiver_list` argument
  of `start/5` / `start_link/5`, and modified at runtime with `add_stream_id_to_whitelist/3` and
  `remove_stream_id_from_whitelist/2`.

  When a client connects with a stream ID that is not on the whitelist, the server responds with
  rejection code `1403` (analogous to HTTP 403 Forbidden).
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
  """
  @spec start_link(
          address :: String.t(),
          port :: non_neg_integer(),
          password :: String.t(),
          latency_ms :: integer(),
          allowed_stream_id_with_receiver_list :: [{String.t(), pid()}]
        ) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start_link(
        address,
        port,
        password \\ "",
        latency_ms \\ -1,
        allowed_stream_id_with_receiver_list \\ []
      ) do
    {stream_ids_whitelist, receivers} = Enum.unzip(allowed_stream_id_with_receiver_list)

    with :ok <- validate_password(password),
         {:ok, server_ref} <-
           ExLibSRT.Native.start_server(
             address,
             port,
             password,
             latency_ms,
             stream_ids_whitelist,
             receivers
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
  """
  @spec start(address :: String.t(), port :: non_neg_integer()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  @spec start(
          address :: String.t(),
          port :: non_neg_integer(),
          password :: String.t(),
          latency_ms :: integer(),
          allowed_stream_id_with_receiver_list :: [{String.t(), pid()}]
        ) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start(
        address,
        port,
        password \\ "",
        latency_ms \\ -1,
        allowed_stream_id_with_receiver_list \\ []
      ) do
    {stream_ids_whitelist, receivers} = Enum.unzip(allowed_stream_id_with_receiver_list)

    with :ok <- validate_password(password),
         {:ok, server_ref} <-
           ExLibSRT.Native.start_server(
             address,
             port,
             password,
             latency_ms,
             stream_ids_whitelist,
             receivers
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

  The `receiver` process will receive connection and data messages for this stream ID.
  Defaults to `self()` when not provided.
  """
  @spec add_stream_id_to_whitelist(t(), String.t(), pid() | nil) ::
          :ok | {:error, reason :: String.t()}
  def add_stream_id_to_whitelist(agent, stream_id, receiver \\ nil) do
    receiver = receiver || self()

    if Process.alive?(agent) do
      server_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.add_stream_id_to_whitelist(stream_id, receiver, server_ref)
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
