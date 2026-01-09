defmodule ExLibSRT.Client do
  @moduledoc """
  Implementation of the SRT client.

  ## API
  The client API consinsts of the following functions:

  * `start/3` - starts a client connection to the server
  * `start/4` - starts a client connection to the server with password authentication
  * `start_link/3` - starts a client connection to the server and links to current process
  * `start_link/4` - starts a client connection to the server with password authentication and links to current process
  * `stop/1` - stops the client connection
  * `send_data/2` - sends a packet through the client connection

  ## Password Authentication

  When connecting to a server that requires password authentication:
  - Password must be between 10 and 79 characters long (SRT specification requirement: https://github.com/Haivision/srt/blob/master/docs/API/API-socket-options.md#srto_passphrase)
  - Empty string means no password authentication (default behavior)
  - Password must match the server's password

  A process starting the client will also receive the following notifications:
  * `t:srt_client_started/0`
  * `t:srt_client_disconnected/0`
  * `t:srt_client_error/0`
  """

  use Agent
  require Logger

  @type t :: pid()

  @type srt_client_started :: :srt_client_started
  @type srt_client_disconnected :: :srt_client_started
  @type srt_client_error :: {:srt_client_error, reason :: String.t()}

  @doc """
  Starts a new SRT connection to the target address and port and links to the current process.

  ## Password Authentication

  If a password is provided, it must be between 10 and 79 characters long according to SRT specification.
  An empty string means no password authentication will be used.
  """
  @spec start_link(address :: String.t(), port :: non_neg_integer(), stream_id :: String.t()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  @spec start_link(
          address :: String.t(),
          port :: non_neg_integer(),
          stream_id :: String.t(),
          password :: String.t()
        ) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start_link(address, port, stream_id, password \\ "") do
    with :ok <- validate_password(password),
         {:ok, client_ref} <- ExLibSRT.Native.start_client(address, port, stream_id, password, -1) do
      Agent.start_link(fn -> client_ref end)
    else
      {:error, reason, error_code} -> {:error, reason, error_code}
      {:error, reason} -> {:error, reason, 0}
    end
  end

  @doc """
  Starts a new SRT connection to the target address and port outside the supervision tree.

  ## Password Authentication

  If a password is provided, it must be between 10 and 79 characters long according to SRT specification.
  An empty string means no password authentication will be used.
  """
  @spec start(address :: String.t(), port :: non_neg_integer(), stream_id :: String.t()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  @spec start(
          address :: String.t(),
          port :: non_neg_integer(),
          stream_id :: String.t(),
          password :: String.t()
        ) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start(address, port, stream_id, password \\ "") do
    with :ok <- validate_password(password),
         {:ok, client_ref} <- ExLibSRT.Native.start_client(address, port, stream_id, password, -1) do
      Agent.start(fn -> client_ref end, name: {:global, client_ref})
    else
      {:error, reason, error_code} -> {:error, reason, error_code}
      {:error, reason} -> {:error, reason, 0}
    end
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
  @spec send_data(binary(), t()) :: :ok | {:error, :payload_too_large | (reason :: String.t())}
  def send_data(payload, agent)

  def send_data(payload, _agent) when byte_size(payload) > 1316, do: {:error, :payload_too_large}

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
  @spec read_socket_stats(t()) ::
          {:ok, ExLibSRT.SocketStats.t()} | {:error, reason :: String.t()}
  def read_socket_stats(agent) do
    if Process.alive?(agent) do
      client_ref = Agent.get(agent, & &1)
      ExLibSRT.Native.read_client_socket_stats(client_ref)
    else
      {:error, "Client is not active"}
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
