defmodule ExLibSRT.Native do
  @moduledoc false

  @typedoc "SRT client socket mode."
  @type client_mode :: :sender | :receiver

  use Unifex.Loader

  @doc """
  Starts an SRT client using an atom-based client mode.

  This is a developer-friendly wrapper around the native
  `start_client_with_mode/6` function.
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

    start_client_with_mode(
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
