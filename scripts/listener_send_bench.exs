Mix.Task.run("app.start")

{opts, _argv, _invalid} =
  OptionParser.parse(System.argv(),
    strict: [
      duration: :integer,
      clients: :integer,
      payload: :integer,
      port: :integer,
      latency: :integer,
      sndtimeo: :integer,
      batch: :integer,
      mode: :string
    ]
  )

duration_s = Keyword.get(opts, :duration, 60)
clients = Keyword.get(opts, :clients, 1)
payload_size = Keyword.get(opts, :payload, 1316)
port = Keyword.get(opts, :port, 19_000 + :rand.uniform(2000))
latency_ms = Keyword.get(opts, :latency, 120)
sndtimeo = Keyword.get(opts, :sndtimeo, -1)
mode = Keyword.get(opts, :mode, "single")
batch_size = Keyword.get(opts, :batch, 8)

if payload_size <= 0 or payload_size > 1316 do
  raise "payload must be in 1..1316"
end

if mode not in ["single", "many"] do
  raise "mode must be single|many"
end

if batch_size <= 0 or batch_size > 32 do
  raise "batch must be in 1..32"
end

parent = self()
recv_bytes = :atomics.new(1, [])
send_bytes = :atomics.new(1, [])
send_errors = :atomics.new(1, [])

defmodule BenchReceiver do
  def start(parent, recv_bytes, port, idx, latency_ms) do
    spawn_link(fn ->
      stream_id = "bench-#{idx}"

      {:ok, client} =
        ExLibSRT.Client.start_link("127.0.0.1", port, stream_id,
          mode: :receiver,
          latency_ms: latency_ms
        )

      send(parent, {:receiver_ready, self()})
      loop(client, recv_bytes)
    end)
  end

  defp loop(client, recv_bytes) do
    receive do
      {:bench_stop, from} ->
        ExLibSRT.Client.stop(client)
        send(from, {:bench_stopped, self()})

      {:srt_data, _conn_id, payload} ->
        :atomics.add_get(recv_bytes, 1, byte_size(payload))
        loop(client, recv_bytes)

      :srt_client_connected ->
        loop(client, recv_bytes)

      :srt_client_disconnected ->
        loop(client, recv_bytes)

      {:srt_client_error, _reason} ->
        loop(client, recv_bytes)

      _other ->
        loop(client, recv_bytes)
    end
  end
end

server_opts = [latency_ms: latency_ms, udp_rcvbuf: 67_108_864]
server_opts = if sndtimeo >= 0, do: Keyword.put(server_opts, :sndtimeo, sndtimeo), else: server_opts

{:ok, server} = ExLibSRT.Server.start_link("127.0.0.1", port, server_opts)

receivers =
  for idx <- 1..clients do
    BenchReceiver.start(parent, recv_bytes, port, idx, latency_ms)
  end

for _ <- 1..clients do
  receive do
    {:receiver_ready, _pid} -> :ok
  after
    5_000 -> raise "timed out waiting for receiver startup"
  end
end

for _ <- 1..clients do
  receive do
    {:srt_server_connect_request, _address, _stream_id} ->
      :ok = ExLibSRT.Server.accept_awaiting_connect_request(server)

    {:srt_server_send_telemetry, _q, _d, _r, _bps} ->
      :ok

    _other ->
      :ok
  after
    10_000 -> raise "timed out waiting for connect request"
  end
end

conn_ids =
  Enum.reduce_while(1..clients, [], fn _, acc ->
    receive do
      {:srt_server_conn, conn_id, _stream_id} ->
        {:cont, [conn_id | acc]}

      {:srt_server_send_telemetry, _q, _d, _r, _bps} ->
        {:cont, acc}

      _other ->
        {:cont, acc}
    after
      10_000 ->
        {:halt, acc}
    end
  end)

if length(conn_ids) != clients do
  raise "expected #{clients} connected clients, got #{length(conn_ids)}"
end

payload = :binary.copy(<<0>>, payload_size)
batch_payloads = List.duplicate(payload, batch_size)
deadline_ms = System.monotonic_time(:millisecond) + duration_s * 1000
sender_parent = self()

