defmodule ExLibSRT.Native do
  @moduledoc false

  @typedoc "SRT client socket mode."
  @type client_mode :: :sender | :receiver

  @typedoc """
  SRT socket buffer options.

  All values are in bytes. A value of `-1` (or omission) means
  "use the SRT library default".

    * `:rcvbuf`      – SRT-level receive buffer (`SRTO_RCVBUF`, default ~12 MB)
    * `:udp_rcvbuf`  – OS kernel UDP receive buffer (`SRTO_UDP_RCVBUF`, default ~8 MB)
    * `:sndbuf`      – SRT-level send buffer (`SRTO_SNDBUF`, default ~12 MB)
    * `:udp_sndbuf`  – OS kernel UDP send buffer (`SRTO_UDP_SNDBUF`, default ~64 KB)
    * `:sndtimeo`    – send timeout in ms (`SRTO_SNDTIMEO`, default SRT value)
  """
  @type socket_opt ::
          {:rcvbuf, pos_integer()}
          | {:udp_rcvbuf, pos_integer()}
          | {:sndbuf, pos_integer()}
          | {:udp_sndbuf, pos_integer()}
          | {:sndtimeo, non_neg_integer()}

  @type socket_opts :: [socket_opt()]

  use Unifex.Loader

  @doc """
  Starts an SRT client in `:sender` mode with default socket options.
  """
  @spec start_client(String.t(), non_neg_integer(), String.t(), String.t(), integer()) ::
          {:ok, reference()} | {:error, String.t(), integer()}
  def start_client(address, port, stream_id, password, latency_ms) do
    start_client(address, port, stream_id, password, latency_ms, :sender, [])
  end

  @doc """
  Starts an SRT client with an explicit `mode` and default socket options.
  """
  @spec start_client(
          String.t(),
          non_neg_integer(),
          String.t(),
          String.t(),
          integer(),
          client_mode()
        ) ::
          {:ok, reference()} | {:error, String.t(), integer()}
  def start_client(address, port, stream_id, password, latency_ms, mode)
      when mode in [:sender, :receiver] do
    start_client(address, port, stream_id, password, latency_ms, mode, [])
  end

  def start_client(_address, _port, _stream_id, _password, _latency_ms, mode) do
    {:error, "Invalid client mode #{inspect(mode)}. Expected :sender or :receiver.", 0}
  end

  @doc """
  Starts an SRT client with an explicit `mode` and socket buffer options.

  `socket_opts` is a keyword list of buffer sizes (see `t:socket_opts/0`).
  Omitted keys default to `-1` (SRT library default).
  """
  @spec start_client(
          String.t(),
          non_neg_integer(),
          String.t(),
          String.t(),
          integer(),
          client_mode(),
          socket_opts()
        ) ::
          {:ok, reference()} | {:error, String.t(), integer()}
  def start_client(address, port, stream_id, password, latency_ms, mode, socket_opts)
      when mode in [:sender, :receiver] and is_list(socket_opts) do
    sender_mode = if mode == :sender, do: 1, else: 0

    start_client_native(
      address,
      port,
      stream_id,
      password,
      latency_ms,
      sender_mode,
      Keyword.get(socket_opts, :rcvbuf, -1),
      Keyword.get(socket_opts, :udp_rcvbuf, -1),
      Keyword.get(socket_opts, :sndbuf, -1),
      Keyword.get(socket_opts, :udp_sndbuf, -1)
    )
  end

  def start_client(_address, _port, _stream_id, _password, _latency_ms, mode, _socket_opts) do
    {:error, "Invalid client mode #{inspect(mode)}. Expected :sender or :receiver.", 0}
  end

  @doc """
  Starts an SRT server with default socket options.
  """
  @spec start_server(String.t(), non_neg_integer(), String.t(), integer()) ::
          {:ok, reference()} | {:error, String.t()}
  def start_server(address, port, password, latency_ms) do
    start_server(address, port, password, latency_ms, [])
  end

  @doc """
  Starts an SRT server with socket buffer options.

  `socket_opts` is a keyword list of buffer sizes (see `t:socket_opts/0`).
  Omitted keys default to `-1` (SRT library default).
  """
  @spec start_server(String.t(), non_neg_integer(), String.t(), integer(), socket_opts()) ::
          {:ok, reference()} | {:error, String.t()}
  def start_server(address, port, password, latency_ms, socket_opts)
      when is_list(socket_opts) do
    start_server(
      address,
      port,
      password,
      latency_ms,
      Keyword.get(socket_opts, :rcvbuf, -1),
      Keyword.get(socket_opts, :udp_rcvbuf, -1),
      Keyword.get(socket_opts, :sndbuf, -1),
      Keyword.get(socket_opts, :udp_sndbuf, -1),
      Keyword.get(socket_opts, :sndtimeo, -1)
    )
  end
end
