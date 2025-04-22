Mix.install([{:ex_libsrt, path: "../"}])

defmodule Server do
  use GenServer

  require Logger

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def init(_args) do
    {:ok, server} = ExLibSRT.Server.start("0.0.0.0", 12_000)

    {:ok, %{server: server, packets: 0}}
  end

  @impl true
  def handle_info({:srt_server_connect_request, address, stream_id}, state) do
    Logger.info(
      "Receiving new connection request with stream id: #{stream_id} from address: #{address}"
    )

    :ok = ExLibSRT.Server.accept_awaiting_connect_request(state.server)

    {:noreply, state}
  end

  @impl true
  def handle_info({:srt_server_conn, conn_id, stream_id}, state) do
    Logger.info("Connection established with id: #{conn_id} for stream: #{stream_id}")

    {:noreply, state}
  end

  @impl true
  def handle_info({:srt_data, conn_id, payload}, state) do
    Logger.info("Received payload from connection: #{conn_id} #{byte_size(payload)}")

    {:noreply, %{state | packets: state.packets + 1}}
  end

  @impl true
  def handle_info({:srt_server_conn_closed, conn_id}, state) do
    Logger.info("Connection closed: #{conn_id}")

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, server) do
    Logger.info("Terminating server, total packets: #{server.packets}")
  end
end

{:ok, server} = Server.start_link()

Process.sleep(5_000)

{:ok, client} = ExLibSRT.Client.start("127.0.0.1", 12_000, "some_stream_id")

receive do
  :srt_client_connected -> :ok
end

# Process.sleep(2_000)
for _i <- 1..10_000 do
  payload = :crypto.strong_rand_bytes(1200)
  :ok = ExLibSRT.Client.send_data(payload, client)
end

Process.sleep(5000)

ExLibSRT.Client.stop(client)

Process.sleep(1000)

GenServer.stop(server)
