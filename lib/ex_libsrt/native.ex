defmodule ExLibSRT.Native do
  @moduledoc false

  @on_load :__on_load__

  def __on_load__ do
    path = :filename.join(:code.priv_dir(:ex_libsrt), ~c"libexsrt")

    case :erlang.load_nif(path, 0) do
      :ok ->
        on_load()
        :ok

      {:error, reason} ->
        raise "failed to load NIF library, reason: #{inspect(reason)}"
    end
  end

  def on_load() do
    :erlang.nif_error("nif not loaded")
  end

  def create_server(_address, _port) do
    :erlang.nif_error("nif not loaded")
  end

  def stop_server(_server) do
    :erlang.nif_error("nif not loaded")
  end

  def accept_awaiting_connect_request(_handler_pid, _server) do
    :erlang.nif_error("nif not loaded")
  end

  def reject_awaiting_connect_request(_server) do
    :erlang.nif_error("nif not loaded")
  end

  def close_server_connection(_connection_id, _server) do
    :erlang.nif_error("nif not loaded")
  end

  def read_server_socket_stats(_connection_id, _server) do
    :erlang.nif_error("nif not loaded")
  end

  def create_client(_address, _port, _stream_id) do
    :erlang.nif_error("nif not loaded")
  end

  def stop_client(_client) do
    :erlang.nif_error("nif not loaded")
  end

  def send_client_data(_payload, _client) do
    :erlang.nif_error("nif not loaded")
  end

  def read_client_socket_stats(_client) do
    :erlang.nif_error("nif not loaded")
  end
end
