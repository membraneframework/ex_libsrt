defmodule ExLibSRT.Client do
  @moduledoc """
  Implementation of the SRT client.

  ## API
  The client API consinsts of the following functions:

  * `start/3` - starts a client connection to the server
  * `stop/1` - stops the client connection
  * `send_data/2` - sencds a packet through the client connection

  A process starting the client will also receive the following notifications:
  * `t:srt_client_started/0`
  * `t:srt_client_disconnected/0`
  * `t:srt_client_error/0`
  """

  use Agent

  @type t :: pid()

  @type srt_client_started :: :srt_client_started
  @type srt_client_disconnected :: :srt_client_started
  @type srt_client_error :: {:srt_client_error, reason :: String.t()}

  @doc """
  Starts a new SRT connection to the target address and port and link to the current process.
  """
  @spec start_link(address :: String.t(), port :: non_neg_integer(), stream_id :: String.t()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start_link(address, port, stream_id) do
    case ExLibSRT.Native.start_client(address, port, stream_id) do
      {:ok, client_ref} ->
        Agent.start_link(fn -> client_ref end, name: {:global, client_ref})

      {:error, reason, error_code} ->
        {:error, reason, error_code}
    end
  end

  @doc """
  Starts a new SRT connection to the target address and port outside the supervision tree.
  """
  @spec start(address :: String.t(), port :: non_neg_integer(), stream_id :: String.t()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start(address, port, stream_id) do
    case ExLibSRT.Native.start_client(address, port, stream_id) do
      {:ok, client_ref} ->
        Agent.start(fn -> client_ref end, name: {:global, client_ref})

      {:error, reason, error_code} ->
        {:error, reason, error_code}
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
    client_ref = Agent.get(agent, & &1)
    ExLibSRT.Native.send_client_data(payload, client_ref)
  end

  @doc """
  Reads socket statistics.
  """
  @spec read_socket_stats(t()) ::
          {:ok, ExLibSRT.SocketStats.t()} | {:error, reason :: String.t()}
  def read_socket_stats(agent) do
    client_ref = Agent.get(agent, & &1)
    ExLibSRT.Native.read_client_socket_stats(client_ref)
  end
end
