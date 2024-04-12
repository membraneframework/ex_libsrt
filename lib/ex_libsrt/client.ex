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

  @type t :: reference()

  @type srt_client_started :: :srt_client_started
  @type srt_client_disconnected :: :srt_client_started
  @type srt_client_error :: {:srt_client_error, reason :: String.t()}

  @doc """
  Starts a new SRT connection to the target address and port.
  """
  @spec start(address :: String.t(), port :: non_neg_integer(), stream_id :: String.t()) ::
          {:ok, t()} | {:error, reason :: String.t(), error_code :: integer()}
  def start(address, port, stream_id) do
    ExLibSRT.Native.start_client(address, port, stream_id)
  end

  @doc """
  Stops the active client connection.
  """
  @spec stop(t()) :: :ok
  def stop(client) do
    ExLibSRT.Native.stop_client(client)
  end

  @doc """
  Sends data through the client connection.
  """
  @spec send_data(binary(), t()) :: :ok | {:error, reason :: String.t()}
  def send_data(payload, client) do
    ExLibSRT.Native.send_client_data(payload, client)
  end

  @doc """
  Reads socket statistics.
  """
  @spec read_socket_stats(t()) ::
          {:ok, ExLibSRT.SocketStats.t()} | {:error, reason :: String.t()}
  def read_socket_stats(client),
    do: ExLibSRT.Native.read_client_socket_stats(client)
end
