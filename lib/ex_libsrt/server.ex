defmodule ExLibSRT.Server do
  @moduledoc """
  Implementation of the SRT server.

  ## API
  The client API consinsts of the following functions:

  * `start/2` - starts the server
  * `start/3` - starts the server with password authentication
  * `start_link/2` - starts the server and links to current process
  * `start_link/3` - starts the server with password authentication and links to current process
  * `start_link/4` - starts the server with password authentication, sets SRT latency and links to current process
  * `stop/1` - stops the server
  * `close_server_connection/2` - stops server's connection to given client

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

  When user rejects the stream, the server respons with `1403` rejection code (SRT wise). While not being to accept in time
  results in `1504` (not that the codes respectively are the same of HTTP 403 forbidden and 504 gateway timeout).

  > #### Response timeout {: .warning}
  >
  > It is very important to answer the connection request as fast as possible.
  > Due to how `libsrt` works, while the server waits for the response it blocks the receiving thread
  > and potentially interrupts other ongoing connections.
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
          allowed_stream_id_with_receiver_list :: [String.t()]
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

  @spec add_stream_id_to_whitelist(t(), String.t()) :: :ok | {:error, reason :: String.t()}
  def add_stream_id_to_whitelist(agent, stream_id, receiver \\ nil) do
    receiver = receiver || self()

    if Process.alive?(agent) do
      server_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.add_stream_id_to_whitelist(stream_id, receiver, server_ref)
    else
      {:error, "Server is not active"}
    end
  end

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
