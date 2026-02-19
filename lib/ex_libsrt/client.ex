defmodule ExLibSRT.Client do
  @moduledoc """
  Implementation of the SRT client.

  ## API

  Preferred API (keyword options):

    * `start/4` - starts a client connection outside a supervision tree
    * `start_link/4` - starts a client connection and links it to the caller

  Supported options:

    * `:password` - SRT passphrase (default: `""`)
    * `:latency_ms` - SRT socket latency in milliseconds (default: `-1`)
    * `:mode` - `:sender | :receiver` (default: `:sender`)

  Backwards-compatible API (still supported):

    * `start/3`
    * `start/4` with password as 4th argument
    * `start_link/3`
    * `start_link/4` with password as 4th argument
    * `start_link/5` with password and latency arguments

  A process starting the client will receive the following notifications:

    * `t:srt_client_started/0`
    * `t:srt_client_disconnected/0`
    * `t:srt_client_error/0`
  """

  use Agent

  @default_password ""
  @default_latency_ms -1
  @default_mode :sender
  @max_payload_size 1316

  @type t :: pid()
  @type mode :: ExLibSRT.Native.client_mode()
  @type srt_client_started :: :srt_client_started
  @type srt_client_disconnected :: :srt_client_disconnected
  @type srt_client_error :: {:srt_client_error, reason :: String.t()}

  @type start_opt ::
          {:password, String.t()}
          | {:latency_ms, integer()}
          | {:mode, mode()}

  @type start_opts :: [start_opt()]

  @doc """
  Starts a new SRT connection to the target address and port and links to the current process.

  This function supports both modern options-based calls and backwards-compatible positional args.
  """
  @spec start_link(String.t(), non_neg_integer(), String.t()) ::
          {:ok, t()} | {:error, String.t(), integer()}
  @spec start_link(String.t(), non_neg_integer(), String.t(), String.t()) ::
          {:ok, t()} | {:error, String.t(), integer()}
  @spec start_link(String.t(), non_neg_integer(), String.t(), String.t(), integer()) ::
          {:ok, t()} | {:error, String.t(), integer()}
  @spec start_link(String.t(), non_neg_integer(), String.t(), start_opts()) ::
          {:ok, t()} | {:error, String.t(), integer()}
  def start_link(address, port, stream_id) do
    start_link(address, port, stream_id, [])
  end

  def start_link(address, port, stream_id, password) when is_binary(password) do
    start_link(address, port, stream_id, password, @default_latency_ms)
  end

  def start_link(address, port, stream_id, opts) when is_list(opts) do
    do_start_link(address, port, stream_id, opts)
  end

  def start_link(address, port, stream_id, password, latency_ms)
      when is_binary(password) and is_integer(latency_ms) do
    do_start_link(address, port, stream_id, password: password, latency_ms: latency_ms)
  end

  @doc """
  Starts a new SRT connection to the target address and port outside the supervision tree.

  This function supports both modern options-based calls and backwards-compatible positional args.
  """
  @spec start(String.t(), non_neg_integer(), String.t()) ::
          {:ok, t()} | {:error, String.t(), integer()}
  @spec start(String.t(), non_neg_integer(), String.t(), String.t()) ::
          {:ok, t()} | {:error, String.t(), integer()}
  @spec start(String.t(), non_neg_integer(), String.t(), start_opts()) ::
          {:ok, t()} | {:error, String.t(), integer()}
  def start(address, port, stream_id) do
    start(address, port, stream_id, [])
  end

  def start(address, port, stream_id, password) when is_binary(password) do
    do_start(address, port, stream_id, password: password)
  end

  def start(address, port, stream_id, opts) when is_list(opts) do
    do_start(address, port, stream_id, opts)
  end

  @doc """
  Stops the active client connection.
  """
  @spec stop(t()) :: :ok
  def stop(agent) do
    client_ref = Agent.get(agent, & &1)
    ExLibSRT.Native.stop_client(client_ref)
    Agent.stop(agent)
  end

  @doc """
  Sends data through the client connection.
  """
  @spec send_data(binary(), t()) :: :ok | {:error, :payload_too_large | String.t()}
  def send_data(payload, _agent) when byte_size(payload) > @max_payload_size,
    do: {:error, :payload_too_large}

  def send_data(payload, agent) do
    if Process.alive?(agent) do
      client_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.send_client_data(payload, client_ref)
    else
      {:error, "Client is not active"}
    end
  end

  @doc """
  Reads socket statistics.
  """
  @spec read_socket_stats(t()) :: {:ok, ExLibSRT.SocketStats.t()} | {:error, String.t()}
  def read_socket_stats(agent) do
    if Process.alive?(agent) do
      client_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.read_client_socket_stats(client_ref)
    else
      {:error, "Client is not active"}
    end
  end

  defp do_start_link(address, port, stream_id, opts) do
    with {:ok, normalized_opts} <- normalize_start_opts(opts),
         :ok <- validate_password(normalized_opts.password),
         {:ok, client_ref} <- start_native_client(address, port, stream_id, normalized_opts) do
      Agent.start_link(fn -> client_ref end)
    else
      {:error, reason, error_code} -> {:error, reason, error_code}
      {:error, reason} -> {:error, reason, 0}
    end
  end

  defp do_start(address, port, stream_id, opts) do
    with {:ok, normalized_opts} <- normalize_start_opts(opts),
         :ok <- validate_password(normalized_opts.password),
         {:ok, client_ref} <- start_native_client(address, port, stream_id, normalized_opts) do
      Agent.start(fn -> client_ref end, name: {:global, client_ref})
    else
      {:error, reason, error_code} -> {:error, reason, error_code}
      {:error, reason} -> {:error, reason, 0}
    end
  end

  defp start_native_client(address, port, stream_id, opts) do
    ExLibSRT.Native.start_client(
      address,
      port,
      stream_id,
      opts.password,
      opts.latency_ms,
      opts.mode
    )
  end

  defp normalize_start_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      with {:ok, _validated_opts} <- Keyword.validate(opts, [:password, :latency_ms, :mode]),
           latency_ms <- Keyword.get(opts, :latency_ms, @default_latency_ms),
           :ok <- validate_latency_ms(latency_ms),
           mode <- Keyword.get(opts, :mode, @default_mode),
           :ok <- validate_mode(mode) do
        {:ok,
         %{
           password: Keyword.get(opts, :password, @default_password),
           latency_ms: latency_ms,
           mode: mode
         }}
      else
        {:error, invalid_keys} when is_list(invalid_keys) ->
          {:error,
           "Unsupported client options: " <>
             Enum.map_join(invalid_keys, ", ", &inspect/1)}

        {:error, _reason} = error ->
          error
      end
    else
      {:error, "Client options must be a keyword list"}
    end
  end

  defp normalize_start_opts(_opts), do: {:error, "Client options must be a keyword list"}

  defp validate_latency_ms(latency_ms) when is_integer(latency_ms), do: :ok

  defp validate_latency_ms(latency_ms),
    do: {:error, "Latency must be an integer, got: #{inspect(latency_ms)}"}

  defp validate_mode(mode) when mode in [:sender, :receiver], do: :ok

  defp validate_mode(mode),
    do: {:error, "Invalid client mode #{inspect(mode)}. Expected :sender or :receiver."}

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
