Mix.install([{:ex_libsrt, path: "../"}])


defmodule ConnectionHandler do
  @behaviour ExLibSRT.Connection.Handler

  require Logger

  defstruct [:registry]

  @impl true
  def init(%__MODULE__{registry: registry}) do
    %{registry: registry}
  end

  @impl true
  def handle_connected(conn_id, stream_id, state) do
    Logger.info("Connected with conn_id: #{conn_id} and stream_id: #{stream_id}")

    Registry.register(state.registry, "connections", conn_id)

    {:ok, Map.put(state, :conn_id, conn_id)}
  end

  @impl true
  def handle_disconnected(state) do
    Logger.info("Connection closed conn_id: #{state.conn_id}")
    :ok
  end

  @impl true
  def handle_data(data, state) do
    Logger.info("[#{state.conn_id}] Received data: #{data}")

    {:ok, state}
  end
end


defmodule Server do
  use GenServer

  require Logger

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def statistics(server, conn_id) do
    GenServer.call(server, {:statistics, conn_id})
  end

  def close_connection(server, conn_id) do
    GenServer.call(server, {:close_connection, conn_id})
  end

  @impl true
  def init(_args) do
    stream_ids = ["some_stream_id_1", "some_stream_id_2", "some_stream_id_3"]

    {:ok, server} = ExLibSRT.Server.start("0.0.0.0", 12_000, "", -1, stream_ids, self())

    {:ok, server}
  end

  @impl true
  def handle_info({:srt_server_conn, conn_id, _stream_id}, server) do
    {:ok, _conn} =
      ExLibSRT.Server.bind_with_handler(
        %ConnectionHandler{registry: ConnectionRegistry},
        server,
        conn_id
      )

    {:noreply, server}
  end

  @impl true
  def handle_info({:srt_server_rejected_client, stream_id}, server) do
    Logger.warning("Rejected connection attempt for unknown stream ID: #{stream_id}")

    {:noreply, server}
  end

  @impl true
  def handle_call({:statistics, conn_id}, _from, server) do
    {:ok, stats} = ExLibSRT.Server.read_socket_stats(conn_id, server)

    {:reply, stats, server}
  end

  @impl true
  def handle_call({:close_connection, conn_id}, _from, server) do
    :ok = ExLibSRT.Server.close_server_connection(conn_id, server)

    {:reply, :ok, server}
  end

  @impl true
  def terminate(_reason, _server) do
    Logger.info("Terminating server")
  end
end

{:ok, _registry} = Registry.start_link(keys: :duplicate, name: ConnectionRegistry)

{:ok, server} = Server.start_link()


clients =
  for i <- 1..3 do
    {:ok, client} = ExLibSRT.Client.start("127.0.0.1", 12_000, "some_stream_id_#{i}")

    receive do
      :srt_client_connected -> :ok
    end

    client
  end

Enum.each(clients, &ExLibSRT.Client.send_data("Hello world!", &1))

Process.sleep(200)

Registry.dispatch(ConnectionRegistry, "connections", fn entries ->
  for {_pid, conn_id} <- entries do
    stats = Server.statistics(server, conn_id)

    IO.puts(
      "Statistics for socket: #{conn_id}: #{inspect(Map.take(stats, [:byteRecvTotal, :pktRecv, :pktSentACK]))}"
    )

    Server.close_connection(server, conn_id)
  end
end)

Process.sleep(2_000)

GenServer.stop(server)
