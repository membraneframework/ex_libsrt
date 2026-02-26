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
  * `accept_awaiting_connect_request/1` - accepts next incoming connection
  * `reject_awaiting_connect_request/1` - rejects next incoming connection
  * `close_server_connection/2` - stops server's connection to given client
  * `send_data/3` - sends a packet through a server connection

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

  use Agent

  @max_payload_size 1316

  @type t :: pid()

  @type connection_id :: non_neg_integer()

  @type srt_server_conn :: {:srt_server_conn, connection_id(), stream_id :: String.t()}
  @type srt_server_conn_closed :: {:srt_server_conn_closed, connection_id()}
  @type srt_server_error :: {:srt_server_error, connection_id(), error :: String.t()}
  @type srt_data :: {:srt_data, connection_id(), data :: binary()}
  @type srt_server_connect_request ::
          {:srt_server_connect_request, address :: String.t(), stream_id :: String.t()}

  @type start_opt ::
          {:password, String.t()}
          | {:latency_ms, integer()}
          | {:rcvbuf, pos_integer()}
          | {:udp_rcvbuf, pos_integer()}
          | {:sndbuf, pos_integer()}
          | {:udp_sndbuf, pos_integer()}
          | {:sndtimeo, non_neg_integer()}

  @type start_opts :: [start_opt()]

  @doc """
  Starts a new SRT server binding to given address and port and links to current process.

  One may usually want to bind to `0.0.0.0` address.

  ## Options

    * `:password` - SRT passphrase (default: `""`)
    * `:latency_ms` - SRT socket latency in milliseconds (default: `-1`)
    * `:rcvbuf` - SRT-level receive buffer in bytes (`SRTO_RCVBUF`)
    * `:udp_rcvbuf` - OS kernel UDP receive buffer in bytes (`SRTO_UDP_RCVBUF`)
    * `:sndbuf` - SRT-level send buffer in bytes (`SRTO_SNDBUF`)
    * `:udp_sndbuf` - OS kernel UDP send buffer in bytes (`SRTO_UDP_SNDBUF`)
    * `:sndtimeo` - send timeout in milliseconds (`SRTO_SNDTIMEO`)

  ## Password Requirements

  If a password is provided, it must be between 10 and 79 characters long according to SRT specification.
  An empty string means no password authentication will be used.
  """
  @spec start_link(address :: String.t(), port :: non_neg_integer()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start_link(address, port) do
    do_start_link(address, port, [])
  end

  @spec start_link(address :: String.t(), port :: non_neg_integer(), String.t() | start_opts()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start_link(address, port, password) when is_binary(password) do
    do_start_link(address, port, password: password)
  end

  def start_link(address, port, opts) when is_list(opts) do
    do_start_link(address, port, opts)
  end

  @spec start_link(
          address :: String.t(),
          port :: non_neg_integer(),
          password :: String.t(),
          latency_ms :: integer()
        ) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start_link(address, port, password, latency_ms)
      when is_binary(password) and is_integer(latency_ms) do
    do_start_link(address, port, password: password, latency_ms: latency_ms)
  end

  @doc """
  Starts a new SRT server outside the supervision tree, binding to given address and port.

  One may usually want to bind to `0.0.0.0` address.

  Accepts the same options as `start_link/3`.

  ## Password Requirements

  If a password is provided, it must be between 10 and 79 characters long according to SRT specification.
  An empty string means no password authentication will be used.
  """
  @spec start(address :: String.t(), port :: non_neg_integer()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start(address, port) do
    do_start(address, port, [])
  end

  @spec start(address :: String.t(), port :: non_neg_integer(), String.t() | start_opts()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start(address, port, password) when is_binary(password) do
    do_start(address, port, password: password)
  end

  def start(address, port, opts) when is_list(opts) do
    do_start(address, port, opts)
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
  Acccepts the currently awaiting connection request.
  """
  @spec accept_awaiting_connect_request(t()) :: :ok | {:error, reason :: String.t()}
  def accept_awaiting_connect_request(agent) do
    if Process.alive?(agent) do
      server_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.accept_awaiting_connect_request(self(), server_ref)
    else
      {:error, "Server is not active"}
    end
  end

  @doc """
  Acccepts the currently awaiting connection request and starts a separate connection process
  """
  @spec accept_awaiting_connect_request_with_handler(ExLibSRT.Connection.Handler.t(), t()) ::
          {:ok, ExLibSRT.Connection.t()} | {:error, reason :: any()}
  def accept_awaiting_connect_request_with_handler(handler, agent) do
    with true <- Process.alive?(agent),
         server_ref = Agent.get(agent, & &1),
         {:ok, handler} <- ExLibSRT.Connection.start(handler),
         :ok <- ExLibSRT.Native.accept_awaiting_connect_request(handler, server_ref) do
      {:ok, handler}
    else
      false ->
        {:error, "Server is not active"}

      {:error, _reason} = error ->
        ExLibSRT.Connection.stop(handler)
        error
    end
  end

  @doc """
  Rejects the currently awaiting connection request.
  """
  @spec reject_awaiting_connect_request(t()) :: :ok | {:error, reason :: String.t()}
  def reject_awaiting_connect_request(agent) do
    if Process.alive?(agent) do
      server_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.reject_awaiting_connect_request(server_ref)
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
  Sends data through a server connection.
  """
  @spec send_data(connection_id(), binary(), t()) ::
          :ok | {:error, :payload_too_large | (reason :: String.t())}
  def send_data(connection_id, payload, agent)

  def send_data(_connection_id, payload, _agent) when byte_size(payload) > @max_payload_size,
    do: {:error, :payload_too_large}

  def send_data(connection_id, payload, agent) do
    if Process.alive?(agent) do
      server_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.send_server_data(connection_id, payload, server_ref)
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

  @known_opts [:password, :latency_ms, :rcvbuf, :udp_rcvbuf, :sndbuf, :udp_sndbuf, :sndtimeo]

  defp do_start_link(address, port, opts) do
    with {:ok, normalized} <- normalize_start_opts(opts),
         :ok <- validate_password(normalized.password),
         {:ok, server_ref} <-
           ExLibSRT.Native.start_server(
             address,
             port,
             normalized.password,
             normalized.latency_ms,
             normalized.socket_opts
           ) do
      Agent.start_link(fn -> server_ref end)
    else
      {:error, reason, error_code} -> {:error, reason, error_code}
      {:error, reason} -> {:error, reason, 0}
    end
  end

  defp do_start(address, port, opts) do
    with {:ok, normalized} <- normalize_start_opts(opts),
         :ok <- validate_password(normalized.password),
         {:ok, server_ref} <-
           ExLibSRT.Native.start_server(
             address,
             port,
             normalized.password,
             normalized.latency_ms,
             normalized.socket_opts
           ) do
      Agent.start(fn -> server_ref end, name: {:global, server_ref})
    else
      {:error, reason, error_code} -> {:error, reason, error_code}
      {:error, reason} -> {:error, reason, 0}
    end
  end

  defp normalize_start_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      with {:ok, _} <- Keyword.validate(opts, @known_opts),
           :ok <- validate_buffer_opts(opts),
           :ok <- validate_sndtimeo_opt(opts) do
        {:ok,
         %{
           password: Keyword.get(opts, :password, ""),
           latency_ms: Keyword.get(opts, :latency_ms, -1),
           socket_opts:
             Keyword.take(opts, [:rcvbuf, :udp_rcvbuf, :sndbuf, :udp_sndbuf, :sndtimeo])
         }}
      else
        {:error, invalid_keys} when is_list(invalid_keys) ->
          {:error,
           "Unsupported server options: " <>
             Enum.map_join(invalid_keys, ", ", &inspect/1)}

        {:error, _reason} = error ->
          error
      end
    else
      {:error, "Server options must be a keyword list"}
    end
  end

  @buffer_opt_keys [:rcvbuf, :udp_rcvbuf, :sndbuf, :udp_sndbuf]

  defp validate_buffer_opts(opts) do
    Enum.reduce_while(@buffer_opt_keys, :ok, fn key, :ok ->
      case Keyword.fetch(opts, key) do
        :error ->
          {:cont, :ok}

        {:ok, val} when is_integer(val) and val > 0 ->
          {:cont, :ok}

        {:ok, val} ->
          {:halt, {:error, "#{key} must be a positive integer, got: #{inspect(val)}"}}
      end
    end)
  end

  defp validate_sndtimeo_opt(opts) do
    case Keyword.fetch(opts, :sndtimeo) do
      :error ->
        :ok

      {:ok, val} when is_integer(val) and val >= 0 ->
        :ok

      {:ok, val} ->
        {:error, ":sndtimeo must be a non-negative integer, got: #{inspect(val)}"}
    end
  end

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