for conn_id <- conn_ids do
  spawn_link(fn ->
    send_loop = fn send_loop ->
      now = System.monotonic_time(:millisecond)

      if now >= deadline_ms do
        send(sender_parent, {:sender_done, self()})
      else
        result =
          if mode == "many" do
            ExLibSRT.Server.send_data_many(conn_id, batch_payloads, server)
          else
            ExLibSRT.Server.send_data(conn_id, payload, server)
          end

        case result do
          :ok ->
            sent_now = if mode == "many", do: payload_size * batch_size, else: payload_size
            :atomics.add_get(send_bytes, 1, sent_now)

          {:error, _reason} ->
            :atomics.add_get(send_errors, 1, 1)
        end

        send_loop.(send_loop)
      end
    end

    send_loop.(send_loop)
  end)
end

for _ <- 1..clients do
  receive do
    {:sender_done, _pid} -> :ok
  after
    duration_s * 3000 -> raise "timed out waiting for sender"
  end
end

stats =
  conn_ids
  |> Enum.map(&ExLibSRT.Server.read_socket_stats(&1, server))
  |> Enum.filter(&match?({:ok, _}, &1))
  |> Enum.map(fn {:ok, st} -> st end)

for pid <- receivers do
  send(pid, {:bench_stop, self()})
end

for _ <- receivers do
  receive do
    {:bench_stopped, _pid} -> :ok
  after
    5_000 -> :ok
  end
end

telemetry_samples =
  Stream.repeatedly(fn ->
    receive do
      {:srt_server_send_telemetry, queue_depth, enqueue_drops, send_retries, drain_rate_bps} ->
        {:ok, {queue_depth, enqueue_drops, send_retries, drain_rate_bps}}
    after
      0 ->
        :done
    end
  end)
  |> Enum.take_while(&(&1 != :done))
  |> Enum.map(fn {:ok, sample} -> sample end)

ExLibSRT.Server.stop(server)

sent = :atomics.get(send_bytes, 1)
recv = :atomics.get(recv_bytes, 1)
errors = :atomics.get(send_errors, 1)

send_mbps = sent * 8 / 1_000_000 / duration_s
recv_mbps = recv * 8 / 1_000_000 / duration_s

sum = fn fun -> Enum.reduce(stats, 0, fn st, acc -> acc + fun.(st) end) end

pkt_snd_drop = sum.(fn st -> st.pktSndDrop end)
pkt_retrans = sum.(fn st -> st.pktRetrans end)

mbps_send_rate_avg =
  case stats do
    [] -> 0.0
    list -> Enum.reduce(list, 0.0, fn st, acc -> acc + st.mbpsSendRate end) / length(list)
  end

{queue_depth_max, enqueue_drops_last, send_retries_last, drain_rate_bps_avg} =
  case telemetry_samples do
    [] ->
      {0, 0, 0, 0}

    samples ->
      qmax = samples |> Enum.map(&elem(&1, 0)) |> Enum.max()
      dlast = samples |> List.last() |> elem(1)
      rlast = samples |> List.last() |> elem(2)
      bavg =
        samples
        |> Enum.map(&elem(&1, 3))
        |> Enum.sum()
        |> Kernel./(length(samples))
        |> round()

      {qmax, dlast, rlast, bavg}
  end

IO.puts(
  "RESULT " <>
    "mode=#{mode} batch=#{batch_size} duration_s=#{duration_s} clients=#{clients} payload=#{payload_size} sndtimeo=#{sndtimeo} " <>
    "sent_bytes=#{sent} recv_bytes=#{recv} send_errors=#{errors} " <>
    "send_mbps=#{:erlang.float_to_binary(send_mbps, decimals: 3)} " <>
    "recv_mbps=#{:erlang.float_to_binary(recv_mbps, decimals: 3)} " <>
    "srt_mbps_send_rate=#{:erlang.float_to_binary(mbps_send_rate_avg, decimals: 3)} " <>
    "pkt_snd_drop=#{pkt_snd_drop} pkt_retrans=#{pkt_retrans} " <>
    "queue_depth_max=#{queue_depth_max} enqueue_drops=#{enqueue_drops_last} " <>
    "send_retries=#{send_retries_last} drain_rate_bps_avg=#{drain_rate_bps_avg}"
)
