defmodule ExLibSRT.Native do
  @moduledoc false

  @typedoc "SRT client socket mode."
  @type client_mode :: :sender | :receiver

  use Unifex.Loader

  @doc """
  Starts an SRT client in `:sender` mode.

  Use this when the client is expected to push data to the remote SRT listener,
  for example when calling `send_client_data/2`.
  """
  @spec start_client(String.t(), non_neg_integer(), String.t(), String.t(), integer()) ::
          {:ok, reference()} | {:error, String.t(), integer()}
  def start_client(address, port, stream_id, password, latency_ms) do
    start_client(address, port, stream_id, password, latency_ms, :sender)
  end

  @doc """
  Starts an SRT client with an explicit `mode` (`:sender` or `:receiver`).

  This is the developer-friendly client startup API used by higher-level modules.

  It converts the Elixir atom mode to the native `sender_mode` flag internally,
  so callers never need to pass raw integers (`1` / `0`).

  - Use `:sender` when the client should send payloads with `send_client_data/2`.
  - Use `:receiver` when the client should consume incoming `{:srt_data, ...}` messages.
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
    sender_mode = if mode == :sender, do: 1, else: 0

    start_client_native(
      address,
      port,
      stream_id,
      password,
      latency_ms,
      sender_mode
    )
  end

  def start_client(_address, _port, _stream_id, _password, _latency_ms, mode) do
    {:error, "Invalid client mode #{inspect(mode)}. Expected :sender or :receiver.", 0}
  end
end
